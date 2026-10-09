import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';
import '../guide_seed.dart';

/// Read-only access to bundled offline guides (never network-fetched).
class GuideRepository {
  GuideRepository(this._db);

  final Database _db;

  /// Idempotent seeding (also runs during database creation).
  Future<void> ensureSeeded() => seedGuidesIfEmpty(_db);

  Future<List<EmergencyProtocolGuide>> all() async {
    final rows = await _db.query('guides', orderBy: 'slug ASC');
    return rows.map(EmergencyProtocolGuide.fromMap).toList();
  }

  Future<List<EmergencyProtocolGuide>> byCrisis(CrisisType type) async {
    final rows = await _db.query(
      'guides',
      where: 'crisis_type = ?',
      whereArgs: [type.contractName],
      orderBy: 'slug ASC',
    );
    return rows.map(EmergencyProtocolGuide.fromMap).toList();
  }

  Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM guides');
    return rows.first['c'] as int;
  }
}
