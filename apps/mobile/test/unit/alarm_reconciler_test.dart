import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signalready_pocket/data/database.dart';
import 'package:signalready_pocket/data/repositories/alarm_repository.dart';
import 'package:signalready_pocket/data/repositories/incident_repository.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/notifications/alarm_reconciler.dart';
import 'package:signalready_pocket/notifications/alarm_scheduler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T037 — Reconciler contract (research R8, SC-006, reboot edge case):
/// idempotent re-arm of `scheduled` rows only, correct fire-time math,
/// cancel path clears the platform handle.
void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  final tempDir = Directory.systemTemp.createTempSync('alarm_rec_');
  var dbCounter = 0;

  Future<(SignalReadyDatabase, AlarmRepository, int)> openStore() async {
    final store = await SignalReadyDatabase.open(
        overridePath: p.join(tempDir.path, 'rec_${dbCounter++}.db'));
    final incidentId = await IncidentRepository(store.db).insert(
      IncidentRecord(
        createdAt: DateTime(2026, 10, 9, 11, 0),
        sourceType: SourceType.text,
        sourceText: 'FLASH FLOOD: evacuate Zone 4.',
        crisisType: CrisisType.flood,
        severity: SeverityState.alert,
        summary: const LocalizedText(en: 's', tl: 's', ceb: 's'),
        speech: const LocalizedText(en: 's', tl: 's', ceb: 's'),
        status: AnalysisStatus.skeleton,
      ),
    );
    return (store, AlarmRepository(store.db), incidentId);
  }

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<int> seed(
    AlarmRepository alarms, {
    required int incidentId,
    required AlarmStatus status,
    required DateTime fireAt,
    String? handle,
  }) {
    return alarms.insert(ReCheckAlarm(
      incidentId: incidentId,
      fireAt: fireAt,
      message: 'Re-check the flood advisory.',
      status: status,
      platformHandle: handle,
    ));
  }

  test('fire time math: offsets are added to the supplied clock', () {
    final now = DateTime(2026, 10, 9, 12, 0);
    expect(AlarmScheduler.fireAtFromNow(const Duration(minutes: 15), now: now),
        DateTime(2026, 10, 9, 12, 15));
    expect(AlarmScheduler.fireAtFromNow(const Duration(hours: 1), now: now),
        DateTime(2026, 10, 9, 13, 0));
  });

  test('re-arms only scheduled rows with future fire times', () async {
    final (store, alarms, incidentId) = await openStore();
    addTearDown(store.close);
    final now = DateTime(2026, 10, 9, 12, 0);

    final pendingId = await seed(alarms,
        incidentId: incidentId,
        status: AlarmStatus.scheduled,
        fireAt: now.add(const Duration(hours: 1)));
    await seed(alarms,
        incidentId: incidentId,
        status: AlarmStatus.fired,
        fireAt: now.subtract(const Duration(hours: 2)),
        handle: '99');
    await seed(alarms,
        incidentId: incidentId,
        status: AlarmStatus.cancelled,
        fireAt: now.add(const Duration(days: 1)),
        handle: '98');

    final scheduled = <ReCheckAlarm>[];
    final cancelCalls = <String>[];
    final reconciler = AlarmReconciler(
      alarms: alarms,
      schedule: (alarm) async {
        scheduled.add(alarm);
        return AlarmScheduler.handleFor(alarm.id!);
      },
      cancelPlatform: (handle) async => cancelCalls.add(handle),
      now: () => now,
    );

    final report = await reconciler.reconcile();

    expect(report.reArmed, 1);
    expect(scheduled.single.id, pendingId);
    final rearm = await alarms.getById(pendingId);
    expect(rearm!.status, AlarmStatus.scheduled);
    expect(rearm.platformHandle, '$pendingId');

    // Stale handles on terminal rows cancelled + cleared (cancel path).
    expect(report.clearedStale, 2);
    expect(cancelCalls, containsAll(['99', '98']));
    final fired = await alarms.byStatus(AlarmStatus.fired);
    expect(fired.single.platformHandle, isNull);
    final cancelled = await alarms.byStatus(AlarmStatus.cancelled);
    expect(cancelled.single.platformHandle, isNull);

    // Idempotent: a second pass re-arms the same single row again —
    // never duplicates, never touches terminal rows.
    final second = await reconciler.reconcile();
    expect(second.reArmed, 1);
    expect(second.clearedStale, 0);
    final all = await Future.wait([
      alarms.byStatus(AlarmStatus.scheduled),
      alarms.byStatus(AlarmStatus.fired),
      alarms.byStatus(AlarmStatus.cancelled),
    ]);
    expect(all[0], hasLength(1), reason: 'still exactly one scheduled row');
    expect(all[1], hasLength(1));
    expect(all[2], hasLength(1));
  });

  test('scheduled row whose time passed is marked fired (missed → notice)',
      () async {
    final (store, alarms, incidentId) = await openStore();
    addTearDown(store.close);
    final now = DateTime(2026, 10, 9, 12, 0);

    final missedId = await seed(alarms,
        incidentId: incidentId,
        status: AlarmStatus.scheduled,
        fireAt: now.subtract(const Duration(minutes: 5)));

    var scheduleCalls = 0;
    final report = await AlarmReconciler(
      alarms: alarms,
      schedule: (_) async {
        scheduleCalls++;
        return 'x';
      },
      now: () => now,
    ).reconcile();

    expect(scheduleCalls, 0, reason: 'a passed alarm is never re-armed');
    expect(report.missed, 1);
    expect(report.reArmed, 0);
    final row = await alarms.getById(missedId);
    expect(row!.status, AlarmStatus.fired);
    expect(row.platformHandle, isNull);
  });

  test('cancel path via repository clears the platform handle', () async {
    final (store, alarms, incidentId) = await openStore();
    addTearDown(store.close);

    final id = await seed(alarms,
        incidentId: incidentId,
        status: AlarmStatus.scheduled,
        fireAt: DateTime(2026, 10, 9, 13),
        handle: '42');
    await alarms.updateStatus(id,
        status: AlarmStatus.cancelled, clearPlatformHandle: true);

    final row = await alarms.getById(id);
    expect(row!.status, AlarmStatus.cancelled);
    expect(row.platformHandle, isNull,
        reason: 'cancellation must drop the OS handle (B3)');
  });
}
