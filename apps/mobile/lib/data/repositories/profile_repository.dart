import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';

/// Optional single-row household profile (data-model HouseholdProfile).
/// Profile data may only personalize *future* checklists — it never merges
/// into source-derived brief fields (FR-005 provenance, ui-actions C6).
class ProfileRepository {
  ProfileRepository(this._db);

  final Database _db;

  Future<HouseholdProfile?> get() async {
    final rows = await _db.query('household_profile', where: 'id = 1');
    if (rows.isEmpty) return null;
    return HouseholdProfile.fromMap(rows.first);
  }

  Future<void> save(HouseholdProfile profile) =>
      _db.insert('household_profile', profile.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
}
