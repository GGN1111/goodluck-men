import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';

/// Checklist persistence (FR-006): ordered steps, toggleable done-state,
/// state survives restart (SC-008).
class ChecklistRepository {
  ChecklistRepository(this._db);

  final Database _db;

  /// Data-model cap: max 5 action steps per incident.
  static const int maxSteps = 5;

  /// Inserts steps after enforcing the 5-step cap per incident. Exceeding
  /// it is a programmer/contract error (LLM output is validated ≤5 upstream),
  /// so it throws rather than silently truncating.
  Future<void> insertAll(List<ActionStep> steps) async {
    if (steps.isEmpty) return;
    final perIncident = <int, int>{};
    for (final step in steps) {
      perIncident.update(step.incidentId, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final entry in perIncident.entries) {
      final rows = await _db.query('action_steps',
          columns: ['id'],
          where: 'incident_id = ?',
          whereArgs: [entry.key]);
      if (rows.length + entry.value > maxSteps) {
        throw ArgumentError(
            'Checklist for incident ${entry.key} would exceed $maxSteps steps '
            '(${rows.length} existing + ${entry.value} new).');
      }
    }
    final batch = _db.batch();
    for (final step in steps) {
      batch.insert('action_steps', step.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// B1: flips `pending ⇄ done`, persists immediately, and returns the new
  /// state so the UI can update without a reload.
  Future<ChecklistStepState> toggle(int stepId) async {
    final rows = await _db.query('action_steps',
        columns: ['state'], where: 'id = ?', whereArgs: [stepId]);
    if (rows.isEmpty) {
      throw ArgumentError('No checklist step with id $stepId.');
    }
    final current = ChecklistStepState.fromName(rows.first['state'] as String);
    final next = current == ChecklistStepState.pending
        ? ChecklistStepState.done
        : ChecklistStepState.pending;
    await setState(stepId, next);
    return next;
  }

  Future<List<ActionStep>> forIncident(int incidentId) async {
    final rows = await _db.query(
      'action_steps',
      where: 'incident_id = ?',
      whereArgs: [incidentId],
      orderBy: 'priority ASC',
    );
    return rows.map(ActionStep.fromMap).toList();
  }

  Future<void> setState(int stepId, ChecklistStepState state) {
    return _db.update(
      'action_steps',
      {'state': state.name},
      where: 'id = ?',
      whereArgs: [stepId],
    );
  }

  /// Replaces step text/origin after enrichment while **preserving ids and
  /// user done-state** (contracts/ui-actions.md A5).
  Future<void> updateContent(
    int stepId, {
    required int priority,
    required LocalizedText text,
    required StepOrigin origin,
  }) {
    return _db.update(
      'action_steps',
      {
        'priority': priority,
        'text_en': text.en,
        'text_tl': text.tl,
        'text_ceb': text.ceb,
        'origin': origin.name,
      },
      where: 'id = ?',
      whereArgs: [stepId],
    );
  }

  /// Removes steps not present after enrichment (LLM returned fewer items).
  Future<void> deleteExcept(int incidentId, List<int> keepStepIds) async {
    if (keepStepIds.isEmpty) {
      await _db.delete('action_steps',
          where: 'incident_id = ?', whereArgs: [incidentId]);
      return;
    }
    final placeholders = List.filled(keepStepIds.length, '?').join(',');
    await _db.delete(
      'action_steps',
      where:
          'incident_id = ? AND id NOT IN ($placeholders)',
      whereArgs: [incidentId, ...keepStepIds],
    );
  }
}
