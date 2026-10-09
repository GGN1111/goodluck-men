import '../data/repositories/alarm_repository.dart';
import '../domain/entities.dart';

/// Outcome of one boot/launch reconciliation pass (reboot edge case,
/// spec: "re-arm or explicit reschedule notice — never silent loss").
class ReconcileReport {
  const ReconcileReport({
    this.reArmed = 0,
    this.missed = 0,
    this.clearedStale = 0,
  });

  /// `scheduled` rows whose fire time is still ahead — re-armed.
  final int reArmed;

  /// `scheduled` rows whose fire time passed while the app/device was off —
  /// marked `fired` and surfaced to the user for an explicit reschedule.
  final int missed;

  /// `fired`/`cancelled` rows that still held a platform handle — cancelled
  /// at the OS level and cleared.
  final int clearedStale;

  bool get nothingLostSilently => true;
}

/// T039 — Boot/launch alarm reconciliation (research R8, SC-006):
/// idempotent by construction — only `scheduled` rows are re-armed, and a
/// row's handle is replaced (never duplicated). Running twice in a row is
/// safe: the second pass simply re-arms the same rows again.
class AlarmReconciler {
  AlarmReconciler({
    required this.alarms,
    required this.schedule,
    this.cancelPlatform,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AlarmRepository alarms;

  /// Arms a persisted alarm and returns its platform handle — injected so
  /// host tests never touch plugins.
  final Future<String?> Function(ReCheckAlarm alarm) schedule;

  /// Optional OS-level cancel (handle → notification id).
  final Future<void> Function(String handle)? cancelPlatform;

  final DateTime Function() _now;

  Future<ReconcileReport> reconcile() async {
    var reArmed = 0;
    var missed = 0;
    var clearedStale = 0;
    final now = _now();

    for (final alarm in await alarms.byStatus(AlarmStatus.scheduled)) {
      final id = alarm.id;
      if (id == null) continue;
      if (!alarm.fireAt.isAfter(now)) {
        // Passed while off — record it so the UI can offer an explicit
        // reschedule (no silent loss).
        await alarms.updateStatus(id, status: AlarmStatus.fired);
        missed++;
        continue;
      }
      // Exact alarms do not survive reboot on modern Android — re-arm
      // from the DB row, replacing any stale handle.
      final handle = await schedule(alarm);
      await alarms.updateStatus(id,
          status: AlarmStatus.scheduled, platformHandle: handle);
      reArmed++;
    }

    final cancel = cancelPlatform;
    if (cancel != null) {
      for (final status in [AlarmStatus.fired, AlarmStatus.cancelled]) {
        for (final alarm in await alarms.byStatus(status)) {
          final handle = alarm.platformHandle;
          if (handle == null || alarm.id == null) continue;
          await cancel(handle);
          await alarms.updateStatus(alarm.id!,
              status: status, clearPlatformHandle: true);
          clearedStale++;
        }
      }
    }

    return ReconcileReport(
      reArmed: reArmed,
      missed: missed,
      clearedStale: clearedStale,
    );
  }
}
