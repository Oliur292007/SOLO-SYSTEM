
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player_system.dart';

class StudyQuest {
  final String id;
  final String name;
  final String subject;
  final int durationMinutes;

  const StudyQuest({
    required this.id,
    required this.name,
    required this.subject,
    required this.durationMinutes,
  });

  int get xpReward => (durationMinutes / 15).ceil() * 25;
}

class QuestSystem extends ChangeNotifier {
  final List<StudyQuest> quests = const [
    StudyQuest(
      id: 'math',
      name: 'Mathematics',
      subject: 'Study',
      durationMinutes: 60,
    ),
    StudyQuest(
      id: 'physics',
      name: 'Physics',
      subject: 'Study',
      durationMinutes: 60,
    ),
    StudyQuest(
      id: 'chemistry',
      name: 'Chemistry',
      subject: 'Study',
      durationMinutes: 60,
    ),
    StudyQuest(
      id: 'english',
      name: 'English',
      subject: 'Study',
      durationMinutes: 30,
    ),
  ];

  Set<String> completedQuestIds = {};

  bool isLoaded = false;

  String get todayKey {
    final now = DateTime.now();

    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  int get completedCount => completedQuestIds.length;

  int get totalCount => quests.length;

  double get progress =>
      totalCount == 0 ? 0 : completedCount / totalCount;

  bool isCompleted(String questId) {
    return completedQuestIds.contains(questId);
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

  Future<int?> completeQuest(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;

    if (isCompleted(questId)) return null;

    StudyQuest? selectedQuest;

    for (final quest in quests) {
      if (quest.id == questId) {
        selectedQuest = quest;
        break;
      }
    }

    if (selectedQuest == null) return null;

    completedQuestIds.add(questId);

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('quest_date', todayKey);
    await prefs.setStringList(
      'completed_quests',
      completedQuestIds.toList(),
    );

    await player.addXp(selectedQuest.xpReward);

    notifyListeners();

    return selectedQuest.xpReward;
  }
}
