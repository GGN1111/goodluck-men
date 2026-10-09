import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';

/// Single-row settings (defaults seeded by schema v1).
class SettingsRepository {
  SettingsRepository(this._db);

  final Database _db;

  Future<AppSettings> get() async {
    final rows = await _db.query('settings', where: 'id = 1');
    if (rows.isEmpty) {
      const fresh = AppSettings();
      await _db.insert('settings', fresh.toMap());
      return fresh;
    }
    return AppSettings.fromMap(rows.first);
  }

  Future<void> save(AppSettings settings) =>
      _db.update('settings', settings.toMap(), where: 'id = 1');

  Future<void> setLanguage(AppLanguage language) async {
    final current = await get();
    await save(current.copyWith(language: language));
  }

  Future<void> setLowPowerMode(bool enabled) async {
    final current = await get();
    await save(current.copyWith(lowPowerMode: enabled));
  }

  Future<void> setNotificationsGranted(bool granted) async {
    final current = await get();
    await save(current.copyWith(notificationsGranted: granted));
  }

  Future<void> setModelVariant(String variant) async {
    final current = await get();
    await save(current.copyWith(modelVariant: variant));
  }
}
