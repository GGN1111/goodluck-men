import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';

/// Red-flag warnings (FR-004): only genuinely omitted details are stored —
/// never fabricated (FR-005), enforced upstream by fast-path rules (T030)
/// and LLM validation (T019).
class WarningRepository {
  WarningRepository(this._db);

  final Database _db;

  Future<void> insertAll(List<MissingWarning> warnings) async {
    if (warnings.isEmpty) return;
    final batch = _db.batch();
    for (final warning in warnings) {
      batch.insert('missing_warnings', warning.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<MissingWarning>> forIncident(int incidentId) async {
    final rows = await _db.query(
      'missing_warnings',
      where: 'incident_id = ?',
      whereArgs: [incidentId],
      orderBy: 'id ASC',
    );
    return rows.map(MissingWarning.fromMap).toList();
  }

  Future<void> deleteForIncident(int incidentId) =>
      _db.delete('missing_warnings',
          where: 'incident_id = ?', whereArgs: [incidentId]);
}
