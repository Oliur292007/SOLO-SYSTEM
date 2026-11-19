
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudyScheduleItem {
  final String id;
  final int dayOfWeek;
  final String subject;
  final String startTime;
  final int durationMinutes;
  final bool isOptional;

  const StudyScheduleItem({
    required this.id,
    required this.dayOfWeek,
    required this.subject,
    required this.startTime,
    required this.durationMinutes,
    this.isOptional = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dayOfWeek': dayOfWeek,
      'subject': subject,
      'startTime': startTime,
      'durationMinutes': durationMinutes,
      'isOptional': isOptional,
    };
  }

  factory StudyScheduleItem.fromJson(Map<String, dynamic> json) {
    return StudyScheduleItem(
      id: json['id'] as String,
      dayOfWeek: json['dayOfWeek'] as int,
      subject: json['subject'] as String,
      startTime: json['startTime'] as String,
      durationMinutes: json['durationMinutes'] as int,
      isOptional: json['isOptional'] as bool? ?? false,
    );
  }
}

class TimetableSystem extends ChangeNotifier {
  static const String _storageKey = 'study_timetable';

  final List<StudyScheduleItem> schedules = [];

  bool isLoaded = false;

  static const List<String> weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // GET SCHEDULES FOR A DAY

  List<StudyScheduleItem> getSchedulesForDay(int day) {
    final result = schedules
        .where((item) => item.dayOfWeek == day)
        .toList();

    result.sort(
      (a, b) => a.startTime.compareTo(b.startTime),
    );

    return result;
  }

  // LOAD TIMETABLE

  Future<void> loadTimetable() async {
    final prefs = await SharedPreferences.getInstance();

    final savedData = prefs.getString(_storageKey);

    schedules.clear();

    if (savedData != null) {
      try {
        final List<dynamic> decoded = jsonDecode(savedData);

        for (final item in decoded) {
          final schedule = StudyScheduleItem.fromJson(
            Map<String, dynamic>.from(item),
          );

          if (_isValidScheduleData(schedule)) {
            schedules.add(schedule);
          }
        }
      } catch (_) {
        schedules.clear();
      }
    }

    isLoaded = true;
    notifyListeners();
  }

  // ADD SCHEDULE

  Future<bool> addSchedule({
    required int dayOfWeek,
    required String subject,
    required String startTime,
    required int durationMinutes,
    bool isOptional = false,
  }) async {
    final cleanSubject = subject.trim();

    if (dayOfWeek < 1 || dayOfWeek > 7) return false;
    if (cleanSubject.isEmpty) return false;
    if (durationMinutes <= 0) return false;
    if (!_isValidTime(startTime)) return false;

    // Optional schedules are allowed only on Friday.
    // Friday can contain both Mandatory and Optional schedules.

    if (isOptional && dayOfWeek != 5) return false;

    final item = StudyScheduleItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      dayOfWeek: dayOfWeek,
      subject: cleanSubject,
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
    );

    schedules.add(item);

    await _saveTimetable();

    notifyListeners();

    return true;
  }

  // UPDATE SCHEDULE

  Future<bool> updateSchedule(
    String id, {
    required int dayOfWeek,
    required String subject,
    required String startTime,
    required int durationMinutes,
    bool isOptional = false,
  }) async {
    final index = schedules.indexWhere(
      (item) => item.id == id,
    );

    if (index == -1) return false;
    if (dayOfWeek < 1 || dayOfWeek > 7) return false;
    if (subject.trim().isEmpty) return false;
    if (durationMinutes <= 0) return false;
    if (!_isValidTime(startTime)) return false;

    if (isOptional && dayOfWeek != 5) return false;

    schedules[index] = StudyScheduleItem(
      id: id,
      dayOfWeek: dayOfWeek,
      subject: subject.trim(),
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
    );

    await _saveTimetable();

    notifyListeners();

    return true;
  }

  // DELETE SCHEDULE

  Future<void> deleteSchedule(String id) async {
    schedules.removeWhere((item) => item.id == id);

    await _saveTimetable();

    notifyListeners();
  }

  // VALIDATE TIME

  bool _isValidTime(String value) {
    return RegExp(
      r'^([01]\d|2[0-3]):([0-5]\d)$',
    ).hasMatch(value);
  }

  // VALIDATE SAVED SCHEDULE

  bool _isValidScheduleData(StudyScheduleItem item) {
    if (item.id.isEmpty) return false;
    if (item.dayOfWeek < 1 || item.dayOfWeek > 7) return false;
    if (item.subject.trim().isEmpty) return false;
    if (item.durationMinutes <= 0) return false;
    if (!_isValidTime(item.startTime)) return false;

    if (item.isOptional && item.dayOfWeek != 5) {
      return false;
    }

    return true;
  }

  // SAVE TIMETABLE

  Future<void> _saveTimetable() async {
    final prefs = await SharedPreferences.getInstance();

    final data = schedules
        .map((item) => item.toJson())
        .toList();

    await prefs.setString(
      _storageKey,
      jsonEncode(data),
    );
  }
}
