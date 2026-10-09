import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signalready_pocket/data/database.dart';
import 'package:signalready_pocket/data/repositories/checklist_repository.dart';
import 'package:signalready_pocket/data/repositories/incident_repository.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/inference/merge_enriched.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T027 — enrichment merge (contracts/ui-actions.md A5): ids and tick
/// state survive a rewrite; surplus/shortfall incoming lists resize safely.
void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  final tempDir = Directory.systemTemp.createTempSync('sr_merge_');
  var dbCounter = 0;

  Future<(SignalReadyDatabase, ChecklistRepository, int)>
      openWithSteps() async {
    final store = await SignalReadyDatabase.open(
        overridePath: p.join(tempDir.path, 'merge_${dbCounter++}.db'));
    final incidentId = await IncidentRepository(store.db).insert(
      IncidentRecord(
        createdAt: DateTime.now(),
        sourceType: SourceType.text,
        sourceText: 'verbatim source',
        crisisType: CrisisType.flood,
        severity: SeverityState.alert,
        summary: const LocalizedText(en: 's', tl: 's', ceb: 's'),
        speech: const LocalizedText(en: 'p', tl: 'p', ceb: 'p'),
        status: AnalysisStatus.skeleton,
      ),
    );
    final repo = ChecklistRepository(store.db);
    await repo.insertAll([
      ActionStep(
        incidentId: incidentId,
        priority: 1,
        text: const LocalizedText(en: 'T1', tl: 'T1', ceb: 'T1'),
        state: ChecklistStepState.done,
        origin: StepOrigin.template,
      ),
      ActionStep(
        incidentId: incidentId,
        priority: 2,
        text: const LocalizedText(en: 'T2', tl: 'T2', ceb: 'T2'),
        state: ChecklistStepState.pending,
        origin: StepOrigin.template,
      ),
      ActionStep(
        incidentId: incidentId,
        priority: 3,
        text: const LocalizedText(en: 'T3', tl: 'T3', ceb: 'T3'),
        state: ChecklistStepState.pending,
        origin: StepOrigin.template,
      ),
    ]);
    return (store, repo, incidentId);
  }

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // temp cleanup is best-effort
    }
  });

  List<EnrichedStep> enriched(List<String> en, {int startPriority = 1}) => [
        for (var i = 0; i < en.length; i++)
          EnrichedStep(
            priority: startPriority + i,
            origin: StepOrigin.llm,
            text: LocalizedText(
                en: en[i], tl: '${en[i]} TL', ceb: '${en[i]} CEB'),
          ),
      ];

  test('rewrites text in place: ids and user ticks preserved (A5)', () async {
    final (store, repo, incidentId) = await openWithSteps();
    addTearDown(store.close);

    final existing = await repo.forIncident(incidentId);
    final plan = mergeEnrichedChecklist(
      incidentId: incidentId,
      existing: existing,
      incoming: enriched(['L1', 'L2', 'L3']),
    );
    expect(plan.removeIds, isEmpty);
    expect(plan.inserts, isEmpty);
    expect(plan.replacements, hasLength(3));

    final merged = await applyChecklistMerge(repo, plan);
    expect(merged, hasLength(3));
    // Same SQLite ids (in priority order), user state untouched.
    expect(merged.map((s) => s.id).toList(),
        existing.map((s) => s.id).toList());
    expect(merged[0].state, ChecklistStepState.done,
        reason: 'the user tick on step 1 must survive enrichment');
    expect(merged[1].state, ChecklistStepState.pending);
    // Content replaced, origin switched to llm.
    expect(merged.map((s) => s.text.en).toList(), ['L1', 'L2', 'L3']);
    expect(merged.every((s) => s.origin == StepOrigin.llm), isTrue);
    expect(merged.every((s) => s.text.isComplete), isTrue,
        reason: 'merged steps stay trilingual');

    // Persistence: reload proves the rewrite hit SQLite, not just memory.
    final reloaded = await repo.forIncident(incidentId);
    expect(reloaded[0].state, ChecklistStepState.done);
    expect(reloaded.map((s) => s.text.en).toList(), ['L1', 'L2', 'L3']);
  });

  test('fewer incoming steps removes surplus; more inserts (cap safe)',
      () async {
    final (store, repo, incidentId) = await openWithSteps();
    addTearDown(store.close);
    final existing = await repo.forIncident(incidentId);

    // Shortfall: 3 existing, 1 incoming → 2 removed.
    final shrink = mergeEnrichedChecklist(
      incidentId: incidentId,
      existing: existing,
      incoming: enriched(['ONLY']),
    );
    expect(shrink.replacements, hasLength(1));
    expect(shrink.removeIds, hasLength(2));
    final afterShrink = await applyChecklistMerge(repo, shrink);
    expect(afterShrink, hasLength(1));
    expect(afterShrink.single.text.en, 'ONLY');
    expect(afterShrink.single.state, ChecklistStepState.done,
        reason: 'the surviving step keeps its tick');

    // Growth: 1 existing, 3 incoming → 2 fresh pending inserts.
    final grow = mergeEnrichedChecklist(
      incidentId: incidentId,
      existing: afterShrink,
      incoming: enriched(['G1', 'G2', 'G3']),
    );
    expect(grow.replacements, hasLength(1));
    expect(grow.inserts, hasLength(2));
    expect(grow.removeIds, isEmpty);
    final afterGrow = await applyChecklistMerge(repo, grow);
    expect(afterGrow, hasLength(3));
    expect(afterGrow.first.state, ChecklistStepState.done);
    expect(afterGrow.skip(1).every((s) => s.state == ChecklistStepState.pending),
        isTrue);
    expect(afterGrow.map((s) => s.priority).toList(), [1, 2, 3]);
  });

  test('merge never exceeds the 5-step data-model cap', () {
    final plan = mergeEnrichedChecklist(
      incidentId: 1,
      existing: const [],
      incoming: enriched(['a', 'b', 'c', 'd', 'e', 'f', 'g']),
    );
    expect(plan.finalStepCount, ChecklistRepository.maxSteps);
    expect(plan.inserts, hasLength(ChecklistRepository.maxSteps));
  });

  test('empty incoming clears the checklist (validated payload never has it)',
      () async {
    final (store, repo, incidentId) = await openWithSteps();
    addTearDown(store.close);
    final existing = await repo.forIncident(incidentId);

    final plan = mergeEnrichedChecklist(
      incidentId: incidentId,
      existing: existing,
      incoming: const [],
    );
    expect(plan.removeIds, hasLength(3));
    expect(plan.replacements, isEmpty);
    final merged = await applyChecklistMerge(repo, plan);
    expect(merged, isEmpty);
  });
}
