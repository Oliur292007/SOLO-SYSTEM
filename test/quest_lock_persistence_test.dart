import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/player_system.dart';
import '../lib/quest_system.dart';
import '../lib/rest_system.dart';
import '../lib/timetable_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('penalty expiry and Night Lock state survive app restart', () async {
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final penaltyExpiry = now.add(const Duration(hours: 3));

    SharedPreferences.setMockInitialValues({
      'quest_date': todayKey,
      'completed_quests': ['wakeup'],
      'missed_quests': <String>[],
      'skipped_quests': <String>[],
      'penalty_until': penaltyExpiry.millisecondsSinceEpoch,
      'night_lock_active': true,
      'hp_critical_penalty_applied': true,
    });

    final player = PlayerSystem();
    await player.loadPlayer();

    final rest = RestSystem(player: player);
    await rest.loadRest();

    final timetable = TimetableSystem();
    await timetable.loadTimetable();

    final quests = QuestSystem(
      timetableSystem: timetable,
      restSystem: rest,
    );
    await quests.loadQuests();

    expect(quests.isPenaltyActive, isTrue);
    expect(
      quests.penaltyUntil!.millisecondsSinceEpoch,
      penaltyExpiry.millisecondsSinceEpoch,
    );
    expect(quests.isNightLockActive, isTrue);
    expect(quests.isAppLockActive, isTrue);

    quests.dispose();
    rest.dispose();
    timetable.dispose();
    player.dispose();
  });

  test('cancelled quest timer loses its saved deadline-start eligibility',
      () async {
    SharedPreferences.setMockInitialValues({
      'quest_date': DateTime.now().toIso8601String().substring(0, 10),
      'quest_timer_starts': '{}',
    });

    final player = PlayerSystem();
    await player.loadPlayer();
    final rest = RestSystem(player: player);
    await rest.loadRest();
    final timetable = TimetableSystem();
    await timetable.loadTimetable();
    final quests = QuestSystem(
      timetableSystem: timetable,
      restSystem: rest,
    );
    await quests.loadQuests();

    final startedAt = DateTime.now();
    await quests.registerTimerStart('test_quest', startedAt);
    expect(quests.timerStartedAt('test_quest'), startedAt);

    await quests.clearTimerStart('test_quest');

    expect(quests.timerStartedAt('test_quest'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('quest_timer_starts'), isNull);

    quests.dispose();
    rest.dispose();
    timetable.dispose();
    player.dispose();
  });

  test('expired penalty does not reactivate after loading persisted state',
      () async {
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    SharedPreferences.setMockInitialValues({
      'quest_date': todayKey,
      'completed_quests': ['wakeup'],
      'missed_quests': <String>[],
      'skipped_quests': <String>[],
      'penalty_until':
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      'night_lock_active': false,
      'hp_critical_penalty_applied': true,
    });

    final player = PlayerSystem();
    await player.loadPlayer();
    final rest = RestSystem(player: player);
    await rest.loadRest();
    final timetable = TimetableSystem();
    await timetable.loadTimetable();
    final quests = QuestSystem(
      timetableSystem: timetable,
      restSystem: rest,
    );

    await quests.loadQuests();

    expect(quests.isPenaltyActive, isFalse);
    expect(quests.isNightLockActive, isFalse);
    expect(quests.isAppLockActive, isFalse);

    quests.dispose();
    rest.dispose();
    timetable.dispose();
    player.dispose();
  });
}
