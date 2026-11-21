import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'player_system.dart';
import 'quest_system.dart';

class StudyTimer extends ChangeNotifier {
  static const String _questIdKey = 'timer_quest_id';
  static const String _endTimeKey = 'timer_end_time';
  static const String _remainingKey = 'timer_remaining';
  static const String _runningKey = 'timer_running';
  static const String _finishedKey = 'timer_finished';
  static const String _reservedMpKey = 'timer_reserved_mp';
  static const String _startedAtKey = 'timer_started_at';

  /// Cancel damage applies only if elapsed session ≥ this threshold.
  static const Duration _cancelDamageThreshold = Duration(minutes: 5);

  /// Cancel damage base percent (of maxHp, before level multiplier).
  static const double _cancelDamagePercent = 8.0;

  /// Hard cap per cancel (fraction of maxHp).
  static const double _cancelDamageCapFraction = 0.40;

  static const MethodChannel _restrictionChannel =
      MethodChannel('solo_system/app_restriction');

  Future<void> _syncNativeRestriction() async {
    try {
      await _restrictionChannel.invokeMethod<void>(
        'setStudyRestriction',
        {'active': isRunning},
      );
    } on PlatformException catch (error) {
      debugPrint('APP RESTRICTION SYNC ERROR: ${error.message}');
    } catch (error) {
      debugPrint('APP RESTRICTION SYNC ERROR: $error');
    }
  }

  Timer? _ticker;

  String? activeQuestId;
  int remainingSeconds = 0;
  int? endTime;

  DateTime? startedAt;

  bool isRunning = false;
  bool isLoaded = false;
  bool isFinished = false;

  bool _isClaiming = false;

  int reservedMp = 0;

  int get reservedMpAmount => reservedMp;
  DateTime? get startedAtTime => startedAt;

  int availableMp(PlayerSystem player) {
    return (player.mp - reservedMp).clamp(0, player.maxMp);
  }

  // ============================================================
  // DIFFICULTY & MP COST
  // ============================================================

  String getDifficulty(int durationMinutes) {
    if (durationMinutes <= 30) return 'Easy';
    if (durationMinutes <= 60) return 'Normal';
    return 'Hard';
  }

  int calculateMpCost(int durationMinutes) {
    if (durationMinutes <= 0) return 0;
    final difficulty = getDifficulty(durationMinutes);
    int rate;
    switch (difficulty) {
      case 'Easy':
        rate = 5;
        break;
      case 'Normal':
        rate = 8;
        break;
      default:
        rate = 12;
    }
    return ((durationMinutes + 14) ~/ 15) * rate;
  }

  String get formattedTime {
    final minutes = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> loadTimer() async {
    final prefs = await SharedPreferences.getInstance();

    activeQuestId = prefs.getString(_questIdKey);
    remainingSeconds = prefs.getInt(_remainingKey) ?? 0;
    endTime = prefs.getInt(_endTimeKey);
    isRunning = prefs.getBool(_runningKey) ?? false;
    isFinished = prefs.getBool(_finishedKey) ?? false;

    reservedMp = prefs.getInt(_reservedMpKey) ?? 0;

    final startedMs = prefs.getInt(_startedAtKey);
    startedAt = startedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startedMs)
        : null;

    if (activeQuestId == null) {
      reservedMp = 0;
      startedAt = null;
      await prefs.remove(_reservedMpKey);
      await prefs.remove(_startedAtKey);
    }

    if (isRunning && endTime != null) {
      _updateRemaining();
      if (remainingSeconds <= 0) {
        remainingSeconds = 0;
        isRunning = false;
        isFinished = true;
        endTime = null;
        await _saveTimer();
      } else {
        _startTicker();
      }
    } else if (isRunning && endTime == null) {
      isRunning = false;
      await _saveTimer();
    }

    isLoaded = true;
    await _syncNativeRestriction();
    notifyListeners();
  }

  // ============================================================
  // START
  // ============================================================

  Future<bool> start({
    required String questId,
    required int durationMinutes,
    required PlayerSystem player,
    QuestSystem? questSystem,
  }) async {
    if (!isLoaded || !player.isLoaded) return false;
    if (isRunning || activeQuestId != null) return false;
    if (durationMinutes <= 0) return false;
    if (player.isCriticalHp) return false;

    final mpCost = calculateMpCost(durationMinutes);
    if (availableMp(player) < mpCost) return false;

    activeQuestId = questId;
    reservedMp = mpCost;

    remainingSeconds = durationMinutes * 60;

    final now = DateTime.now();
    startedAt = now;

    endTime = now
        .add(Duration(seconds: remainingSeconds))
        .millisecondsSinceEpoch;

    isRunning = true;
    isFinished = false;

    await _saveTimer();
    await _syncNativeRestriction();

    if (questSystem != null) {
      await questSystem.registerTimerStart(questId, now);
    }

    _startTicker();
    notifyListeners();
    return true;
  }

  // ============================================================
  // PAUSE
  // ============================================================

  Future<void> pause() async {
    if (!isRunning) return;

    _updateRemaining();
    _ticker?.cancel();
    _ticker = null;

    isRunning = false;
    endTime = null;

    if (remainingSeconds <= 0) {
      remainingSeconds = 0;
      isFinished = true;
    }

    await _saveTimer();
    await _syncNativeRestriction();
    notifyListeners();
  }

  // ============================================================
  // RESUME
  // ============================================================

