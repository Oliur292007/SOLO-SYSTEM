
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

  Timer? _ticker;

  String? activeQuestId;
  int remainingSeconds = 0;
  int? endTime;

  bool isRunning = false;
  bool isLoaded = false;
  bool isFinished = false;

  bool _isClaiming = false;

  String get formattedTime {
    final minutes = (remainingSeconds ~/ 60)
        .toString()
        .padLeft(2, '0');

    final seconds = (remainingSeconds % 60)
        .toString()
        .padLeft(2, '0');

    return '$minutes:$seconds';
  }

  // LOAD SAVED TIMER

  Future<void> loadTimer() async {
    final prefs = await SharedPreferences.getInstance();

    activeQuestId = prefs.getString(_questIdKey);
    remainingSeconds = prefs.getInt(_remainingKey) ?? 0;
    endTime = prefs.getInt(_endTimeKey);
    isRunning = prefs.getBool(_runningKey) ?? false;
    isFinished = prefs.getBool(_finishedKey) ?? false;

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

  // START TIMER

  Future<bool> start({
    required String questId,
    required int durationMinutes,
  }) async {
    if (!isLoaded) return false;
    if (isRunning || activeQuestId != null) return false;
    if (durationMinutes <= 0) return false;

    activeQuestId = questId;
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

    await _saveTimer();

    _startTicker();
    notifyListeners();
  }

  // CANCEL TIMER

  Future<void> cancel() async {
    _ticker?.cancel();
    _ticker = null;

    activeQuestId = null;
    remainingSeconds = 0;
    endTime = null;

    isRunning = false;
    isFinished = false;
    _isClaiming = false;

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_questIdKey);
    await prefs.remove(_endTimeKey);
    await prefs.remove(_remainingKey);
    await prefs.remove(_runningKey);
    await prefs.remove(_finishedKey);

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

  // COMPLETE MISSION + RECORD STUDY TIME

  Future<int?> completeQuest(
    QuestSystem questSystem,
    PlayerSystem player,
  ) async {
    if (!isLoaded || !isFinished) return null;
    if (activeQuestId == null || _isClaiming) return null;

    _isClaiming = true;

    try {
      final quest = questSystem.getQuestById(activeQuestId!);

      if (quest == null || !quest.requiresTimer) {
        return null;
      }

      final studyMinutes = quest.durationMinutes;

      final earnedXp = await questSystem.completeQuest(
        activeQuestId!,
        player,
      );

      if (earnedXp == null) {
        return null;
      }

      // Record only successfully completed sessions.
      // Optional missions also count their study time.

      await player.addStudyTime(studyMinutes);

      await cancel();

      return earnedXp;
    } finally {
      _isClaiming = false;
    }
  }

  // SAVE TIMER

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
