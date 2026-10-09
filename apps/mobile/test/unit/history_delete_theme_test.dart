import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signalready_pocket/core/app_graph.dart';
import 'package:signalready_pocket/core/theme/app_theme.dart';
import 'package:signalready_pocket/data/database.dart';
import 'package:signalready_pocket/data/repositories/alarm_repository.dart';
import 'package:signalready_pocket/data/repositories/checklist_repository.dart';
import 'package:signalready_pocket/data/repositories/incident_repository.dart';
import 'package:signalready_pocket/data/repositories/settings_repository.dart';
import 'package:signalready_pocket/data/repositories/warning_repository.dart';
import 'package:signalready_pocket/domain/delete_incident.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/ui/history_screen.dart';
import 'package:signalready_pocket/ui/settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T047 — US7 contract (FR-010/011/015, quickstart V9, ui-actions C1–C3):
/// history survives restart, permanent delete cascades steps/warnings/alarms,
/// and low-power high-contrast theme applies app-wide.
void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  final tempDir = Directory.systemTemp.createTempSync('hist_del_');
  var dbCounter = 0;
  String nextDbPath() => p.join(tempDir.path, 'h${dbCounter++}.db');

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  IncidentRecord incident({
    String text = 'FLASH FLOOD: evacuate Zone 4.',
    DateTime? createdAt,
  }) =>
      IncidentRecord(
        createdAt: createdAt ?? DateTime(2026, 10, 9, 12, 0),
        sourceType: SourceType.text,
        sourceText: text,
        crisisType: CrisisType.flood,
        severity: SeverityState.alert,
        summary: const LocalizedText(
            en: 'Flash flood in Zone 4.', tl: 'Baha.', ceb: 'Baha.'),
        speech: const LocalizedText(
            en: 'Move high.', tl: 'Umakyat.', ceb: 'Ambak.'),
        status: AnalysisStatus.skeleton,
      );

  Future<(SignalReadyDatabase, IncidentRepository, int)> seedIncident(
    String dbPath,
  ) async {
    final store = await SignalReadyDatabase.open(overridePath: dbPath);
    final id = await IncidentRepository(store.db).insert(incident());
    return (store, IncidentRepository(store.db), id);
  }

  group('history survives restart (FR-010 / SC-008)', () {
    test('records persist across close/reopen and stay fully offline',
        () async {
      final dbPath = nextDbPath();

      var (store, repo, _) = await seedIncident(dbPath);
      await repo.insert(incident(
        text: 'POWER OUTAGE: several barangays.',
        createdAt: DateTime(2026, 10, 9, 13, 0),
      ));
      await store.close();

      (store, repo, _) = await seedIncidentReusePath(dbPath);
      addTearDown(store.close);
      final records = await repo.getAll();

      expect(records, hasLength(2), reason: 'both advisories visible offline');
      expect(records.first.createdAt.isAfter(records.last.createdAt), isTrue,
          reason: 'History is newest-first');
      expect(
        records.map((r) => r.sourceText),
        containsAll([
          'FLASH FLOOD: evacuate Zone 4.',
          'POWER OUTAGE: several barangays.',
        ]),
      );
    });
  });

  group('permanent delete cascades (FR-015 / contract C2)', () {
    test('steps, warnings, and alarm rows are removed immediately and '
        'stay gone after restart', () async {
      final dbPath = nextDbPath();
      final (store, incidents, incidentId) = await seedIncident(dbPath);
      final steps = ChecklistRepository(store.db);
      final warnings = WarningRepository(store.db);
      final alarms = AlarmRepository(store.db);

      await steps.insertAll([
        ActionStep(
          incidentId: incidentId,
          priority: 1,
          text: const LocalizedText(en: 'Go high.', tl: 'Umakyat.',
              ceb: 'Ambak.'),
          state: ChecklistStepState.done,
          origin: StepOrigin.template,
        ),
      ]);
      await warnings.insertAll([
        MissingWarning(
          incidentId: incidentId,
          code: WarningCode.evacCenter,
          text: const LocalizedText(
              en: 'No center.', tl: 'Walang center.', ceb: 'Walay center.'),
          origin: WarningOrigin.fastpath,
        ),
      ]);
      await alarms.insert(ReCheckAlarm(
        incidentId: incidentId,
        fireAt: DateTime(2026, 10, 9, 13, 0),
        message: 'Re-check.',
        status: AlarmStatus.scheduled,
        platformHandle: '42',
      ));

      final cancelled = <String>[];
      await DeleteIncident(
        incidents: incidents,
        alarms: alarms,
        cancelPlatform: (handle) async => cancelled.add(handle),
      ).call(incidentId);

      expect(cancelled, ['42'],
          reason: 'pending platform notification cancelled before delete');
      expect(await steps.forIncident(incidentId), isEmpty);
      expect(await warnings.forIncident(incidentId), isEmpty);
      expect(await alarms.forIncident(incidentId), isEmpty);
      expect(await incidents.getById(incidentId), isNull);
      await store.close();

      // Restart: nothing resurrects.
      final reopened = await SignalReadyDatabase.open(overridePath: dbPath);
      addTearDown(reopened.close);
      expect(await IncidentRepository(reopened.db).getAll(), isEmpty);
      expect(await ChecklistRepository(reopened.db).forIncident(incidentId),
          isEmpty);
      expect(await WarningRepository(reopened.db).forIncident(incidentId),
          isEmpty);
      expect(await AlarmRepository(reopened.db).forIncident(incidentId),
          isEmpty);
    });
  });

  group('low-power high-contrast theme (FR-011 / contract C3)', () {
    test('low-power swaps every severity to pure-black surfaces', () {
      for (final severity in ['ALERT', 'CAUTION', 'INFO']) {
        final on = appThemeFor(severity, lowPower: true);
        final off = appThemeFor(severity, lowPower: false);
        expect(on.scaffoldBackgroundColor, AppColors.pureBlack,
            reason: '$severity low-power uses OLED black');
        expect(on.cardColor, AppColors.pureBlack);
        expect(off.scaffoldBackgroundColor, AppColors.primarySlate);
      }
    });

    test('Settings row default is off; toggling persists low_power_mode',
        () async {
      final store = await SignalReadyDatabase.open(overridePath: nextDbPath());
      addTearDown(store.close);
      final settings = SettingsRepository(store.db);

      expect((await settings.get()).lowPowerMode, isFalse);
      await settings.setLowPowerMode(true);
      expect((await settings.get()).lowPowerMode, isTrue,
          reason: 'FR-011 flag persisted to the single settings row');
    });

    testWidgets('Settings screen switch persists through the repository',
        (tester) async {
      final graph = await tester.runAsync(
        () => AppGraph.open(dbOverridePath: nextDbPath(), enableEngine: false),
      );
      addTearDown(graph!.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SettingsScreen(graph: graph)),
      ));
      await tester.pump();
      // Real sqflite futures need the real event loop — nudge them out of
      // the FakeAsync zone, then let frames settle.
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final stored = await tester.runAsync(() => graph.settings.get());
      expect(stored!.lowPowerMode, isTrue, reason: 'contract C3');
    });
  });

  group('history screen (contract C1 / T048)', () {
    testWidgets('lists seeded incidents newest-first and opens the full '
        'brief with checklist state', (tester) async {
      final graph = await tester.runAsync(
        () => AppGraph.open(dbOverridePath: nextDbPath(), enableEngine: false),
      );
      addTearDown(graph!.dispose);

      await tester.runAsync(() async {
        await graph.settings.setLanguage(AppLanguage.en);
        final incidents = IncidentRepository(graph.store.db);
        final older = await incidents.insert(incident(
            text: 'FLASH FLOOD: evacuate Zone 4.'));
        await incidents.insert(IncidentRecord(
          createdAt: DateTime(2026, 10, 9, 13, 0),
          sourceType: SourceType.text,
          sourceText: 'FIRE: evacuate the market.',
          crisisType: CrisisType.fire,
          severity: SeverityState.caution,
          summary: const LocalizedText(
              en: 'Market fire.', tl: 'Sunog sa merkado.', ceb: 'Sunog.'),
          speech: const LocalizedText(
              en: 'Leave now.', tl: 'Lumabas.', ceb: 'Gawas.'),
          status: AnalysisStatus.skeleton,
        ));
        await ChecklistRepository(graph.store.db).insertAll([
          ActionStep(
            incidentId: older,
            priority: 1,
            text: const LocalizedText(
                en: 'Go high.', tl: 'Umakyat.', ceb: 'Ambak.'),
            state: ChecklistStepState.done,
            origin: StepOrigin.template,
          ),
        ]);
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: HistoryScreen(graph: graph)),
      ));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text('Market fire.'), findsOneWidget,
          reason: 'newest first');
      expect(find.text('Flash flood in Zone 4.'), findsOneWidget);

      await tester.tap(find.text('Flash flood in Zone 4.'));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text('Go high.'), findsOneWidget,
          reason: 'full brief opens offline (C1)');
      expect(find.text('Action checklist'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget,
          reason: 'checklist done-state survives into History');
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}

/// Reopen helper (mirrors seedIncident without inserting a new record).
Future<(SignalReadyDatabase, IncidentRepository, int)> seedIncidentReusePath(
  String dbPath,
) async {
  final store = await SignalReadyDatabase.open(overridePath: dbPath);
  final rows = await store.db.query('incidents', orderBy: 'id ASC');
  return (
    store,
    IncidentRepository(store.db),
    rows.first['id'] as int,
  );
}
