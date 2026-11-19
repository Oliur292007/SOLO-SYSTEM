
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
    if (availableFrom == null) return true;
    return !DateTime.now().isBefore(availableFrom!);
  }
}

class QuestSystem extends ChangeNotifier {
  final TimetableSystem timetableSystem;

  QuestSystem({
    required this.timetableSystem,
  }) {
    timetableSystem.addListener(_onTimetableChanged);
  }

  static const String _dateKey = 'quest_date';
  static const String _completedKey = 'completed_quests';
  static const String _snapshotKey = 'quest_snapshot';
  static const String _penaltyKey = 'penalty_until';
  static const String _nightLockKey = 'night_lock_active';

  static const Duration penaltyDuration = Duration(hours: 4);

  Set<String> completedQuestIds = {};

  bool isLoaded = false;
  bool isNightLockActive = false;

  DateTime? penaltyUntil;

  Timer? _deadlineTimer;
  String? _loadedDateKey;

  String get todayKey {
    final now = DateTime.now();

    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool get isPenaltyActive {
    return penaltyUntil != null &&
        DateTime.now().isBefore(penaltyUntil!);
  }

  bool get isAppLockActive {
    return isNightLockActive || isPenaltyActive;
  }

  String get lockStatus {
    if (isPenaltyActive) return 'PENALTY LOCK';
    if (isNightLockActive) return 'NIGHT LOCK';
    return 'UNLOCKED';
  }

  Duration get penaltyRemaining {
    if (!isPenaltyActive) return Duration.zero;
    return penaltyUntil!.difference(DateTime.now());
  }

  List<StudyQuest> get quests {
    final now = DateTime.now();

    final wakeupAvailable = DateTime(
      now.year,
      now.month,
      now.day,
      5,
    );

    final wakeupDeadline = DateTime(
      now.year,
      now.month,
      now.day,
      8,
      30,
    );

    final sleepingAvailable = DateTime(
      now.year,
      now.month,
      now.day,
      20,
    );

    final sleepingDeadline = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      58,
    );

    final dailyQuests = <StudyQuest>[
      StudyQuest(
        id: 'wakeup',
        name: 'Wakeup',
        subject: 'Start your day on time',
        durationMinutes: 0,
        requiresTimer: false,
        availableFrom: wakeupAvailable,
        deadline: wakeupDeadline,
      ),
    ];

    final todaySchedules =
        timetableSystem.getSchedulesForDay(now.weekday);

    for (final item in todaySchedules) {
      final parts = item.startTime.split(':');

      final startHour = int.parse(parts[0]);
      final startMinute = int.parse(parts[1]);

      final start = DateTime(
        now.year,
        now.month,
        now.day,
        startHour,
        startMinute,
      );

      final end = start.add(
        Duration(minutes: item.durationMinutes),
      );

      dailyQuests.add(
        StudyQuest(
          id: 'schedule_${item.id}',
          name: item.subject,
          subject: 'Study Mission',
          durationMinutes: item.durationMinutes,
          requiresTimer: true,
          isOptional: item.isOptional,
          deadline: end,
        ),
      );
    }

    dailyQuests.add(
      StudyQuest(
        id: 'sleeping',
        name: 'Sleeping',
        subject: 'Complete your day and get proper rest',
        durationMinutes: 0,
        requiresTimer: false,
        availableFrom: sleepingAvailable,
        deadline: sleepingDeadline,
      ),
    );

    return dailyQuests;
  }

  int get completedCount {
    return quests
        .where((quest) => completedQuestIds.contains(quest.id))
        .length;
  }

  int get totalCount => quests.length;

