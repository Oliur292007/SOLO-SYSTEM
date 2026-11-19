
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_system.dart';

class RestSystem extends ChangeNotifier {
  // STORAGE KEYS
  static const String _shortRestStartKey = 'short_rest_start';
  static const String _shortRestAppliedKey = 'short_rest_applied';
  static const String _longRestStartKey = 'long_rest_start';

  // SHORT REST SETTINGS
  static const int recoveryIntervalMinutes = 10;
  static const int hpRecoveryPerInterval = 5;
  static const int mpRecoveryPerInterval = 5;

  // LONG REST SETTINGS
  static const double hourlyRecoveryRate = 0.10;
  static const double sleepingBonusRate = 0.25;

  final PlayerSystem player;

  RestSystem({required this.player});

  Timer? _timer;

  DateTime? _shortRestStart;
  DateTime? _longRestStart;

  int _appliedIntervals = 0;

  bool isLoaded = false;

  // REST STATUS

  bool get isShortRestActive => _shortRestStart != null;

  bool get isLongRestActive => _longRestStart != null;

  // SHORT REST ELAPSED TIME

  int get elapsedShortRestMinutes {
    if (_shortRestStart == null) return 0;

    return DateTime.now()
        .difference(_shortRestStart!)
        .inMinutes;
  }

  int get nextRecoveryMinutes {
    if (_shortRestStart == null) {
      return recoveryIntervalMinutes;
    }

    final remainder =
        elapsedShortRestMinutes % recoveryIntervalMinutes;

    return remainder == 0
        ? recoveryIntervalMinutes
        : recoveryIntervalMinutes - remainder;
  }

  Duration get shortRestTimeToNextRecovery {
    if (_shortRestStart == null) return Duration.zero;

    final elapsed = DateTime.now().difference(_shortRestStart!);
    final interval = Duration(minutes: recoveryIntervalMinutes);

    final elapsedSeconds = elapsed.inSeconds;
    final intervalSeconds = interval.inSeconds;

    final remainingSeconds =
        intervalSeconds - (elapsedSeconds % intervalSeconds);

    return Duration(seconds: remainingSeconds);
  }

  int get remainingLongRestMinutes {
    if (_longRestStart == null) return 0;

    final remaining = _longRestDeadline.difference(DateTime.now());

    return remaining.isNegative ? 0 : remaining.inMinutes;
  }

  // LONG REST ELAPSED TIME

  int get elapsedLongRestMinutes {
    if (_longRestStart == null) return 0;

    final end = _longRestDeadline;

    final now = DateTime.now().isAfter(end)
        ? end
        : DateTime.now();

    return now.difference(_longRestStart!).inMinutes;
  }

  // WAKEUP DEADLINE: NEXT DAY 8:30 AM

  DateTime get _longRestDeadline {
    final start = _longRestStart!;

    return DateTime(
      start.year,
      start.month,
      start.day + 1,
      8,
      30,
    );
  }

  // LOAD REST DATA

  Future<void> loadRest() async {
    if (!player.isLoaded) {
      throw StateError('PlayerSystem must be loaded first.');
    }

    final prefs = await SharedPreferences.getInstance();

    final shortTimestamp = prefs.getInt(_shortRestStartKey);

    _appliedIntervals =
        prefs.getInt(_shortRestAppliedKey) ?? 0;

    final longTimestamp = prefs.getInt(_longRestStartKey);

    if (shortTimestamp != null) {
      _shortRestStart =
          DateTime.fromMillisecondsSinceEpoch(shortTimestamp);

      await _processShortRestRecovery();
    }

    if (longTimestamp != null) {
      _longRestStart =
          DateTime.fromMillisecondsSinceEpoch(longTimestamp);

      if (DateTime.now().isAfter(_longRestDeadline) ||
          DateTime.now().isAtSameMomentAs(_longRestDeadline)) {
        await endLongRest(
          endedAt: _longRestDeadline,
        );
      }
    }

    isLoaded = true;

    if (isShortRestActive || isLongRestActive) {
      _startTicker();
    }

    notifyListeners();
  }

  // START SHORT REST

