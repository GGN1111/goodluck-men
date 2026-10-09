import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';

/// Re-check alarm persistence (FR-008). DB rows are the source of truth;
/// platform handles are cached for cancel/rewrite. Boot/launch reconciliation
/// (research R8) re-arms rows still in `scheduled`.
class AlarmRepository {
  AlarmRepository(this._db);

  final Database _db;

  Future<int> insert(ReCheckAlarm alarm) =>
      _db.insert('recheck_alarms', alarm.toMap());

  Future<List<ReCheckAlarm>> byStatus(AlarmStatus status) async {
    final rows = await _db.query(
      'recheck_alarms',
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'fire_at ASC',
    );
    return rows.map(ReCheckAlarm.fromMap).toList();
  }

  Future<List<ReCheckAlarm>> forIncident(int incidentId) async {
    final rows = await _db.query(
      'recheck_alarms',
      where: 'incident_id = ?',
      whereArgs: [incidentId],
      orderBy: 'fire_at ASC',
    );
    return rows.map(ReCheckAlarm.fromMap).toList();
  }

  Future<ReCheckAlarm?> getById(int id) async {
    final rows = await _db.query('recheck_alarms',
        where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ReCheckAlarm.fromMap(rows.first);
  }

  Future<void> updateStatus(
    int id, {
    required AlarmStatus status,
    String? platformHandle,
    bool clearPlatformHandle = false,
  }) {
    return _db.update(
      'recheck_alarms',
      {
        'status': status.name,
        if (clearPlatformHandle)
          'platform_handle': null
        else if (platformHandle != null) 'platform_handle': platformHandle,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) =>
      _db.delete('recheck_alarms', where: 'id = ?', whereArgs: [id]);
}
