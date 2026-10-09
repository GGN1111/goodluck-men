import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:signalready_pocket/data/database.dart';
import 'package:signalready_pocket/data/repositories/checklist_repository.dart';
import 'package:signalready_pocket/data/repositories/incident_repository.dart';
import 'package:signalready_pocket/data/repositories/warning_repository.dart';
import 'package:signalready_pocket/domain/analyze_advisory.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/inference/enrichment_pipeline.dart';
import 'package:signalready_pocket/inference/fastpath_classifier.dart';
import 'package:signalready_pocket/inference/inference_types.dart';
import 'package:signalready_pocket/inference/template_checklists.dart';
import 'package:signalready_pocket/ingest/intake.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_engine.dart';

/// T023 — US1 offline parse smoke (quickstart V1 end-to-end on a host):
/// paste → fast-path skeleton persisted → fake-enrichment validated →
/// history row + trilingual steps + latency numbers, all with zero network.
void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  final tempDir = Directory.systemTemp.createTempSync('sr_smoke_');
  var dbCounter = 0;

  Future<SignalReadyDatabase> openDb() => SignalReadyDatabase.open(
      overridePath: p.join(tempDir.path, 'smoke_${dbCounter++}.db'));

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // temp cleanup is best-effort
    }
  });

  AnalyzeAdvisory buildAnalyze(
    SignalReadyDatabase store, {
    EnrichmentPipeline? pipeline,
  }) {
    final incidents = IncidentRepository(store.db);
    return AnalyzeAdvisory(
      intake: IntakeService(),
      classifier: const FastPathClassifier(),
      templates: const TemplateChecklists(),
      incidents: incidents,
      steps: ChecklistRepository(store.db),
      warnings: WarningRepository(store.db),
      pipeline: pipeline,
    );
  }

  const floodNotice = 'FLASH FLOOD: Lumikas na agad! Marikina River alarm 2. '
      'Tumaas ang tubig sa Zone 4.';

  test('skeleton → enrichment → persistence with separate latencies',
      () async {
    final store = await openDb();
    final fake = FakeInferenceEngine(payloadBuilder: floodPayload);
    final analyze = buildAnalyze(store,
        pipeline: EnrichmentPipeline(engine: fake));

    AnalyzedOutcome? skeleton;
    final outcome = await analyze(floodNotice,
        onSkeletonReady: (s) => skeleton = s);

    expect(outcome, isA<AnalyzedOutcome>());
    final enriched = outcome as AnalyzedOutcome;

    // Fast-path skeleton arrived first (SC-001 first number, ≤2s).
    expect(skeleton, isNotNull);
    expect(skeleton!.record.status, AnalysisStatus.skeleton);
    expect(skeleton!.skeletonMs, lessThan(2000));
    expect(skeleton!.enriched, isFalse);
    // A1: red flags ride along with the skeleton (before enrichment runs).
    expect(
      skeleton!.warnings.map((w) => w.code.contractName),
      contains('EVAC_CENTER'),
    );

    // Enrichment applied (SC-001 second number, reported separately).
    expect(enriched.enriched, isTrue);
    expect(enriched.enrichmentMs, isNotNull);
    expect(enriched.record.status, AnalysisStatus.enriched);
    expect(enriched.record.crisisType, CrisisType.flood);
    expect(enriched.record.severity, SeverityState.alert);
    expect(enriched.record.summary.isComplete, isTrue);

    // Both stages persisted: one incident, template steps, merged warnings.
    final incidents = IncidentRepository(store.db);
    final all = await incidents.getAll();
    expect(all, hasLength(1));
    final saved = all.first;
    expect(saved.id, isNotNull);
    expect(saved.sourceText, contains('FLASH FLOOD'));
    expect(saved.status, AnalysisStatus.enriched);

    // A5 (US2/T027): enrichment merged the LLM steps in place — template
    // rows rewritten to the payload's refined copy, ids/state preserved.
    final savedSteps =
        await ChecklistRepository(store.db).forIncident(saved.id!);
    expect(savedSteps, hasLength(2),
        reason: 'merged to the enriched payload step count');
    for (final step in savedSteps) {
      expect(step.text.isComplete, isTrue, reason: 'steps must be trilingual');
      expect(step.origin, StepOrigin.llm);
    }

    // T032 (US3): fast-path red flags persist at skeleton time and the LLM
    // copy merges alongside by code — the flood notice omits an evacuation
    // center (fastpath) while the payload flags the hotline (llm).
    final savedWarnings =
        await WarningRepository(store.db).forIncident(saved.id!);
    expect(savedWarnings, hasLength(2));
    final byCode = {
      for (final w in savedWarnings) w.code: w,
    };
    expect(byCode[WarningCode.evacCenter]?.origin, WarningOrigin.fastpath);
    expect(byCode[WarningCode.hotline]?.origin, WarningOrigin.llm);
    for (final w in savedWarnings) {
      expect(w.text.isComplete, isTrue, reason: 'warnings must be trilingual');
    }

    await store.close();
  });

  test('invalid first attempt triggers exactly one repair request', () async {
    final store = await openDb();
    final fake = FakeInferenceEngine();
    final broken = floodPayload(InferenceRequest(
      analysisId: 'dummy',
      systemPrompt: '',
      userText: '',
    ));
    fake.scripts.add([
      const CompletedEvent('the model rambles instead of emitting JSON'),
    ]);
    fake.scripts.add([
      CompletedEvent(jsonEncode(broken)),
    ]);
    final analyze = buildAnalyze(store,
        pipeline: EnrichmentPipeline(engine: fake));

    final outcome = await analyze(floodNotice);
    expect(outcome, isA<AnalyzedOutcome>());
    expect((outcome as AnalyzedOutcome).enriched, isTrue);

    expect(fake.requests, hasLength(2));
    expect(fake.requests.first.stage, InferenceStage.enrich);
    expect(fake.requests.last.stage, InferenceStage.repair);
    expect(fake.requests.last.repairErrors, isNotEmpty);

    await store.close();
  });

  test('engine failure degrades to failed brief with notice (FR-014)',
      () async {
    final store = await openDb();
    final fake = FakeInferenceEngine()
      ..failure = const FailedEvent('lib_missing', 'no llama.cpp here');
    final analyze = buildAnalyze(store,
        pipeline: EnrichmentPipeline(engine: fake));

    final outcome = await analyze(floodNotice);
    expect(outcome, isA<AnalyzedOutcome>());
    final degraded = outcome as AnalyzedOutcome;
    expect(degraded.enriched, isFalse);
    expect(degraded.record.status, AnalysisStatus.failed);
    expect(degraded.notice, isNotNull);
    expect(degraded.record.summary.isComplete, isTrue,
        reason: 'skeleton content must survive failure');

    await store.close();
  });

  test('no model available → skeleton-only with notice', () async {
    final store = await openDb();
    final analyze = buildAnalyze(store, pipeline: null);

    final outcome = await analyze(floodNotice);
    expect(outcome, isA<AnalyzedOutcome>());
    final skeletonOnly = outcome as AnalyzedOutcome;
    expect(skeletonOnly.enriched, isFalse);
    expect(skeletonOnly.record.status, AnalysisStatus.skeleton);
    expect(skeletonOnly.notice, isNotNull);
    expect(skeletonOnly.enrichmentMs, isNull);

    await store.close();
  });

  test('non-emergency input never fabricates a crisis', () async {
    final store = await openDb();
    final analyze = buildAnalyze(store, pipeline: null);

    final outcome =
        await analyze('Grocery list for the week: rice, eggs, detergent.');
    expect(outcome, isA<NoEmergencyOutcome>());

    final all = await IncidentRepository(store.db).getAll();
    expect(all, isEmpty,
        reason: 'no-emergency input must not persist fake incidents');

    await store.close();
  });
}
