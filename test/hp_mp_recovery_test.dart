import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/player_system.dart';
import '../lib/rest_system.dart';
import '../lib/study_timer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('HP and MP maximums scale with player level', () async {
    final player = PlayerSystem();
    await player.loadPlayer();

    expect(player.maxHp, 100);
    expect(player.maxMp, 100);

    await player.addXp(1000);

    expect(player.level, 2);
    expect(player.maxHp, 110);
    expect(player.maxMp, 110);
  });

  test('vital recovery event is applied only once and survives reload', () async {
    final player = PlayerSystem();
    await player.loadPlayer();

    await player.recoverVitalsOnce(
      'test:short-rest:1',
      hpAmount: 5,
      mpAmount: 5,
    );
    await player.recoverVitalsOnce(
      'test:short-rest:1',
      hpAmount: 5,
      mpAmount: 5,
    );

    expect(player.hp, 100);
    expect(player.mp, 100);

    await player.setHp(80);
    await player.setMp(70);
    await player.recoverVitalsOnce(
      'test:short-rest:2',
      hpAmount: 5,
      mpAmount: 5,
    );

    final reloaded = PlayerSystem();
    await reloaded.loadPlayer();
    await reloaded.recoverVitalsOnce(
      'test:short-rest:2',
      hpAmount: 5,
      mpAmount: 5,
    );

    expect(reloaded.hp, 85);
    expect(reloaded.mp, 75);
  });

  test('MP deduction event is applied only once', () async {
    final player = PlayerSystem();
    await player.loadPlayer();

    await player.deductMpOnce('test:quest:session-1', 15);
    await player.deductMpOnce('test:quest:session-1', 15);

    expect(player.mp, 85);

    final reloaded = PlayerSystem();
    await reloaded.loadPlayer();
    await reloaded.deductMpOnce('test:quest:session-1', 15);

    expect(reloaded.mp, 85);
  });

  test('HP damage event is applied only once and recorded once', () async {
    final player = PlayerSystem();
    await player.loadPlayer();

    final first = await player.applyHpDamageOnce(
      'test:missed-quest:1',
      20,
      reason: 'Test Missed Mission',
    );
    final second = await player.applyHpDamageOnce(
      'test:missed-quest:1',
      20,
      reason: 'Test Missed Mission',
    );

    expect(first, 20);
    expect(second, 0);
    expect(player.hp, 80);
    expect(player.hpDamageHistory, hasLength(1));
  });

  test('short rest grants each elapsed interval once after reload', () async {
    final restStarted = DateTime.now()
        .subtract(const Duration(minutes: 10))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'player_hp': 50,
      'player_mp': 40,
      'short_rest_start': restStarted,
      'short_rest_applied': 0,
    });

    final player = PlayerSystem();
    await player.loadPlayer();
    final rest = RestSystem(player: player);
    await rest.loadRest();

    expect(player.hp, 55);
    expect(player.mp, 45);
    rest.dispose();

    final reloadedPlayer = PlayerSystem();
    await reloadedPlayer.loadPlayer();
    final reloadedRest = RestSystem(player: reloadedPlayer);
    await reloadedRest.loadRest();

    expect(reloadedPlayer.hp, 55);
    expect(reloadedPlayer.mp, 45);
    reloadedRest.dispose();
  });

  test('long rest applies hourly recovery and sleeping bonus once', () async {
    final restStarted = DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'player_hp': 50,
      'player_mp': 40,
      'long_rest_start': restStarted,
    });

    final player = PlayerSystem();
    await player.loadPlayer();
    final rest = RestSystem(player: player);
    await rest.loadRest();
    await rest.endLongRest();

    // 10% of 100 per hour = 10; 25% bonus rounds to 3.
    expect(player.hp, 63);
    expect(player.mp, 53);
    expect(rest.isLongRestActive, isFalse);
    rest.dispose();

    final reloadedPlayer = PlayerSystem();
    await reloadedPlayer.loadPlayer();
    expect(reloadedPlayer.hp, 63);
    expect(reloadedPlayer.mp, 53);
  });

  test('MP is reserved at start and released without deduction on cancel', () async {
    final player = PlayerSystem();
    await player.loadPlayer();
    final timer = StudyTimer();
    await timer.loadTimer(player: player);

    final started = await timer.start(
      questId: 'test_quest',
      durationMinutes: 15,
      player: player,
    );

    expect(started, isTrue);
    expect(timer.reservedMpAmount, 5);
    expect(timer.availableMp(player), 95);
    expect(player.mp, 100);

    await timer.cancel(player: player);

    expect(timer.reservedMpAmount, 0);
    expect(timer.activeQuestId, isNull);
    expect(player.mp, 100);
  });

  test('long study sessions remain one continuous countdown', () async {
    final player = PlayerSystem();
    await player.loadPlayer();

    final timer = StudyTimer();
    await timer.loadTimer(player: player);
    final before = DateTime.now().millisecondsSinceEpoch;

    final started = await timer.start(
      questId: 'long_test_quest',
      durationMinutes: 60,
      player: player,
    );

    expect(started, isTrue);
    expect(timer.formattedTime, '60:00');
    expect(timer.endTime! - before, greaterThanOrEqualTo(60 * 60 * 1000));
    expect(timer.endTime! - before, lessThan(60 * 60 * 1000 + 5000));

    await timer.cancel(player: player);
  });

  test('paused quest timer survives restart and resumes without double reservation', () async {
    final player = PlayerSystem();
    await player.loadPlayer();

    final timer = StudyTimer();
    await timer.loadTimer(player: player);
    final started = await timer.start(
      questId: 'restart_test_quest',
      durationMinutes: 30,
      player: player,
    );

    expect(started, isTrue);
    expect(timer.reservedMpAmount, 10);
    await timer.pause();
    final pausedRemaining = timer.remainingSeconds;

    expect(timer.isRunning, isFalse);
    expect(pausedRemaining, greaterThan(0));

    final restoredTimer = StudyTimer();
    await restoredTimer.loadTimer(player: player);

    expect(restoredTimer.activeQuestId, 'restart_test_quest');
    expect(restoredTimer.isRunning, isFalse);
    expect(restoredTimer.remainingSeconds, pausedRemaining);
    expect(restoredTimer.reservedMpAmount, 10);

    await restoredTimer.resume();

    expect(restoredTimer.isRunning, isTrue);
    expect(restoredTimer.activeQuestId, 'restart_test_quest');
    expect(restoredTimer.reservedMpAmount, 10);
    expect(restoredTimer.availableMp(player), 90);

    await restoredTimer.cancel();
  });

  test('timer cannot reserve more MP than the player has', () async {
    final player = PlayerSystem();
    await player.loadPlayer();
    await player.setMp(4);

    final timer = StudyTimer();
    await timer.loadTimer(player: player);
    final started = await timer.start(
      questId: 'test_quest',
      durationMinutes: 15,
      player: player,
    );

    expect(started, isFalse);
    expect(timer.reservedMpAmount, 0);
    expect(player.mp, 4);
  });

  test('MP cost uses level difficulty and 15-minute blocks', () {
    final timer = StudyTimer();

    expect(timer.getDifficulty(30), 'Easy');
    expect(timer.getDifficulty(31), 'Normal');
    expect(timer.getDifficulty(60), 'Normal');
    expect(timer.getDifficulty(61), 'Hard');

    expect(timer.calculateMpCost(15, playerLevel: 1), 5);
    expect(timer.calculateMpCost(30, playerLevel: 1), 10);
    expect(timer.calculateMpCost(31, playerLevel: 31), 24);
    expect(timer.calculateMpCost(61, playerLevel: 61), 60);
  });
}
