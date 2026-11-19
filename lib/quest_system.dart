
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_system.dart';
import 'timetable_system.dart';

class StudyQuest {
  final String id;
  final String name;
  final String subject;
  final int durationMinutes;
  final bool requiresTimer;
  final bool isOptional;
  final DateTime? deadline;
  final DateTime? availableFrom;

  const StudyQuest({
    required this.id,
    required this.name,
    required this.subject,
    required this.durationMinutes,
    this.requiresTimer = true,
    this.isOptional = false,
    this.deadline,
    this.availableFrom,
  });

  int get xpReward {
    if (isOptional || durationMinutes <= 0) return 0;

    return (durationMinutes / 15).ceil() * 25;
  }

  bool get isOverdue {
    if (deadline == null) return false;

    return DateTime.now().isAfter(deadline!);
  }

  bool get isAvailable {
    final now = DateTime.now();

    if (availableFrom != null && now.isBefore(availableFrom!)) {
      return false;
    }

    if (isOverdue) return false;

    return true;
  }
}

class QuestSystem extends ChangeNotifier {
  static const String _dateKey = 'quest_date';
  static const String _completedKey = 'completed_quests';
  static const String _snapshotKey = 'quest_snapshot';
  static const String _penaltyKey = 'penalty_until';
  static const String _nightLockKey = 'night_lock_active';

  static const Duration penaltyDuration = Duration(hours: 4);

  final TimetableSystem timetableSystem;

  QuestSystem({
    required this.timetableSystem,
  }) {
    timetableSystem.addListener(_onTimetableChanged);
  }

  final Set<String> completedQuestIds = {};

  bool isLoaded = false;
  bool isNightLockActive = false;

  DateTime? penaltyUntil;

  Timer? _deadlineTimer;

  String _loadedDateKey = '';

  bool _isCheckingDeadlines = false;
  bool _isSavingSnapshot = false;

  // DATE