  double get progress {
    return totalCount == 0 ? 0 : completedCount / totalCount;
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

  Future<void> loadQuests() async {
    final prefs = await SharedPreferences.getInstance();

    final savedDate = prefs.getString(_dateKey);
    final isFirstInstallation = savedDate == null;

    final savedPenalty = prefs.getString(_penaltyKey);

    if (savedPenalty != null) {
      penaltyUntil = DateTime.tryParse(savedPenalty);
    }

    isNightLockActive =
        prefs.getBool(_nightLockKey) ?? false;

    if (savedDate != todayKey) {
      if (savedDate != null) {
        final oldCompleted =
            (prefs.getStringList(_completedKey) ?? []).toSet();

        final oldSnapshot =
            prefs.getString(_snapshotKey);

        if (oldSnapshot != null) {
          await _evaluatePreviousDay(
            oldSnapshot,
            oldCompleted,
          );
        }
      }

      completedQuestIds = {};

      await prefs.setString(_dateKey, todayKey);
      await prefs.setStringList(_completedKey, []);
    } else {
      completedQuestIds =
          (prefs.getStringList(_completedKey) ?? []).toSet();
    }

    isLoaded = true;
    _loadedDateKey = todayKey;

    // First installation after 8:30 AM:
    // Automatically complete Wakeup only for this day.
    final now = DateTime.now();

    final todayWakeupDeadline = DateTime(
      now.year,
      now.month,
      now.day,
      8,
      30,
    );

    if (isFirstInstallation &&
        now.isAfter(todayWakeupDeadline)) {
      completedQuestIds.add('wakeup');

      await prefs.setStringList(
        _completedKey,
        completedQuestIds.toList(),
      );
    }

    await _saveQuestSnapshot();
    await _checkDeadlines();

    _deadlineTimer?.cancel();

    _deadlineTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        final previousStatus = lockStatus;

        await _checkDeadlines();

        if (previousStatus != lockStatus) {
          notifyListeners();
        }
      },
    );

