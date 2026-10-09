import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';

/// Incident CRUD + enrichment apply (data-model IncidentRecord).
/// Permanent delete relies on FK cascade for steps/warnings/alarms (FR-015).
class IncidentRepository {
  IncidentRepository(this._db);

  final Database _db;

  Future<int> insert(IncidentRecord record) =>
      _db.insert('incidents', record.toMap());

  Future<IncidentRecord?> getById(int id) async {
    final rows =
        await _db.query('incidents', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return IncidentRecord.fromMap(rows.first);
  }

  /// Newest first (History screen).
  Future<List<IncidentRecord>> getAll() async {
    final rows = await _db.query('incidents', orderBy: 'created_at DESC');
    return rows.map(IncidentRecord.fromMap).toList();
  }

  /// Replaces skeleton content with validated enrichment (status → enriched).
  /// Never touches user checklist state — that lives in action_steps.
  Future<void> applyEnrichment(
    int id, {
    required CrisisType crisisType,
    required SeverityState severity,
    required String? location,
    required String? timeOrStatus,
    required LocalizedText summary,
    required LocalizedText speech,
    required String? modelNotice,
  }) {
    return _db.update(
      'incidents',
      {
        'crisis_type': crisisType.contractName,
        'severity': severity.contractName,
        'location': location,
        'time_or_status': timeOrStatus,
        'summary_en': summary.en,
        'summary_tl': summary.tl,
        'summary_ceb': summary.ceb,
        'speech_en': speech.en,
        'speech_tl': speech.tl,
        'speech_ceb': speech.ceb,
        'status': AnalysisStatus.enriched.name,
        'model_notice': modelNotice,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks a failed (degraded) analysis; skeleton content is retained.
  Future<void> markFailed(int id, {required String notice}) {
    return _db.update(
      'incidents',
      {'status': AnalysisStatus.failed.name, 'model_notice': notice},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) =>
      _db.delete('incidents', where: 'id = ?', whereArgs: [id]);
}
