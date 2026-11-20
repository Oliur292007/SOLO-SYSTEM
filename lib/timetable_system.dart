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

  /// Date key ("YYYY-MM-DD") when this schedule was last completed.
  /// null = not completed today.
  final String? completedDate;

  const StudyScheduleItem({
    required this.id,
    required this.dayOfWeek,
    required this.subject,
    required this.startTime,
    required this.durationMinutes,
    this.isOptional = false,
    this.completedDate,
  });

  StudyScheduleItem copyWith({
    String? id,
    int? dayOfWeek,
    String? subject,
    String? startTime,
    int? durationMinutes,
    bool? isOptional,
    Object? completedDate = _sentinel,
  }) {
    return StudyScheduleItem(
      id: id ?? this.id,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      subject: subject ?? this.subject,
      startTime: startTime ?? this.startTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isOptional: isOptional ?? this.isOptional,
      completedDate: identical(completedDate, _sentinel)
          ? this.completedDate
          : completedDate as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dayOfWeek': dayOfWeek,
      'subject': subject,
      'startTime': startTime,
      'durationMinutes': durationMinutes,
      'isOptional': isOptional,
      'completedDate': completedDate,
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
      completedDate: json['completedDate'] as String?,
    );
  }
}

const Object _sentinel = Object();

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
  // DATE HELPER
  // ============================================================

  String get todayKey {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // GETTERS
  // ============================================================

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

  StudyScheduleItem? getScheduleById(String id) {
    for (final item in _schedules) {
      if (item.id == id) return item;
    }
    return null;
  }

  // ============================================================
  // COMPLETION HELPERS
  // ============================================================

  bool isCompletedToday(String id) {
    final schedule = getScheduleById(id);
    if (schedule == null) return false;
    return schedule.completedDate == todayKey;
  }

  /// Mark a schedule as completed for the given date key.
  Future<bool> markCompleted(String id, {String? dateKey}) async {
    final key = dateKey ?? todayKey;
    final index = _schedules.indexWhere((item) => item.id == id);
    if (index == -1) return false;

    final previous = _schedules[index];
    if (previous.completedDate == key) return true; // already marked

    _schedules[index] = previous.copyWith(completedDate: key);

    final saved = await _saveTimetable();
    if (!saved) {
      _schedules[index] = previous; // rollback
      return false;
    }

    notifyListeners();
    return true;
  }

  /// Clear completion status for a specific schedule.
  Future<bool> clearCompleted(String id) async {
    final index = _schedules.indexWhere((item) => item.id == id);
    if (index == -1) return false;

    final previous = _schedules[index];
    if (previous.completedDate == null) return true; // already clear

    _schedules[index] = previous.copyWith(completedDate: null);

    final saved = await _saveTimetable();
    if (!saved) {
      _schedules[index] = previous; // rollback
      return false;
    }

    notifyListeners();
    return true;
  }

  /// Clear completion dates that are older than todayKey.
  /// Called on app load to enforce daily reset.
  Future<void> clearOldCompletions({String? referenceDateKey}) async {
    final ref = referenceDateKey ?? todayKey;
    bool changed = false;

    for (int i = 0; i < _schedules.length; i++) {
      final item = _schedules[i];
      if (item.completedDate == null) continue;
      if (item.completedDate == ref) continue;

      _schedules[i] = item.copyWith(completedDate: null);
      changed = true;
    }

    if (changed) {
      await _saveTimetable();
      notifyListeners();
    }
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

    // Enforce daily reset for completion flags.
    await clearOldCompletions();

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
    ValueChanged<String>? onError,
  }) async {
    final cleanSubject = subject.trim();

    final error = _validateInput(
      dayOfWeek: dayOfWeek,
      subject: cleanSubject,
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
      excludeId: null,
    );
    if (error != null) {
      onError?.call(error);
      return false;
    }

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
      _schedules.remove(item);
      onError?.call('Failed to save timetable.');
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
    ValueChanged<String>? onError,
  }) async {
    final cleanSubject = subject.trim();
    final index = _schedules.indexWhere((item) => item.id == id);
    if (index == -1) {
      onError?.call('Schedule not found.');
      return false;
    }

    final error = _validateInput(
      dayOfWeek: dayOfWeek,
      subject: cleanSubject,
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
      excludeId: id,
    );
    if (error != null) {
      onError?.call(error);
      return false;
    }

    final previous = _schedules[index];
    _schedules[index] = StudyScheduleItem(
      id: id,
      dayOfWeek: dayOfWeek,
      subject: cleanSubject,
      startTime: startTime,
      durationMinutes: durationMinutes,
      isOptional: isOptional,
      completedDate: previous.completedDate, // preserve
    );

    final saved = await _saveTimetable();
    if (!saved) {
      _schedules[index] = previous;
      onError?.call('Failed to save timetable.');
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
      _schedules.insert(index, removed);
      return false;
    }

    notifyListeners();
    return true;
  }

  // ============================================================
  // CLEAR ALL
  // ============================================================

  Future<bool> clearAllSchedules() async {
    if (_schedules.isEmpty) return true;

    final backup = List<StudyScheduleItem>.from(_schedules);
    _schedules.clear();

    final saved = await _saveTimetable();
    if (!saved) {
      _schedules.addAll(backup);
      return false;
    }

    notifyListeners();
    return true;
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  /// Returns null if valid, otherwise an error message.
  String? _validateInput({
    required int dayOfWeek,
    required String subject,
    required String startTime,
    required int durationMinutes,
    required bool isOptional,
    required String? excludeId,
  }) {
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      return 'Invalid day selected.';
    }
    if (subject.isEmpty) {
      return 'Enter a subject name.';
    }
    if (subject.length > _maxSubjectLength) {
      return 'Subject name is too long (max $_maxSubjectLength characters).';
    }
    if (durationMinutes <= 0) {
      return 'Duration must be greater than zero.';
    }
    if (!_isValidTime(startTime)) {
      return 'Invalid start time.';
    }
    if (isOptional && dayOfWeek != 5) {
      return 'Optional schedules are only allowed on Friday.';
    }

    // Option A: strict overlap prevention.
    // Block if another schedule exists on the same day at the same startTime.
    final conflict = _schedules.any((item) {
      if (item.id == excludeId) return false;
      if (item.dayOfWeek != dayOfWeek) return false;
      if (item.startTime != startTime) return false;
      return true;
    });

    if (conflict) {
      return 'Another schedule already starts at this exact time on this day.';
    }

    return null;
  }

  bool _isValidTime(String value) {
    return RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').hasMatch(value);
  }

  bool _isValidScheduleData(StudyScheduleItem item) {
    if (item.id.isEmpty) return false;
    if (item.dayOfWeek < 1 || item.dayOfWeek > 7) return false;
    if (item.subject.trim().isEmpty) return false;
    if (item.subject.length > _maxSubjectLength) return false;
    if (item.durationMinutes <= 0) return false;
    if (!_isValidTime(item.startTime)) return false;
    if (item.isOptional && item.dayOfWeek != 5) return false;

    // Note: do NOT re-run overlap detection on load —
    // historical data might contain overlaps from before this rule.
    return true;
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