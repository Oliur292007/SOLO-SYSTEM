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
  static const int _maxSubjectLength = 40;

  final List<StudyScheduleItem> _schedules = [];

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

  // ============================================================
  // GETTERS
  // ============================================================

  /// Unmodifiable view of all schedules.
  List<StudyScheduleItem> get allSchedules =>
      List.unmodifiable(_schedules);

  int get scheduleCount => _schedules.length;

  // ============================================================
  // GET SCHEDULES FOR A DAY
  // ============================================================

  List<StudyScheduleItem> getSchedulesForDay(int day) {
    final result =
        _schedules.where((item) => item.dayOfWeek == day).toList();
    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> loadTimetable() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString(_storageKey);

    _schedules.clear();

    if (savedData != null && savedData.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedData);
        for (final item in decoded) {
          final schedule = StudyScheduleItem.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (_isValidScheduleData(schedule)) {
            _schedules.add(schedule);
          }
        }
      } catch (_) {
        _schedules.clear();
      }
    }

    isLoaded = true;
    notifyListeners();
  }

  // ============================================================
  // ADD SCHEDULE
  // ============================================================

  Future<bool> addSchedule({
    required int dayOfWeek,
    required String subject,
    required String startTime,
    required int durationMinutes,
    bool isOptional = false,
  }) async {
    final cleanSubject = subject.trim();

    if (!_isValidInput(
      dayOfWeek: dayOfWeek,
      subject: cleanSubject,
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
    )) {
      return false;
    }

    // Duplicate check (same day + same startTime + same subject).
    final isDuplicate = _schedules.any(
      (item) =>
          item.dayOfWeek == dayOfWeek &&
          item.startTime == startTime &&
          item.subject.toLowerCase() == cleanSubject.toLowerCase(),
    );

    if (isDuplicate) return false;

    final item = StudyScheduleItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      dayOfWeek: dayOfWeek,
      subject: cleanSubject,
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
    );

    _schedules.add(item);

    final saved = await _saveTimetable();
    if (!saved) {
      _schedules.remove(item); // rollback
      return false;
    }

    notifyListeners();
    return true;
  }

  // ============================================================
  // UPDATE SCHEDULE
  // ============================================================

  Future<bool> updateSchedule(
    String id, {
    required int dayOfWeek,
    required String subject,
    required String startTime,
    required int durationMinutes,
    bool isOptional = false,
  }) async {
    final cleanSubject = subject.trim();
    final index = _schedules.indexWhere((item) => item.id == id);

    if (index == -1) return false;

    if (!_isValidInput(
      dayOfWeek: dayOfWeek,
      subject: cleanSubject,
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
    )) {
      return false;
    }

    // Duplicate check (exclude self).
    final isDuplicate = _schedules.any(
      (item) =>
          item.id != id &&
          item.dayOfWeek == dayOfWeek &&
          item.startTime == startTime &&
          item.subject.toLowerCase() == cleanSubject.toLowerCase(),
    );

    if (isDuplicate) return false;

    final previous = _schedules[index];
    _schedules[index] = StudyScheduleItem(
      id: id,
      dayOfWeek: dayOfWeek,
      subject: cleanSubject,
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
    );

    final saved = await _saveTimetable();
    if (!saved) {
      _schedules[index] = previous; // rollback
      return false;
    }

    notifyListeners();
    return true;
  }

  // ============================================================
  // DELETE SCHEDULE
  // ============================================================

  Future<bool> deleteSchedule(String id) async {
    final index = _schedules.indexWhere((item) => item.id == id);
    if (index == -1) return false;

    final removed = _schedules.removeAt(index);

    final saved = await _saveTimetable();
    if (!saved) {
      _schedules.insert(index, removed); // rollback
      return false;
    }

    notifyListeners();
    return true;
  }

  // ============================================================
  // CLEAR ALL (future use)
  // ============================================================

  Future<bool> clearAllSchedules() async {
    if (_schedules.isEmpty) return true;

    final backup = List<StudyScheduleItem>.from(_schedules);
    _schedules.clear();

    final saved = await _saveTimetable();
    if (!saved) {
      _schedules.addAll(backup); // rollback
      return false;
    }

    notifyListeners();
    return true;
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  bool _isValidInput({
    required int dayOfWeek,
    required String subject,
    required String startTime,
    required int durationMinutes,
    required bool isOptional,
  }) {
    if (dayOfWeek < 1 || dayOfWeek > 7) return false;
    if (subject.isEmpty) return false;
    if (subject.length > _maxSubjectLength) return false;
    if (durationMinutes <= 0) return false;
    if (!_isValidTime(startTime)) return false;
    // Optional schedules only allowed on Friday (day 5).
    if (isOptional && dayOfWeek != 5) return false;
    return true;
  }

  bool _isValidTime(String value) {
    return RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').hasMatch(value);
  }

  bool _isValidScheduleData(StudyScheduleItem item) {
    return _isValidInput(
      dayOfWeek: item.dayOfWeek,
      subject: item.subject,
      startTime: item.startTime,
      durationMinutes: item.durationMinutes,
      isOptional: item.isOptional,
    );
  }

  // ============================================================
  // PERSISTENCE
  // ============================================================

  Future<bool> _saveTimetable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _schedules.map((item) => item.toJson()).toList();
      return await prefs.setString(_storageKey, jsonEncode(data));
    } catch (_) {
      return false;
    }
  }
}