  String get todayKey {
    final now = DateTime.now();

    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  DateTime _dateAt(int hour, int minute) {
    final now = DateTime.now();

    return DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
  }

  // QUEST LIST

  List<StudyQuest> get quests {
    final List<StudyQuest> result = [];

    final wakeupStart = _dateAt(5, 0);
    final wakeupDeadline = _dateAt(8, 30);

    result.add(
      StudyQuest(
        id: 'wakeup',
        name: 'Wakeup',
        subject: 'Daily Routine',
        durationMinutes: 0,
        requiresTimer: false,
        deadline: wakeupDeadline,
        availableFrom: wakeupStart,
      ),
    );

    final now = DateTime.now();
    final todayWeekday = now.weekday;

    for (final schedule
        in timetableSystem.getSchedulesForDay(todayWeekday)) {
      final timeParts = schedule.startTime.split(':');

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final start = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      final deadline = start.add(
        Duration(minutes: schedule.durationMinutes),
      );

      result.add(
        StudyQuest(
          id: 'schedule_${schedule.id}',
          name: schedule.subject,
          subject: schedule.subject,
          durationMinutes: schedule.durationMinutes,
          requiresTimer: true,
          isOptional: schedule.isOptional,
          deadline: deadline,
          availableFrom: start,
        ),
      );
    }

    final sleepingStart = _dateAt(20, 0);
    final sleepingDeadline = _dateAt(23, 58);

    result.add(
      StudyQuest(
        id: 'sleeping',
        name: 'Sleeping',
        subject: 'Daily Routine',
        durationMinutes: 0,
        requiresTimer: false,
        deadline: sleepingDeadline,
        availableFrom: sleepingStart,
      ),
    );

    return result;
  }

  // PROGRESS

  int get totalQuests => quests.length;

  int get totalCount => totalQuests;

  int get completedCount => completedQuestIds.length;

  int get remainingCount => totalQuests - completedCount;

  double get progress {
    if (totalQuests == 0) return 0;

    return (completedCount / totalQuests)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  bool isCompleted(String questId) {
    return completedQuestIds.contains(questId);
  }

  StudyQuest? getQuestById(String questId) {
    for (final quest in quests) {
      if (quest.id == questId) return quest;
    }

    return null;
  }

  // LOCK STATUS

  bool get isPenaltyActive {
    if (penaltyUntil == null) return false;

    return DateTime.now().isBefore(penaltyUntil!);
  }

  bool get isAppLockActive {
    return isPenaltyActive || isNightLockActive;
  }

  String get lockStatus {
    if (isPenaltyActive) return 'PENALTY ACTIVE';

    if (isNightLockActive) return 'NIGHT LOCK ACTIVE';

    return 'UNLOCKED';
  }

  Duration get penaltyRemaining {
    if (!isPenaltyActive || penaltyUntil == null) {
      return Duration.zero;
    }

    final remaining = penaltyUntil!.difference(DateTime.now());

    return remaining.isNegative ? Duration.zero : remaining;
  }

  // LOAD

  Future<void> loadQuests() async {
    final prefs = await SharedPreferences.getInstance();

    final savedDate = prefs.getString(_dateKey);
    final savedCompleted = prefs.getStringList(_completedKey);

    completedQuestIds
      ..clear()
      ..addAll(savedCompleted ?? []);

    final savedPenalty = prefs.getInt(_penaltyKey);

    if (savedPenalty != null) {
      penaltyUntil = DateTime.fromMillisecondsSinceEpoch(
        savedPenalty,
      );
    }

    isNightLockActive =
        prefs.getBool(_nightLockKey) ?? false;

    final snapshotData = prefs.getString(_snapshotKey);

    if (savedDate == null || savedDate.isEmpty) {
      // First installation.
      _loadedDateKey = todayKey;

      completedQuestIds.clear();

      final now = DateTime.now();

      // First installation after 08:30:
      // Wakeup is automatically completed for this day only.
      if (now.isAfter(_dateAt(8, 30))) {
        completedQuestIds.add('wakeup');
      }

      await _saveCompleted();
      await _saveDate();
      await _saveQuestSnapshot();
    } else if (savedDate != todayKey) {
      // App was not opened on the previous date.
      _loadedDateKey = savedDate;

      await _evaluatePreviousDay(snapshotData);

      completedQuestIds.clear();

      _loadedDateKey = todayKey;

      await _saveCompleted();
      await _saveDate();
      await _saveQuestSnapshot();
    } else {
      _loadedDateKey = todayKey;

      if (snapshotData == null || snapshotData.isEmpty) {
        await _saveQuestSnapshot();
      }
    }

    isLoaded = true;

    await _checkDeadlines();

    _startDeadlineChecker();

    notifyListeners();
  }

  // COMPLETE FIXED MISSION

  Future<int?> completeFixedMission(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;

    if (questId != 'wakeup' && questId != 'sleeping') {
      return null;
    }

    final quest = getQuestById(questId);

    if (quest == null) return null;
    if (isCompleted(questId)) return null;
    if (!quest.isAvailable) return null;

    return _completeMission(quest, player);
  }

  // COMPLETE TIMER MISSION

  Future<int?> completeQuest(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;

    final quest = getQuestById(questId);

    if (quest == null) return null;
    if (!quest.requiresTimer) return null;
    if (isCompleted(questId)) return null;

    if (!quest.isAvailable) return null;

    return _completeMission(quest, player);
  }

  // COMMON COMPLETION

  Future<int?> _completeMission(
    StudyQuest quest,
    PlayerSystem player,
  ) async {
    if (isCompleted(quest.id)) return null;

    completedQuestIds.add(quest.id);

    await _saveCompleted();

    if (quest.id == 'sleeping') {
      isNightLockActive = true;

      await _saveNightLock();
    }

    if (quest.id == 'wakeup') {
      isNightLockActive = false;

      await _saveNightLock();
    }

    final earnedXp = quest.xpReward;

    if (earnedXp > 0) {
      await player.addXp(earnedXp);
    }

    notifyListeners();

    return earnedXp;
  }

  // DEADLINE CHECKER

  void _startDeadlineChecker() {
    _deadlineTimer?.cancel();

    _deadlineTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        if (!isLoaded) return;

        await _checkDeadlines();
      },
    );
  }

  Future<void> _checkDeadlines() async {
    if (_isCheckingDeadlines || !isLoaded) return;

    _isCheckingDeadlines = true;

    try {
      await _checkDateRollover();

      final now = DateTime.now();

      for (final quest in quests) {
        if (isCompleted(quest.id)) continue;
        if (quest.deadline == null) continue;

        if (!now.isAfter(quest.deadline!)) continue;

        if (quest.isOptional) {
          // Optional missions never cause a penalty.
          completedQuestIds.add(quest.id);

          await _saveCompleted();

          continue;
        }

        if (quest.id == 'sleeping') {
          // Sleeping failure activates Night Lock only.
          isNightLockActive = true;

          completedQuestIds.add(quest.id);

          await _saveNightLock();
          await _saveCompleted();

          continue;
        }

        if (quest.id == 'wakeup') {
          // Wakeup failure removes Night Lock
          // and starts the normal 4-hour penalty.
          isNightLockActive = false;

          await _saveNightLock();

          await _startPenalty(quest.deadline!);

          completedQuestIds.add(quest.id);

          await _saveCompleted();

          continue;
        }

        // Any other missed mandatory mission.
        await _startPenalty(quest.deadline!);

        completedQuestIds.add(quest.id);

        await _saveCompleted();
      }

      await _savePenalty();

      notifyListeners();
    } finally {
      _isCheckingDeadlines = false;
    }
  }

  // DATE ROLLOVER

