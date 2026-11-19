
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_system.dart';
import 'quest_system.dart';

class StudyTimer extends ChangeNotifier {
  static const String _questIdKey = 'timer_quest_id';
  static const String _endTimeKey = 'timer_end_time';
  static const String _remainingKey = 'timer_remaining';
  static const String _runningKey = 'timer_running';
  static const String _finishedKey = 'timer_finished';

  // MP RESERVATION KEY
  static const String _reservedMpKey = 'timer_reserved_mp';

  Timer? _ticker;

  String? activeQuestId;
  int remainingSeconds = 0;
  int? endTime;

  bool isRunning = false;
  bool isLoaded = false;
  bool isFinished = false;

  bool _isClaiming = false;

  // RESERVED MP
  int reservedMp = 0;

  int get reservedMpAmount => reservedMp;

  int availableMp(PlayerSystem player) {
    return (player.mp - reservedMp).clamp(0, player.maxMp);
  }

  // AUTOMATIC MISSION DIFFICULTY

  String getDifficulty(int durationMinutes) {
    if (durationMinutes <= 30) return 'Easy';
    if (durationMinutes <= 60) return 'Normal';
    return 'Hard';
  }

  // MP COST CALCULATION

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
    final minutes = (remainingSeconds ~/ 60)
        .toString()
        .padLeft(2, '0');

    final seconds = (remainingSeconds % 60)
        .toString()
        .padLeft(2, '0');

    return '$minutes:$seconds';
  }

  // LOAD SAVED TIMER AND MP RESERVATION

  Future<void> loadTimer() async {
    final prefs = await SharedPreferences.getInstance();

    activeQuestId = prefs.getString(_questIdKey);
    remainingSeconds = prefs.getInt(_remainingKey) ?? 0;
    endTime = prefs.getInt(_endTimeKey);
    isRunning = prefs.getBool(_runningKey) ?? false;
    isFinished = prefs.getBool(_finishedKey) ?? false;

    reservedMp = prefs.getInt(_reservedMpKey) ?? 0;

    // No active mission means no reservation.
    if (activeQuestId == null) {
      reservedMp = 0;
      await prefs.remove(_reservedMpKey);
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
    notifyListeners();
  }

  // START TIMER + RESERVE MP

  Future<bool> start({
    required String questId,
    required int durationMinutes,
    required PlayerSystem player,
  }) async {
    if (!isLoaded || !player.isLoaded) return false;

    if (isRunning || activeQuestId != null) return false;

    if (durationMinutes <= 0) return false;

    final mpCost = calculateMpCost(durationMinutes);

    // CHECK AVAILABLE MP
    if (availableMp(player) < mpCost) {
      return false;
    }

    // RESERVE MP WITHOUT DEDUCTING IT
    activeQuestId = questId;
    reservedMp = mpCost;

    remainingSeconds = durationMinutes * 60;

    endTime = DateTime.now()
        .add(Duration(seconds: remainingSeconds))
        .millisecondsSinceEpoch;

    isRunning = true;
    isFinished = false;

    await _saveTimer();

    _startTicker();
    notifyListeners();

    return true;
  }

  // PAUSE TIMER

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

    // MP RESERVATION REMAINS ACTIVE.
    await _saveTimer();

    notifyListeners();
  }

  // RESUME TIMER

  Future<void> resume() async {
    if (!isLoaded) return;

    if (isRunning || activeQuestId == null) return;

    if (remainingSeconds <= 0 || isFinished) return;

    endTime = DateTime.now()
        .add(Duration(seconds: remainingSeconds))
        .millisecondsSinceEpoch;

    isRunning = true;

    // EXISTING MP RESERVATION IS PRESERVED.
    await _saveTimer();

    _startTicker();
    notifyListeners();
  }

  // CANCEL TIMER + RELEASE MP

  Future<void> cancel() async {
    _ticker?.cancel();
    _ticker = null;

    activeQuestId = null;
    remainingSeconds = 0;
    endTime = null;

    isRunning = false;
    isFinished = false;
    _isClaiming = false;

    // RELEASE RESERVED MP WITHOUT DEDUCTION.
    reservedMp = 0;

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_questIdKey);
    await prefs.remove(_endTimeKey);
    await prefs.remove(_remainingKey);
    await prefs.remove(_runningKey);
    await prefs.remove(_finishedKey);
    await prefs.remove(_reservedMpKey);

    notifyListeners();
  }

  // TIMER TICKER

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
        }

        notifyListeners();
      },
    );
  }

  // UPDATE REMAINING TIME

  void _updateRemaining() {
    if (endTime == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final difference = endTime! - now;

    remainingSeconds = (difference / 1000).ceil();

    if (remainingSeconds < 0) {
      remainingSeconds = 0;
    }
  }

  // COMPLETE MISSION + DEDUCT RESERVED MP

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

    if (quest == null || !quest.requiresTimer) {
      debugPrint('CLAIM ERROR: Quest not found or timer not required');
      return null;
    }

    if (mpToDeduct <= 0) {
      debugPrint('CLAIM ERROR: Reserved MP is zero');
      return null;
    }

    if (earnedXp == null) {
      debugPrint('CLAIM ERROR: QuestSystem returned null');
      return null;
    }

    _isClaiming = true;

    try {
      final quest = questSystem.getQuestById(activeQuestId!);

      if (quest == null || !quest.requiresTimer) {
        return null;
      }

      final studyMinutes = quest.durationMinutes;
      final mpToDeduct = reservedMp;

      if (mpToDeduct <= 0) {
        return null;
      }

      // COMPLETE QUEST FIRST.
      final earnedXp = await questSystem.completeQuest(
        activeQuestId!,
        player,
      );

      if (earnedXp == null) {
        return null;
      }

      // DEDUCT RESERVED MP ONLY AFTER SUCCESS.
      await player.setMp(player.mp - mpToDeduct);

      // RECORD SUCCESSFUL STUDY TIME.
      await player.addStudyTime(studyMinutes);

      // CLEAR TIMER AND RELEASE RESERVATION.
      await cancel();

      return earnedXp;
    } finally {
      _isClaiming = false;
    }
  }

  // SAVE TIMER + RESERVATION

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
