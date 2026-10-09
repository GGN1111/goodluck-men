import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'guide_seed.dart';
import 'migrations/migration_v1.dart';

/// SQLite lifecycle for SignalReady Pocket (plan.md: local storage only).
///
/// - App-private database file, no encryption at rest in v1 (research R7;
///   privacy requirement is zero egress — FR-012).
/// - Foreign keys + cascade delete enforced (FR-015).
/// - Guides seeded on first open (offline reference, FR-012).
///
/// Open (call once at startup, before repositories):
/// ```dart
/// final store = await SignalReadyDatabase.open();
/// ```
class SignalReadyDatabase {
  SignalReadyDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 1;

  static Future<SignalReadyDatabase> open({String? overridePath}) async {
    final path = overridePath ??
        p.join(await getDatabasesPath(), 'signalready.db');
    final database = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // Self-heal every open: create any missing v1 table/index and reseed
        // guides. Guards against dev DBs built from an older schema whose
        // `onCreate` already ran (so it never re-fires) but lacks a table the
        // current v1 includes — e.g. `guides`, which crashed startup with
        // "no such table" on an existing stale file.
        await _healSchema(db);
      },
      onCreate: (db, version) async {
        // Same idempotent path as the heal — onConfigure already ran it, so
        // the CREATEs here are no-ops; _healSchema seeds settings + guides.
        await _healSchema(db);
      },
      onUpgrade: (db, from, to) async {
        // Defensive: bring a stale file up to the full v1 shape before any
        // future migrations chain here.
        await _healSchema(db);
      },
    );
    return SignalReadyDatabase._(database);
  }

  /// Creates any missing v1 table/index idempotently and reseeds guides.
  /// Safe to run on every open; never drops or alters existing data.
  ///
  /// The DDL runs as a [Batch] of single statements: `sqflite_android`'s
  /// `execute()` only runs the first statement of a multi-statement string,
  /// so a lone `execute()` here created just `incidents` on-device and the
  /// settings seed then crashed with "no such table: settings".
  static Future<void> _healSchema(Database db) async {
    final batch = db.batch();
    for (final statement in migrationV1IdempotentStatements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
    await db.execute(settingsSeedSql);
    await seedGuidesIfEmpty(db);
  }

  Future<void> close() => db.close();
}
