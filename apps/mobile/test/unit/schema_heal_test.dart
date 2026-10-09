import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signalready_pocket/data/database.dart';
import 'package:signalready_pocket/data/repositories/guide_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression: a device DB created by an older build whose schema predates
/// the `guides` table crashed startup with "no such table: guides" —
/// `onCreate` never re-fires on an existing file and `onUpgrade` was empty.
/// The self-heal path (`_healSchema`) must bring any stale file up to the
/// full v1 shape on open, without dropping existing data.
void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  final tempDir = Directory.systemTemp.createTempSync('sr_heal_');
  var dbCounter = 0;

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // best-effort
    }
  });

  test('open heals a stale DB missing the guides table (no crash)', () async {
    final path = p.join(tempDir.path, 'stale_${dbCounter++}.db');

    // Simulate an old install: file exists at the current schemaVersion but
    // was built before `guides` existed — so version bookkeeping matches but
    // the table is absent. onCreate will NOT run for an existing file.
    final raw = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: SignalReadyDatabase.schemaVersion,
        onCreate: (db, version) async {
          // Old v1 minus the guides table.
          await db.execute('''
            CREATE TABLE incidents (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    // Seed a pre-existing incident so we can prove data survives the heal.
    await raw.insert('incidents', {'created_at': '2026-10-09T00:00:00'});
    await raw.close();

    // Re-open through the app: must not throw, must create guides + reseed.
    final store = await SignalReadyDatabase.open(overridePath: path);
    addTearDown(store.close);

    final guides = GuideRepository(store.db);
    expect(await guides.count(), greaterThan(0),
        reason: 'guides table created and seeded on heal');

    final rows = await store.db.query('incidents');
    expect(rows, hasLength(1),
        reason: 'pre-existing incident data is preserved by the heal');
  });

  test('heal is idempotent — reopening a healthy DB is a no-op', () async {
    final path = p.join(tempDir.path, 'healthy_${dbCounter++}.db');
    var store = await SignalReadyDatabase.open(overridePath: path);
    final firstCount = await GuideRepository(store.db).count();
    await store.close();

    store = await SignalReadyDatabase.open(overridePath: path);
    addTearDown(store.close);
    expect(await GuideRepository(store.db).count(), firstCount,
        reason: 'reseeding is skipped when guides already present');
  });
}
