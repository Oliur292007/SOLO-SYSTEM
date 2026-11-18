
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

  const StudyQuest({
    required this.id,
    required this.name,
    required this.subject,
    required this.durationMinutes,
    this.requiresTimer = true,
    this.isOptional = false,
    this.deadline,
  });

  int get xpReward => (durationMinutes / 15).ceil() * 25;

  bool get isOverdue {
    if (deadline == null) return false;
    return DateTime.now().isAfter(deadline!);
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

  Set<String> completedQuestIds = {};

  bool isLoaded = false;

  DateTime? penaltyUntil;

  Timer? _deadlineTimer;

  String get todayKey {
    final now = DateTime.now();

    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool get isPenaltyActive {
    return penaltyUntil != null &&
        DateTime.now().isBefore(penaltyUntil!);
  }

  Duration get penaltyRemaining {
    if (!isPenaltyActive) return Duration.zero;

    return penaltyUntil!.difference(DateTime.now());
  }

  List<StudyQuest> get quests {
    final now = DateTime.now();

    final wakeupDeadline = DateTime(
      now.year,
      now.month,
      now.day,
      8,
      30,
    );

    final sleepingDeadline = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    );

    final dailyQuests = <StudyQuest>[
      StudyQuest(
        id: 'wakeup',
        name: 'Wakeup',
        subject: 'Start your day on time',
        durationMinutes: 0,
        requiresTimer: false,
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

    final savedPenalty = prefs.getString(_penaltyKey);

    if (savedPenalty != null) {
      penaltyUntil = DateTime.tryParse(savedPenalty);
    }

    if (savedDate != todayKey) {
      // Check the previous day's unfinished missions
      // before resetting daily completion data.
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

    await _saveQuestSnapshot();
    await _checkDeadlines();

    _deadlineTimer?.cancel();

    _deadlineTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkDeadlines(),
    );

    notifyListeners();
  }

  // Save today's mission deadlines so they can
  // still be checked after the app is closed.
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

  // Detect missed missions from the previous day.
  Future<void> _evaluatePreviousDay(
    String snapshotJson,
    Set<String> oldCompleted,
  ) async {
    try {
      final List<dynamic> snapshot =
          jsonDecode(snapshotJson);

      for (final entry in snapshot) {
        final id = entry['id'] as String;
        final deadlineText = entry['deadline'] as String?;
        final optional = entry['optional'] as bool? ?? false;

        if (optional || oldCompleted.contains(id)) {
          continue;
        }

        if (deadlineText == null) continue;

        final deadline = DateTime.tryParse(deadlineText);

        if (deadline == null) continue;

        if (DateTime.now().isAfter(deadline)) {
          await _startPenalty(deadline);
        }
      }
    } catch (_) {
      // Ignore an invalid saved snapshot.
    }
  }

  // Check today's mandatory missions.
  Future<void> _checkDeadlines() async {
    if (!isLoaded) return;

    final now = DateTime.now();

    for (final quest in quests) {
      if (quest.isOptional) continue;
      if (isCompleted(quest.id)) continue;
      if (quest.deadline == null) continue;

      if (now.isAfter(quest.deadline!)) {
        await _startPenalty(quest.deadline!);
      }
    }
  }

  // A missed mission starts a 24-hour penalty.
  // If another mandatory mission is missed later,
  // the penalty end time moves forward accordingly.
  Future<void> _startPenalty(DateTime missedDeadline) async {
    final newPenaltyEnd = missedDeadline.add(
      const Duration(hours: 24),
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

    await player.addXp(quest.xpReward);

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
