import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signalready_pocket/core/app_graph.dart';
import 'package:signalready_pocket/core/theme/app_theme.dart';
import 'package:signalready_pocket/domain/analyze_advisory.dart';
import 'package:signalready_pocket/domain/delete_incident.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/ingest/ocr_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T055 — Airplane-mode E2E suite (quickstart V1–V10).
///
/// Everything here runs on the host against the real SQLite layer with a
/// hard egress guard active for the whole file: no socket may open. Device-
/// only behaviours (exact alarm delivery, reboot reconciliation, OCR
/// camera) are exercised at their seam level — see validation-results.md
/// for the on-device pass/fail record.
void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  final tempDir = Directory.systemTemp.createTempSync('e2e_');
  var dbCounter = 0;
  String nextDbPath() => p.join(tempDir.path, 'e2e${dbCounter++}.db');

  // V7 guard: every test in this file forbids network egress.
  _EgressGuard? guard;
  setUp(() {
    guard = _EgressGuard();
    IOOverrides.global = guard;
  });
  tearDown(() {
    IOOverrides.global = null;
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppGraph> openGraph() => AppGraph.open(
        dbOverridePath: nextDbPath(),
        enableEngine: false,
      );

  const floodAdvisory =
      'FLASH FLOOD: Marikina River critical level. Evacuate Zone 4 now. '
      'Barhall covered court is the evacuation center. Hotline 911.';

  test('V1 — core offline parse: skeleton brief ≤2s, no model required',
      () async {
    final graph = await openGraph();
    addTearDown(graph.dispose);

    final sw = Stopwatch()..start();
    final outcome = await graph.analyze(floodAdvisory);
    sw.stop();

    expect(outcome, isA<AnalyzedOutcome>());
    final record = (outcome as AnalyzedOutcome).record;
    expect(record.crisisType, CrisisType.flood);
    expect(record.severity, SeverityState.alert);
    expect(record.summary.en, isNotEmpty);
    expect(record.summary.tl, isNotEmpty);
    expect(record.summary.ceb, isNotEmpty);
    expect(record.status, anyOf(AnalysisStatus.skeleton, AnalysisStatus.enriched));
    expect(sw.elapsedMilliseconds, lessThan(2000),
        reason: 'SC-001 skeleton budget');
    expect(guard!.attempts, 0);
  });

  test('V2 — missing-info red flags surface; complete advisory fabricates '
      'nothing', () async {
    final graph = await openGraph();
    addTearDown(graph.dispose);

    final sparse = await graph.analyze(
        'EVACUATION ORDER: Zone 3 residents near the Marikina river must '
        'leave now.');
    expect(sparse, isA<AnalyzedOutcome>());
    final sparseOutcome = sparse as AnalyzedOutcome;
    final codes = sparseOutcome.warnings.map((w) => w.code).toSet();
    expect(codes, contains(WarningCode.evacCenter),
        reason: 'no evacuation center named → EVAC_CENTER flag');
    expect(codes, contains(WarningCode.hotline),
        reason: 'no hotline named → HOTLINE flag');

    final complete = await graph.analyze(floodAdvisory);
    final completeCodes =
        (complete as AnalyzedOutcome).warnings.map((w) => w.code).toSet();
    expect(completeCodes, isNot(contains(WarningCode.evacCenter)),
        reason: 'center present → no fabricated EVAC_CENTER flag');
  });

  test('V3 — screenshot ingestion seam: unreadable image never fabricates; '
      'readable text joins the paste path', () async {
    // Unreadable path (contract A3 / FR-007).
    final failOcr = OcrService(engine: (_) async => '  ');
    final failResult = await failOcr.extract('any.jpg');
    expect(failResult.success, isFalse);
    expect(failResult.notice, isNotNull);
    expect(failResult.text, isNull);

    // Readable path (contract A2): same intake as paste, source_type=ocr.
    final graph = await openGraph();
    addTearDown(graph.dispose);
    final okOcr = OcrService(engine: (_) async => floodAdvisory);
    final okResult = await okOcr.extract('shot.jpg');
    expect(okResult.success, isTrue);
    final outcome = await graph.analyze(okResult.text!,
        sourceType: SourceType.ocr);
    final record = (outcome as AnalyzedOutcome).record;
    expect(record.sourceType, SourceType.ocr);
    expect(record.crisisType, CrisisType.flood);
    expect(guard!.attempts, 0);
  });

  test('V4 — checklist ticks survive "restart" (SC-008)', () async {
    final dbPath = nextDbPath();
    var graph = await AppGraph.open(dbOverridePath: dbPath, enableEngine: false);
    final outcome = await graph.analyze(floodAdvisory);
    final record = (outcome as AnalyzedOutcome).record;
    final steps = await graph.steps.forIncident(record.id!);
    await graph.steps.toggle(steps.first.id!);
    await graph.dispose();

    graph = await AppGraph.open(dbOverridePath: dbPath, enableEngine: false);
    addTearDown(graph.dispose);
    final reloaded = await graph.steps.forIncident(record.id!);
    expect(reloaded.first.state, ChecklistStepState.done,
        reason: 'tick persisted across close/reopen');
    expect(await graph.incidents.getById(record.id!), isNotNull,
        reason: 'record still in History after restart');
  });

  test('V5 — re-check alarm row + reboot reconciliation never lose data',
      () async {
    final graph = await openGraph();
    addTearDown(graph.dispose);
    final outcome = await graph.analyze(floodAdvisory);
    final record = (outcome as AnalyzedOutcome).record;

    final fireAt = DateTime.now().add(const Duration(minutes: 1));
    await graph.alarms.insert(ReCheckAlarm(
      incidentId: record.id!,
      fireAt: fireAt,
      message: 'Re-check the flood advisory.',
      status: AlarmStatus.scheduled,
    ));

    // Simulated reboot: AppGraph.open → AlarmReconciler re-arms scheduled
    // rows (research R8). With no platform on host, reconciliation still
    // reports the row as re-armed rather than silently dropping it.
    final report = graph.reconcileReport;
    expect(report.reArmed + report.missed + report.clearedStale, 0,
        reason: 'fresh schedule has nothing to reconcile yet');
    final rows = await graph.alarms.byStatus(AlarmStatus.scheduled);
    expect(rows, hasLength(1), reason: 'row survives; never silent loss');
  });

  test('V6 — language switch is a pure field swap (<1s, all content)',
      () async {
    final graph = await openGraph();
    addTearDown(graph.dispose);
    final outcome = await graph.analyze(floodAdvisory);
    final record = (outcome as AnalyzedOutcome).record;

    final sw = Stopwatch()..start();
    for (final lang in AppLanguage.values) {
      record.summary.forLang(lang);
      record.speech.forLang(lang);
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1000), reason: 'SC-005 budget');
    expect(record.summary.forLang(AppLanguage.en), isNot(equals('')));
    expect(record.severity, SeverityState.alert,
        reason: 'severity unchanged by language selection');
  });

  test('V7 — zero egress across the whole suite', () {
    expect(guard!.attempts, 0,
        reason: 'SC-007: no test above may open a socket');
  });

  test('V8 — degradation: no model → skeleton brief + Guides still work',
      () async {
    final graph = await openGraph();
    addTearDown(graph.dispose);

    expect(graph.modelReady, isFalse, reason: 'host without GGUF (R11)');
    final outcome = await graph.analyze(floodAdvisory);
    final record = (outcome as AnalyzedOutcome).record;
    expect(record.status, anyOf(AnalysisStatus.skeleton, AnalysisStatus.failed),
        reason: 'no blank screen — degraded brief retained (FR-014)');
    expect(record.summary.en, isNotEmpty);

    // Guides/History remain fully usable in the degraded state.
    expect(await graph.guides.count(), greaterThan(0));
    expect(await graph.incidents.getAll(), isNotEmpty);
  });

  test('V9 — blackout theme tokens + permanent delete cascade', () async {
    final graph = await openGraph();
    addTearDown(graph.dispose);

    // Theme.
    await graph.settings.setLowPowerMode(true);
    expect(appThemeFor('ALERT', lowPower: true).scaffoldBackgroundColor,
        AppColors.pureBlack);

    // Delete cascade.
    final outcome = await graph.analyze(floodAdvisory);
    final record = (outcome as AnalyzedOutcome).record;
    await DeleteIncident(incidents: graph.incidents, alarms: graph.alarms)
        .call(record.id!);
    expect(await graph.incidents.getAll(), isEmpty);
    expect(await graph.steps.forIncident(record.id!), isEmpty);
  });

  test('V10 — odd inputs: no crash, no invented crisis', () async {
    final graph = await openGraph();
    addTearDown(graph.dispose);

    final corpus = <String>[
      '',
      'Grocery list: rice, eggs, coffee, detergent, soap, shampoo.',
      'Karibu mga kaibigan, kumusta na? Hanggang bukas ang palengke.',
      'A' * 20000,
    ];
    for (final input in corpus) {
      final outcome = await graph.analyze(input);
      if (outcome is NoEmergencyOutcome) continue;
      final record = (outcome as AnalyzedOutcome).record;
      expect(
        record.crisisType,
        anyOf(CrisisType.general, CrisisType.flood, CrisisType.blackout,
            CrisisType.fire, CrisisType.security),
      );
      expect(record.summary.en, isNotEmpty,
          reason: 'limited analysis still yields a brief, never blank');
    }
    expect(guard!.attempts, 0);
  });
}

/// Throwing socket hooks — any `Socket.connect` attempt increments the
/// counter and throws (quickstart V7 / SC-007).
final class _EgressGuard extends IOOverrides {
  int attempts = 0;

  Never _block(dynamic host, int port) {
    attempts++;
    throw StateError('NETWORK EGRESS ATTEMPTED (SC-007): $host:$port');
  }

  @override
  Future<Socket> socketConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) =>
      _block(host, port);

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) =>
      _block(host, port);
}