  Future<void> resume() async {
    if (!isLoaded) return;
    if (isRunning || activeQuestId == null) return;
    if (remainingSeconds <= 0 || isFinished) return;

    endTime = DateTime.now()
        .add(Duration(seconds: remainingSeconds))
        .millisecondsSinceEpoch;

    isRunning = true;

    await _saveTimer();
    await _syncNativeRestriction();
    _startTicker();
    notifyListeners();
  }

  // ============================================================
  // CANCEL (with HP damage)
  // ============================================================

  /// Cancels the timer. Applies HP damage if the session ran long enough.
  /// Returns the HP damage applied (0 if no damage).
  Future<int> cancel({PlayerSystem? player}) async {
    // Calculate cancel damage BEFORE clearing state.
    int hpDamageApplied = 0;

    if (player != null &&
        player.isLoaded &&
        startedAt != null &&
        !isFinished) {
      // Use total time since start (includes paused time) — session was wasted effort.
      final elapsed = DateTime.now().difference(startedAt!);

      if (elapsed >= _cancelDamageThreshold) {
        final levelMultiplier = 1.0 + ((player.level - 1) * 0.05);
        final rawDamage =
            player.maxHp * (_cancelDamagePercent / 100.0) * levelMultiplier;
        final cappedDamage = rawDamage.clamp(
          0.0,
          player.maxHp * _cancelDamageCapFraction,
        );
        final damage = cappedDamage.round();

        hpDamageApplied = await player.applyHpDamage(
          damage,
          reason: 'Session Cancelled',
        );
      }
    }

    _ticker?.cancel();
    _ticker = null;

    activeQuestId = null;
    remainingSeconds = 0;
    endTime = null;
    startedAt = null;

    isRunning = false;
    isFinished = false;
    _isClaiming = false;

    reservedMp = 0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_questIdKey);
    await prefs.remove(_endTimeKey);
    await prefs.remove(_remainingKey);
    await prefs.remove(_runningKey);
    await prefs.remove(_finishedKey);
    await prefs.remove(_reservedMpKey);
    await prefs.remove(_startedAtKey);

    await _syncNativeRestriction();
    notifyListeners();
    return hpDamageApplied;
  }

  // ============================================================
  // TICKER
  // ============================================================

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) async {
        if (!isRunning) return;
        _updateRemaining();

        if (remainingSeconds <= 0) {
          remainingSeconds = 0;
          isRunning = false;
          isFinished = true;
          endTime = null;
          _ticker?.cancel();
          _ticker = null;
          await _saveTimer();
          await _syncNativeRestriction();
        }

        notifyListeners();
      },
    );
  }

  void _updateRemaining() {
    if (endTime == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final difference = endTime! - now;
    remainingSeconds = (difference / 1000).ceil();
    if (remainingSeconds < 0) remainingSeconds = 0;
  }

  // ============================================================
  // COMPLETE QUEST
  // ============================================================

  Future<int?> completeQuest(
    QuestSystem questSystem,
    PlayerSystem player,
  ) async {
    if (!isLoaded || !isFinished) {
      debugPrint('CLAIM ERROR: Timer not finished or not loaded');
      return null;
    }

    if (activeQuestId == null || _isClaiming) {
      debugPrint('CLAIM ERROR: No active quest or already claiming');
      return null;
    }

    _isClaiming = true;

    try {
      final questId = activeQuestId!;
      final quest = questSystem.getQuestById(questId);

      if (quest == null || !quest.requiresTimer) {
        debugPrint('CLAIM ERROR: Quest not found or timer not required');
        return null;
      }

      final studyMinutes = quest.durationMinutes;
      final mpToDeduct = reservedMp;

      if (mpToDeduct <= 0) {
        debugPrint('CLAIM ERROR: Reserved MP is zero');
        return null;
      }

      final earnedXp = await questSystem.completeQuest(questId, player);

      if (earnedXp == null) {
        debugPrint('CLAIM ERROR: QuestSystem returned null');
        return null;
      }

      await player.setMp(player.mp - mpToDeduct);
      await player.addStudyTime(studyMinutes);

      // Clear WITHOUT applying cancel damage (successful claim).
      await _clearSession();

      return earnedXp;
    } catch (error, stackTrace) {
      debugPrint('CLAIM EXCEPTION: $error');
      debugPrint('$stackTrace');
      return null;
    } finally {
      _isClaiming = false;
    }
  }

  /// Internal session clear — no cancel damage (used after claim).
  Future<void> _clearSession() async {
    _ticker?.cancel();
    _ticker = null;

    activeQuestId = null;
    remainingSeconds = 0;
    endTime = null;
    startedAt = null;

    isRunning = false;
    isFinished = false;
    _isClaiming = false;

    reservedMp = 0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_questIdKey);
    await prefs.remove(_endTimeKey);
    await prefs.remove(_remainingKey);
    await prefs.remove(_runningKey);
    await prefs.remove(_finishedKey);
    await prefs.remove(_reservedMpKey);
    await prefs.remove(_startedAtKey);

    await _syncNativeRestriction();
    notifyListeners();
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _saveTimer() async {
    final prefs = await SharedPreferences.getInstance();

    if (activeQuestId != null) {
      await prefs.setString(_questIdKey, activeQuestId!);
    } else {
      await prefs.remove(_questIdKey);
    }

    await prefs.setInt(_remainingKey, remainingSeconds);
    await prefs.setBool(_runningKey, isRunning);
    await prefs.setBool(_finishedKey, isFinished);
    await prefs.setInt(_reservedMpKey, reservedMp);

    if (startedAt != null) {
      await prefs.setInt(_startedAtKey, startedAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_startedAtKey);
    }

    if (endTime != null) {
      await prefs.setInt(_endTimeKey, endTime!);
    } else {
      await prefs.remove(_endTimeKey);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}