import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/entities.dart';

/// T038 — Re-check alarm scheduling (FR-008, research R8): exact alarms
/// via `flutter_local_notifications`. DB rows are the source of truth; the
/// platform handle cached on each row is the stringified notification id,
/// so cancel/re-arm are deterministic and reconciliation-safe.
class AlarmScheduler {
  AlarmScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static bool _tzReady = false;

  static void ensureTimezones() {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    _tzReady = true;
  }

  /// T037 fire-time math: schedule offsets are computed from a caller-
  /// supplied clock so tests are deterministic.
  static DateTime fireAtFromNow(Duration offset, {DateTime? now}) =>
      (now ?? DateTime.now()).add(offset);

  /// Platform handle for a persisted alarm row (notification id).
  static String handleFor(int alarmId) => '$alarmId';

  static const NotificationDetails details = NotificationDetails(
    android: AndroidNotificationDetails(
      'recheck',
      'Re-check reminders',
      channelDescription: 'Offline re-check reminders (FR-008)',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    ensureTimezones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: settings);
  }

  /// Arms the exact alarm; returns the platform handle to persist.
  Future<String?> schedule(ReCheckAlarm alarm) async {
    final id = alarm.id;
    if (id == null) {
      throw ArgumentError('alarm must be persisted (has id) before scheduling');
    }
    ensureTimezones();
    await _plugin.zonedSchedule(
      id: id,
      title: 'SignalReady re-check',
      body: alarm.message,
      scheduledDate: tz.TZDateTime.from(alarm.fireAt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exact,
    );
    return handleFor(id);
  }

  Future<void> cancel(String handle) =>
      _plugin.cancel(id: int.parse(handle));

  /// Requests POST_NOTIFICATIONS (Android 13+) / iOS alert permission.
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  Future<bool> notificationsEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.checkPermissions() != null;
    }
    return true;
  }
}
