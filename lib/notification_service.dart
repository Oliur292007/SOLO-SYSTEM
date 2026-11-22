import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'timetable_system.dart';

class SystemNotification {
  final int id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;

  const SystemNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'type': type,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory SystemNotification.fromJson(Map<String, dynamic> json) =>
      SystemNotification(
        id: json['id'] as int,
        title: json['title'] as String,
        body: json['body'] as String,
        type: json['type'] as String? ?? 'system',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] as int,
        ),
      );
}

class MissionNotificationService extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('solo_system/app_restriction');
  static const String _storedIdsKey = 'mission_reminder_notification_ids';
  static const String _historyKey = 'solo_notification_history';
  static const String _historyDateKey = 'solo_notification_history_date';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final List<SystemNotification> _history = [];
  List<StudyScheduleItem> _lastSchedules = <StudyScheduleItem>[];
  Timer? _dailyCleanupTimer;
  bool _initialized = false;

  List<SystemNotification> get history =>
      List<SystemNotification>.unmodifiable(_history);

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

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
    await _ensureToday();
    _dailyCleanupTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_ensureToday()),
    );
  }

  Future<void> _ensureToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString(_historyDateKey) != today) {
      _history.clear();
      await prefs.setString(_historyKey, jsonEncode(<dynamic>[]));
      await prefs.setString(_historyDateKey, today);
      notifyListeners();
      return;
    }
    if (_history.isEmpty) {
      final raw = prefs.getString(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          _history.addAll(decoded.map((item) => SystemNotification.fromJson(
                Map<String, dynamic>.from(item as Map),
              )));
          _history.removeWhere((item) =>
              '${item.createdAt.year}-'
              '${item.createdAt.month.toString().padLeft(2, '0')}-'
              '${item.createdAt.day.toString().padLeft(2, '0')}' != today);
        } catch (error) {
          debugPrint('NOTIFICATION HISTORY LOAD ERROR: $error');
          _history.clear();
        }
      }
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(
      _history.map((item) => item.toJson()).toList(),
    ));
    await prefs.setString(_historyDateKey, _todayKey());
  }

  Future<void> addNotification(
    String title,
    String body, {
    String type = 'system',
    bool showOnDevice = true,
  }) async {
    if (!_initialized) await initialize();
    await _ensureToday();
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch & 0x7fffffff;
    final entry = SystemNotification(
      id: id == 0 ? 1 : id,
      title: title,
      body: body,
      type: type,
      createdAt: now,
    );
    _history.add(entry);
    await _saveHistory();
    notifyListeners();

    if (showOnDevice) {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'solo_mission_reminders',
          'Mission Reminders',
          channelDescription:
              'Mission reminders and important Shadow Learner updates.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );
      try {
        await _plugin.show(entry.id, title, body, details);
      } catch (error) {
        debugPrint('SHOW SYSTEM NOTIFICATION ERROR: $error');
      }
    }
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
    notifyListeners();
  }

  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  Future<bool> areNotificationsEnabled() async {
    if (!_initialized) await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  Future<void> showPermissionConfirmation() async {
    await addNotification(
      'Shadow Learner Notifications Enabled',
      'Mission reminders and system updates are active.',
      type: 'permission',
    );
  }

  int _stableId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  tz.TZDateTime _nextWeeklyStart(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute,
    );
    while (candidate.weekday != weekday || !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Future<bool> canScheduleExactNotifications() async {
    if (!_initialized) await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<bool> requestExactAlarmPermission() async {
    if (!_initialized) await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    await android.requestExactAlarmsPermission();
    final granted = await android.canScheduleExactNotifications() ?? false;
    if (granted) {
      await syncMissionReminders(_lastSchedules);
    }
    return granted;
  }

  Future<void> syncMissionReminders(
    List<StudyScheduleItem> schedules,
  ) async {
    if (!_initialized) await initialize();
    _lastSchedules = List<StudyScheduleItem>.from(schedules);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'solo_mission_reminders',
        'Mission Reminders',
        channelDescription:
            'Mission reminders and important Shadow Learner updates.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final prefs = await SharedPreferences.getInstance();
    final previousIds = prefs.getStringList(_storedIdsKey) ?? <String>[];
    final newIds = <String>[];
    final exactAllowed = await canScheduleExactNotifications();
    final scheduleMode = exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    Future<void> scheduleWeekly({
      required int id,
      required int weekday,
      required int hour,
      required int minute,
      required String title,
      required String body,
    }) async {
      final now = tz.TZDateTime.now(tz.local);
      final nextStart = _nextWeeklyStart(weekday, hour, minute);
      final reminder = nextStart.subtract(const Duration(minutes: 5));

      if (reminder.isAfter(now)) {
        try {
          await _plugin.zonedSchedule(
            id, title, body, reminder, details,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: scheduleMode,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        } catch (error, stackTrace) {
          debugPrint('FAILED TO SCHEDULE REMINDER $id at $reminder: $error');
          debugPrintStack(stackTrace: stackTrace);
          rethrow;
        }
        newIds.add(id.toString());
        return;
      }

      // If a schedule is created inside its final five-minute window,
      // notify once immediately instead of silently postponing it for a week.
      final immediateId = id;
      await _plugin.zonedSchedule(
        immediateId,
        title,
        body,
        now.add(const Duration(seconds: 2)),
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: scheduleMode,
      );
      newIds.add(immediateId.toString());

      // Keep the normal weekly reminder for the next occurrence.
      final repeatId = (id ^ 0x40000000) & 0x7fffffff;
      final nextWeeklyReminder =
          nextStart.add(const Duration(days: 7)).subtract(
                const Duration(minutes: 5),
              );
      await _plugin.zonedSchedule(
        repeatId,
        title,
        body,
        nextWeeklyReminder,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: scheduleMode,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      newIds.add(repeatId.toString());
    }

    for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
      await scheduleWeekly(
        id: 11000 + (day - DateTime.monday) * 2,
        weekday: day,
        hour: 5,
        minute: 0,
        title: 'WAKEUP MISSION IN 5 MINUTES',
        body: 'Your Wakeup Mission starts at 5:00 AM. Get ready, Hunter.',
      );
      await scheduleWeekly(
        id: 11001 + (day - DateTime.monday) * 2,
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
      await scheduleWeekly(
        id: _stableId('schedule_${item.id}'),
        weekday: item.dayOfWeek,
        hour: hour,
        minute: minute,
        title: 'MISSION IN 5 MINUTES',
        body: 'Your ${item.subject} schedule starts at ${item.startTime}. Get ready, Hunter.',
      );
    }
    // Commit the new schedule first. Only then remove obsolete alarm IDs.
    final retainedIds = newIds.toSet();
    for (final value in previousIds) {
      if (retainedIds.contains(value)) continue;
      final id = int.tryParse(value);
      if (id != null) await _plugin.cancel(id);
    }
    await prefs.setStringList(_storedIdsKey, newIds);
    debugPrint(
      'MISSION REMINDERS SYNCED: ${schedules.length} schedules, '
      '${newIds.length} alarms, exact=$exactAllowed',
    );
  }

  @override
  void dispose() {
    _dailyCleanupTimer?.cancel();
    super.dispose();
  }
}
