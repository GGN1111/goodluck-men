import '../data/repositories/alarm_repository.dart';
import '../data/repositories/incident_repository.dart';
import 'entities.dart';

/// T049 — permanent incident delete with cascade (FR-015, contract C2).
///
/// DB-level `ON DELETE CASCADE` removes action_steps / missing_warnings /
/// recheck_alarms rows; this use-case first cancels any still-scheduled
/// platform notification so no phantom reminder fires for a deleted record.
class DeleteIncident {
  DeleteIncident({
    required this.incidents,
    required this.alarms,
    this.cancelPlatform,
  });

  final IncidentRepository incidents;
  final AlarmRepository alarms;

  /// Cancels a scheduled OS notification by its platform handle. Injected so
  /// tests can assert without touching the notification plugin.
  final Future<void> Function(String handle)? cancelPlatform;

  Future<void> call(int incidentId) async {
    final alarmRows = await alarms.forIncident(incidentId);
    for (final alarm in alarmRows) {
      if (alarm.status != AlarmStatus.scheduled) continue;
      final handle = alarm.platformHandle;
      if (handle == null || handle.isEmpty) continue;
      try {
        await cancelPlatform?.call(handle);
      } catch (_) {
        // Best-effort: the row (and its handle) are about to vanish anyway.
      }
    }
    await incidents.delete(incidentId);
  }
}
