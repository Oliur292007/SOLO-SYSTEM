import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'timetable_system.dart';

class MissionNotificationService {
  static const MethodChannel _channel =
      MethodChannel('solo_system/app_restriction');
  static const String _storedIdsKey = 'mission_reminder_notification_ids';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      final zoneName =
          await _channel.invokeMethod<String>('getLocalTimeZone');
      if (zoneName != null && zoneName.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(zoneName));
      }
    } catch (error) {
      debugPrint('TIMEZONE LOAD ERROR: $error');
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> requestPermission() async {
    if (!_initialized) await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  int _stableId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  tz.TZDateTime _nextWeeklyReminder(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).subtract(const Duration(minutes: 5));

    while (candidate.weekday != weekday || !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Future<void> syncMissionReminders(
    List<StudyScheduleItem> schedules,
  ) async {
    if (!_initialized) await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'solo_mission_reminders',
        'Mission Reminders',
        channelDescription:
            'Reminders sent five minutes before scheduled missions.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final prefs = await SharedPreferences.getInstance();
    final previousIds =
        prefs.getStringList(_storedIdsKey) ?? <String>[];
    for (final value in previousIds) {
      final id = int.tryParse(value);
      if (id != null) await _plugin.cancel(id);
    }

    final newIds = <String>[];

    Future<void> scheduleWeekly({
      required int id,
      required int weekday,
      required int hour,
      required int minute,
      required String title,
      required String body,
    }) async {
      final reminder = _nextWeeklyReminder(weekday, hour, minute);
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        reminder,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      newIds.add(id.toString());
    }

    // Daily fixed missions: Wakeup at 5:00 AM and Sleeping at 8:00 PM.
    await scheduleWeekly(
      id: 10001,
      weekday: DateTime.monday,
      hour: 5,
      minute: 0,
      title: 'WAKEUP MISSION IN 5 MINUTES',
      body: 'Your Wakeup Mission starts at 5:00 AM. Get ready, Hunter.',
    );
    await scheduleWeekly(
      id: 10002,
      weekday: DateTime.monday,
      hour: 20,
      minute: 0,
      title: 'SLEEPING MISSION IN 5 MINUTES',
      body: 'Your Sleeping Mission becomes available at 8:00 PM.',
    );

    // Repeat the two fixed daily reminders for every weekday.
    for (var day = DateTime.tuesday; day <= DateTime.sunday; day++) {
      await scheduleWeekly(
        id: 10001 + day - DateTime.monday,
        weekday: day,
        hour: 5,
        minute: 0,
        title: 'WAKEUP MISSION IN 5 MINUTES',
        body: 'Your Wakeup Mission starts at 5:00 AM. Get ready, Hunter.',
      );
      await scheduleWeekly(
        id: 10008 + day - DateTime.tuesday,
        weekday: day,
        hour: 20,
        minute: 0,
        title: 'SLEEPING MISSION IN 5 MINUTES',
        body: 'Your Sleeping Mission becomes available at 8:00 PM.',
      );
    }

    for (final item in schedules) {
      final parts = item.startTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final id = _stableId('schedule_${item.id}');
      await scheduleWeekly(
        id: id,
        weekday: item.dayOfWeek,
        hour: hour,
        minute: minute,
        title: 'MISSION IN 5 MINUTES',
        body: 'Your ${item.subject} schedule starts at ${item.startTime}. Get ready, Hunter.',
      );
    }

    await prefs.setStringList(_storedIdsKey, newIds);
  }
}