    notifyListeners();
  }

  Future<void> _saveQuestSnapshot() async {
    if (!isLoaded) return;

    final prefs = await SharedPreferences.getInstance();

    final snapshot = quests.map((quest) {
      return {
        'id': quest.id,
        'deadline': quest.deadline?.toIso8601String(),
        'optional': quest.isOptional,
      };
    }).toList();

    await prefs.setString(
      _snapshotKey,
      jsonEncode(snapshot),
    );
  }

  Future<void> _evaluatePreviousDay(
    String snapshotJson,
    Set<String> oldCompleted,
  ) async {
    try {
      final List<dynamic> snapshot = jsonDecode(snapshotJson);

      DateTime? getDeadline(dynamic entry) {
        final text = entry['deadline'] as String?;
        if (text == null) return null;
        return DateTime.tryParse(text);
      }

      bool missed(dynamic entry) {
        final id = entry['id'] as String;
        final optional = entry['optional'] as bool? ?? false;
        final deadline = getDeadline(entry);

        return !optional &&
            !oldCompleted.contains(id) &&
            deadline != null &&
            DateTime.now().isAfter(deadline);
      }

      // Sleeping failure activates Night Lock.
      for (final entry in snapshot) {
        if (entry['id'] == 'sleeping' && missed(entry)) {
          await _activateNightLock();
        }
      }

      // Wakeup failure removes Night Lock and starts penalty.
      for (final entry in snapshot) {
        if (entry['id'] == 'wakeup' && missed(entry)) {
          final deadline = getDeadline(entry)!;

          await _deactivateNightLock();
          await _startPenalty(deadline);
        }
      }

      // Other mandatory missions start normal penalty.
      for (final entry in snapshot) {
        final id = entry['id'] as String;

        if (id == 'sleeping' || id == 'wakeup') continue;

        if (missed(entry)) {
          final deadline = getDeadline(entry)!;
          await _startPenalty(deadline);
        }
      }
    } catch (_) {
      // Ignore invalid saved snapshot.
    }
  }

  Future<void> _checkDateRollover() async {
    if (_loadedDateKey == null ||
        _loadedDateKey == todayKey) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final oldCompleted = completedQuestIds.toSet();
    final oldSnapshot = prefs.getString(_snapshotKey);

    if (oldSnapshot != null) {
      await _evaluatePreviousDay(
        oldSnapshot,
        oldCompleted,
      );
    }

    completedQuestIds = {};

    await prefs.setString(_dateKey, todayKey);
    await prefs.setStringList(_completedKey, []);

    _loadedDateKey = todayKey;

    await _saveQuestSnapshot();

    notifyListeners();
  }

  Future<void> _checkDeadlines() async {
    if (!isLoaded) return;

    await _checkDateRollover();

    final now = DateTime.now();

    for (final quest in quests) {
      if (isCompleted(quest.id)) continue;
      if (quest.deadline == null) continue;
      if (!now.isAfter(quest.deadline!)) continue;

      // Sleeping failure: Night Lock only.
      if (quest.id == 'sleeping') {
        await _activateNightLock();
        continue;
      }

      // Wakeup failure: remove Night Lock + 4-hour penalty.
      if (quest.id == 'wakeup') {
        await _deactivateNightLock();
        await _startPenalty(quest.deadline!);
        continue;
      }

      // Optional missions never cause penalties.
      if (quest.isOptional) continue;

      // Other mandatory missions: 4-hour penalty.
      await _startPenalty(quest.deadline!);
    }
  }

  Future<void> _activateNightLock() async {
    if (isNightLockActive) return;

    isNightLockActive = true;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      _nightLockKey,
      true,
    );

    notifyListeners();
  }

  Future<void> _deactivateNightLock() async {
    if (!isNightLockActive) return;

    isNightLockActive = false;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      _nightLockKey,
      false,
    );

    notifyListeners();
  }

  Future<void> _startPenalty(DateTime missedDeadline) async {
    final newPenaltyEnd = missedDeadline.add(
      penaltyDuration,
    );

    if (penaltyUntil != null &&
        !newPenaltyEnd.isAfter(penaltyUntil!)) {
      return;
    }

    penaltyUntil = newPenaltyEnd;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _penaltyKey,
      penaltyUntil!.toIso8601String(),
    );

    notifyListeners();
  }

  Future<int?> completeQuest(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;

    final quest = getQuestById(questId);

    if (quest == null || !quest.requiresTimer) {
      return null;
    }

    if (quest.isOverdue) {
      await _checkDeadlines();
      return null;
    }

    return _completeMission(quest, player);
  }

  Future<int?> completeFixedMission(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;

    final quest = getQuestById(questId);

    if (quest == null || quest.requiresTimer) {
      return null;
    }

    // Cannot complete before the mission becomes available.
    if (!quest.isAvailable) return null;

    if (quest.isOverdue) {
      await _checkDeadlines();
      return null;
    }

    return _completeMission(quest, player);
  }

  Future<int?> _completeMission(
    StudyQuest quest,
    PlayerSystem player,
  ) async {
    if (isCompleted(quest.id)) return null;

    completedQuestIds.add(quest.id);

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_dateKey, todayKey);

    await prefs.setStringList(
      _completedKey,
      completedQuestIds.toList(),
    );

    // Sleeping completion activates Night Lock.
    if (quest.id == 'sleeping') {
      await _activateNightLock();
    }

    // Successful Wakeup removes Night Lock.
    // An active Penalty Lock remains unaffected.
    if (quest.id == 'wakeup') {
      await _deactivateNightLock();
    }

    // Optional missions award zero XP.
    if (quest.xpReward > 0) {
      await player.addXp(quest.xpReward);
    }

    notifyListeners();

    return quest.xpReward;
  }

  void _onTimetableChanged() {
    notifyListeners();

    if (isLoaded) {
      _saveQuestSnapshot();
      _checkDeadlines();
    }
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();

    timetableSystem.removeListener(_onTimetableChanged);

    super.dispose();
  }
}
