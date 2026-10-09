import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signalready_pocket/data/database.dart';
import 'package:signalready_pocket/data/repositories/checklist_repository.dart';
import 'package:signalready_pocket/data/repositories/incident_repository.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/inference/template_checklists.dart';
import 'package:signalready_pocket/ui/action_checklist.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T024 — US2: checklist toggle persistence (SC-008, quickstart V4),
/// crisis template distinctness (FR-006), and the 5-step cap (data-model).
void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  final tempDir = Directory.systemTemp.createTempSync('sr_checklist_');
  var dbCounter = 0;

  Future<(SignalReadyDatabase, int)> openStoreWithIncident(
      {String? reusePath}) async {
    final path = reusePath ?? p.join(tempDir.path, 'chk_${dbCounter++}.db');
    final store = await SignalReadyDatabase.open(overridePath: path);
    final incidentId = await IncidentRepository(store.db).insert(_incident());
    return (store, incidentId);
  }

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // temp cleanup is best-effort
    }
  });

  test('toggle state round-trips through repository and survives reopen',
      () async {
    final path = p.join(tempDir.path, 'persist.db');
    var (store, incidentId) = await openStoreWithIncident(reusePath: path);
    final repo = ChecklistRepository(store.db);

    await repo.insertAll([
      _step(incidentId, priority: 1, text: _text('en one', 'tl one', 'ceb one')),
      _step(incidentId, priority: 2, text: _text('en two', 'tl two', 'ceb two')),
    ]);

    final before = await repo.forIncident(incidentId);
    expect(before, hasLength(2));
    expect(before.every((s) => s.state == ChecklistStepState.pending), isTrue);

    // B1: pending → done persists immediately.
    final newState = await repo.toggle(before.first.id!);
    expect(newState, ChecklistStepState.done);
    await store.close();

    // Force-kill simulation: reopen the same file (quickstart V4).
    final reopened = await SignalReadyDatabase.open(overridePath: path);
    addTearDown(reopened.close);
    final reloaded = await ChecklistRepository(reopened.db)
        .forIncident(incidentId);
    expect(reloaded.first.state, ChecklistStepState.done);
    expect(reloaded.last.state, ChecklistStepState.pending);

    // Second toggle flips back.
    final back = await ChecklistRepository(reopened.db)
        .toggle(reloaded.first.id!);
    expect(back, ChecklistStepState.pending);
    final again =
        await ChecklistRepository(reopened.db).forIncident(incidentId);
    expect(again.first.state, ChecklistStepState.pending);

    // Unknown step id is rejected, not fabricated.
    await expectLater(
        ChecklistRepository(reopened.db).toggle(999999), throwsArgumentError);
  });

  test('flood and blackout templates differ (FR-006 distinct per crisis)',
      () {
    const templates = TemplateChecklists();
    final flood = templates.forCrisis(CrisisType.flood);
    final blackout = templates.forCrisis(CrisisType.blackout);
    final others = [
      ...templates.forCrisis(CrisisType.fire),
      ...templates.forCrisis(CrisisType.security),
      ...templates.forCrisis(CrisisType.general),
    ];

    expect(flood, hasLength(3));
    expect(blackout, hasLength(3));

    final floodEn = flood.map((s) => s.en).toSet();
    final blackoutEn = blackout.map((s) => s.en).toSet();
    expect(floodEn.intersection(blackoutEn), isEmpty,
        reason: 'flood and blackout step sets must be disjoint');

    for (final step in [...flood, ...blackout]) {
      expect(step.isComplete, isTrue, reason: 'every step must be trilingual');
    }

    // All five crises are mutually distinct on English copy.
    final all = [...flood, ...blackout, ...others];
    final texts = all.map((s) => s.en).toList();
    expect(texts.toSet(), hasLength(texts.length),
        reason: 'no step text may repeat across crisis templates');
  });

  testWidgets('ActionChecklist renders trilingual rows and reports taps',
      (tester) async {
    const step1 = ActionStep(
      id: 11,
      incidentId: 1,
      priority: 1,
      text: LocalizedText(en: 'en one', tl: 'tl one', ceb: 'ceb one'),
      state: ChecklistStepState.pending,
      origin: StepOrigin.template,
    );
    const step2 = ActionStep(
      id: 22,
      incidentId: 1,
      priority: 2,
      text: LocalizedText(en: 'en two', tl: 'tl two', ceb: 'ceb two'),
      state: ChecklistStepState.done,
      origin: StepOrigin.template,
    );
    ActionStep? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActionChecklist(
          steps: const [step2, step1],
          language: AppLanguage.en,
          onToggle: (s) => tapped = s,
        ),
      ),
    ));

    // Priority order regardless of list order, active language text shown.
    expect(find.text('en one'), findsOneWidget);
    expect(find.text('en two'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason: 'the done step shows the filled check');
    final firstY = tester.getTopLeft(find.text('en one')).dy;
    final secondY = tester.getTopLeft(find.text('en two')).dy;
    expect(firstY, lessThan(secondY), reason: 'rows follow priority order');

    await tester.tap(find.text('en one'));
    expect(tapped, isNotNull);
    expect(tapped!.id, 11);
  });

  test('max 5 steps enforced per incident (data-model)', () async {
    final (store, incidentId) = await openStoreWithIncident();
    addTearDown(store.close);
    final repo = ChecklistRepository(store.db);

    List<ActionStep> make(int count, int priorityOffset) => [
          for (var i = 0; i < count; i++)
            _step(incidentId,
                priority: priorityOffset + i,
                text: _text('en $i', 'tl $i', 'ceb $i')),
        ];

    // Six at once is rejected outright.
    await expectLater(repo.insertAll(make(6, 1)), throwsArgumentError);

    // 3 + 3 is also rejected; 3 + 2 lands exactly on the cap.
    await repo.insertAll(make(3, 1));
    await expectLater(repo.insertAll(make(3, 4)), throwsArgumentError);
    await repo.insertAll(make(2, 4));

    final steps = await repo.forIncident(incidentId);
    expect(steps, hasLength(ChecklistRepository.maxSteps));
    expect(steps.map((s) => s.priority).toSet(), hasLength(5),
        reason: 'priorities stay unique after capped inserts');
  });
}

IncidentRecord _incident() => IncidentRecord(
      createdAt: DateTime.now(),
      sourceType: SourceType.text,
      sourceText: 'source verbatim for provenance',
      crisisType: CrisisType.flood,
      severity: SeverityState.alert,
      summary: const LocalizedText(en: 's', tl: 's', ceb: 's'),
      speech: const LocalizedText(en: 'p', tl: 'p', ceb: 'p'),
      status: AnalysisStatus.skeleton,
    );

ActionStep _step(
  int incidentId, {
  required int priority,
  required LocalizedText text,
}) =>
    ActionStep(
      incidentId: incidentId,
      priority: priority,
      text: text,
      state: ChecklistStepState.pending,
      origin: StepOrigin.template,
    );

LocalizedText _text(String en, String tl, String ceb) =>
    LocalizedText(en: en, tl: tl, ceb: ceb);