  Future<bool> startShortRest() async {
    if (!isLoaded ||
        isShortRestActive ||
        isLongRestActive) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();

    _shortRestStart = DateTime.now();
    _appliedIntervals = 0;

    await prefs.setInt(
      _shortRestStartKey,
      _shortRestStart!.millisecondsSinceEpoch,
    );

    await prefs.setInt(_shortRestAppliedKey, 0);

    _startTicker();

    notifyListeners();

    return true;
  }

  // STOP SHORT REST

  Future<void> stopShortRest() async {
    if (!isShortRestActive) return;

    await _processShortRestRecovery();

    _shortRestStart = null;
    _appliedIntervals = 0;

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_shortRestStartKey);
    await prefs.remove(_shortRestAppliedKey);

    _stopTickerIfIdle();

    notifyListeners();
  }

  // START LONG REST
  // Call this after successful Sleeping Mission completion.

  Future<bool> startLongRest() async {
    if (!isLoaded ||
        isShortRestActive ||
        isLongRestActive) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();

    _longRestStart = DateTime.now();

    await prefs.setInt(
      _longRestStartKey,
      _longRestStart!.millisecondsSinceEpoch,
    );

    _startTicker();

    notifyListeners();

    return true;
  }

  // END LONG REST
  // Call this after Wakeup completion.
  // If Wakeup is missed, it ends automatically at 8:30 AM.

  Future<void> endLongRest({DateTime? endedAt}) async {
    if (!isLongRestActive) return;

    final start = _longRestStart!;

    DateTime end = endedAt ?? DateTime.now();

    final deadline = _longRestDeadline;

    if (end.isAfter(deadline)) {
      end = deadline;
    }

    if (end.isBefore(start)) {
      end = start;
    }

    final durationMinutes =
        end.difference(start).inMinutes;

    // BASE RECOVERY: 10% PER HOUR

    final baseHpRecovery =
        (player.maxHp *
                hourlyRecoveryRate *
                durationMinutes /
                60)
            .floor();

    final baseMpRecovery =
        (player.maxMp *
                hourlyRecoveryRate *
                durationMinutes /
                60)
            .floor();

    // SLEEPING BONUS: EXTRA 25%

    final hpBonus =
        (baseHpRecovery * sleepingBonusRate).round();

    final mpBonus =
        (baseMpRecovery * sleepingBonusRate).round();

    final totalHpRecovery =
        baseHpRecovery + hpBonus;

    final totalMpRecovery =
        baseMpRecovery + mpBonus;

    // CLEAR ACTIVE REST BEFORE APPLYING RECOVERY

    _longRestStart = null;

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_longRestStartKey);

    await player.recoverHp(totalHpRecovery);
    await player.recoverMp(totalMpRecovery);

    _stopTickerIfIdle();

    notifyListeners();
  }

  // START / MAINTAIN TIMER

  void _startTicker() {
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) async {
        if (isShortRestActive) {
          await _processShortRestRecovery();
        }

        if (isLongRestActive) {
          if (DateTime.now().isAfter(_longRestDeadline) ||
              DateTime.now().isAtSameMomentAs(_longRestDeadline)) {
            await endLongRest(
              endedAt: _longRestDeadline,
            );
          }
        }

        notifyListeners();
      },
    );
  }

  // PROCESS SHORT REST RECOVERY

  Future<void> _processShortRestRecovery() async {
    if (_shortRestStart == null) return;

    final elapsed =
        DateTime.now().difference(_shortRestStart!);

    final completedIntervals =
        elapsed.inMinutes ~/ recoveryIntervalMinutes;

    if (completedIntervals <= _appliedIntervals) return;

    final newIntervals =
        completedIntervals - _appliedIntervals;

    final hpRecovery =
        newIntervals * hpRecoveryPerInterval;

    final mpRecovery =
        newIntervals * mpRecoveryPerInterval;

    _appliedIntervals = completedIntervals;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(
      _shortRestAppliedKey,
      _appliedIntervals,
    );

    await player.recoverHp(hpRecovery);
    await player.recoverMp(mpRecovery);
  }

  // STOP TIMER IF NO REST IS ACTIVE

  void _stopTickerIfIdle() {
    if (isShortRestActive || isLongRestActive) return;

    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
