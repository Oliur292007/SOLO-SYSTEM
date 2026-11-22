import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/player_system.dart';
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
