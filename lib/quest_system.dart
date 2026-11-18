
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

  Set<String> completedQuestIds = {};

  bool isLoaded = false;

  String get todayKey {
    final now = DateTime.now();

    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // Daily Missions are generated from today's timetable.
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
        durationMinutes: 15,
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
        durationMinutes: 15,
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
      if (quest.id == questId) {
        return quest;
      }
    }

    return null;
  }

  Future<void> loadQuests() async {
    final prefs = await SharedPreferences.getInstance();

    final savedDate = prefs.getString('quest_date');

    if (savedDate != todayKey) {
      completedQuestIds = {};

      await prefs.setString('quest_date', todayKey);
      await prefs.setStringList('completed_quests', []);
    } else {
      completedQuestIds =
          (prefs.getStringList('completed_quests') ?? []).toSet();
    }

    isLoaded = true;
    notifyListeners();
  }

  // Called by StudyTimer for timetable-based missions.
  Future<int?> completeQuest(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;

    final quest = getQuestById(questId);

    if (quest == null || !quest.requiresTimer) {
      return null;
    }

    return _completeMission(quest, player);
  }

  // Called directly by the user for Wakeup and Sleeping.
  // These missions do not use the Study Timer.
  Future<int?> completeFixedMission(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;

    final quest = getQuestById(questId);

    if (quest == null || quest.requiresTimer) {
      return null;
    }

    // Fixed missions cannot be completed after their deadline.
    if (quest.isOverdue) {
      return null;
    }

    return _completeMission(quest, player);
  }

  Future<int?> _completeMission(
    StudyQuest quest,
    PlayerSystem player,
  ) async {
    if (isCompleted(quest.id)) return null;

    // Mark immediately to prevent duplicate XP from repeated taps.
    completedQuestIds.add(quest.id);

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('quest_date', todayKey);
    await prefs.setStringList(
      'completed_quests',
      completedQuestIds.toList(),
    );

    await player.addXp(quest.xpReward);

    notifyListeners();

    return quest.xpReward;
  }

  void _onTimetableChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    timetableSystem.removeListener(_onTimetableChanged);
    super.dispose();
  }
}