  Future<void> _checkDateRollover() async {
    if (_loadedDateKey == todayKey) return;

    final prefs = await SharedPreferences.getInstance();

    final snapshotData = prefs.getString(_snapshotKey);

    await _evaluatePreviousDay(snapshotData);

    completedQuestIds.clear();

    _loadedDateKey = todayKey;

    await _saveCompleted();
    await _saveDate();
    await _saveQuestSnapshot();
  }

  // EVALUATE PREVIOUS DAY

  Future<void> _evaluatePreviousDay(
    String? snapshotData,
  ) async {
    if (snapshotData == null || snapshotData.isEmpty) {
      return;
    }

    try {
      final List<dynamic> decoded = jsonDecode(snapshotData);

      final List<Map<String, dynamic>> previousQuests =
          decoded
              .map(
                (item) => Map<String, dynamic>.from(item),
              )
              .toList();

      // Process missions in deadline order.
      // Wakeup is evaluated before Sleeping.
      previousQuests.sort((a, b) {
        final aDeadline = a['deadline'] as int;
        final bDeadline = b['deadline'] as int;

        return aDeadline.compareTo(bDeadline);
      });

      for (final item in previousQuests) {
        final id = item['id'] as String;
        final deadline = DateTime.fromMillisecondsSinceEpoch(
          item['deadline'] as int,
        );

        final isOptional = item['optional'] as bool? ?? false;

        if (completedQuestIds.contains(id)) continue;
        if (isOptional) continue;

        if (id == 'sleeping') {
          isNightLockActive = true;

          await _saveNightLock();

          continue;
        }

        if (id == 'wakeup') {
          isNightLockActive = false;

          await _saveNightLock();

          await _startPenalty(deadline);

          continue;
        }

        await _startPenalty(deadline);
      }
    } catch (_) {
      // Ignore invalid or corrupted old snapshot data.
    }

    await _savePenalty();
  }

  // PENALTY

  Future<void> _startPenalty(
    DateTime missedDeadline,
  ) async {
    final newPenaltyEnd = missedDeadline.add(
      penaltyDuration,
    );

    // Do not create an already-expired penalty.
    if (!DateTime.now().isBefore(newPenaltyEnd)) {
      return;
    }

    // Keep the later active penalty if one already exists.
    if (penaltyUntil != null &&
        penaltyUntil!.isAfter(newPenaltyEnd)) {
      return;
    }

    penaltyUntil = newPenaltyEnd;

    await _savePenalty();
  }

  // SNAPSHOT

  Future<void> _saveQuestSnapshot() async {
    if (_isSavingSnapshot) return;

    _isSavingSnapshot = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      final oldData = prefs.getString(_snapshotKey);

      final Map<String, Map<String, dynamic>> snapshot = {};

      // Preserve old overdue obligations that are still incomplete.
      if (oldData != null && oldData.isNotEmpty) {
        try {
          final List<dynamic> oldList = jsonDecode(oldData);

          for (final entry in oldList) {
            final item = Map<String, dynamic>.from(entry);

            final id = item['id'] as String;
            final deadline = DateTime.fromMillisecondsSinceEpoch(
              item['deadline'] as int,
            );

            final alreadyCompleted =
                completedQuestIds.contains(id);

            final isOptional =
                item['optional'] as bool? ?? false;

            if (!alreadyCompleted &&
                !isOptional &&
                DateTime.now().isAfter(deadline)) {
              snapshot[id] = item;
            }
          }
        } catch (_) {
          snapshot.clear();
        }
      }

      // Add or update today's current obligations.
      for (final quest in quests) {
        if (quest.deadline == null) continue;
        if (isCompleted(quest.id)) continue;

        // Do not overwrite an already overdue obligation.
        if (snapshot.containsKey(quest.id)) continue;

        snapshot[quest.id] = {
          'id': quest.id,
          'deadline': quest.deadline!
              .millisecondsSinceEpoch,
          'optional': quest.isOptional,
        };
      }

      await prefs.setString(
        _snapshotKey,
        jsonEncode(snapshot.values.toList()),
      );
    } finally {
      _isSavingSnapshot = false;
    }
  }

  // TIMETABLE CHANGE

  void _onTimetableChanged() {
    if (!isLoaded) return;

    _handleTimetableChange();
  }

  Future<void> _handleTimetableChange() async {
    await _saveQuestSnapshot();
    await _checkDeadlines();

    notifyListeners();
  }

  // PERSISTENCE

  Future<void> _saveCompleted() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      _completedKey,
      completedQuestIds.toList(),
    );
  }

  Future<void> _saveDate() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _dateKey,
      _loadedDateKey,
    );
  }

  Future<void> _savePenalty() async {
    final prefs = await SharedPreferences.getInstance();

    if (penaltyUntil != null) {
      await prefs.setInt(
        _penaltyKey,
        penaltyUntil!.millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_penaltyKey);
    }
  }

  Future<void> _saveNightLock() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      _nightLockKey,
      isNightLockActive,
    );
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();

    timetableSystem.removeListener(
      _onTimetableChanged,
    );

    super.dispose();
  }
}
