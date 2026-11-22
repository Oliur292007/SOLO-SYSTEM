import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'player_system.dart';

enum PomodoroPhase { focus, shortBreak, longBreak }

class PomodoroSystem extends ChangeNotifier {
  static const String _focusMinutesKey = 'pomodoro_focus_minutes';
  static const String _shortBreakMinutesKey = 'pomodoro_short_break_minutes';
  static const String _longBreakMinutesKey = 'pomodoro_long_break_minutes';
  static const String _longBreakEveryKey = 'pomodoro_long_break_every';
  static const String _phaseKey = 'pomodoro_phase';
  static const String _remainingKey = 'pomodoro_remaining_seconds';
  static const String _runningKey = 'pomodoro_running';
  static const String _endTimeKey = 'pomodoro_end_time_ms';
  static const String _completedKey = 'pomodoro_completed_focus_sessions';

  final PlayerSystem player;
  final MissionNotificationService notifications;

  PomodoroSystem({required this.player, required this.notifications});

  int focusMinutes = 25;
  int shortBreakMinutes = 5;
  int longBreakMinutes = 15;
  int longBreakEvery = 4;
  int completedFocusSessions = 0;
  PomodoroPhase phase = PomodoroPhase.focus;
  int remainingSeconds = 25 * 60;
  bool isRunning = false;
  bool isLoaded = false;

  int? _endTimeMs;
  int _lastPersistedSecond = -1;
  bool _isFinishing = false;
  Timer? _ticker;

  int get currentPhaseMinutes => _durationFor(phase);

  String get phaseLabel {
    switch (phase) {
      case PomodoroPhase.focus:
        return 'FOCUS SESSION';
      case PomodoroPhase.shortBreak:
        return 'SHORT BREAK';
      case PomodoroPhase.longBreak:
        return 'LONG BREAK';
    }
  }

  String get nextPhaseLabel {
    if (phase == PomodoroPhase.focus) {
      return (completedFocusSessions + 1) % longBreakEvery == 0
          ? 'LONG BREAK'
          : 'SHORT BREAK';
    }
    return 'FOCUS SESSION';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    focusMinutes = (prefs.getInt(_focusMinutesKey) ?? 25).clamp(1, 180);
    shortBreakMinutes = (prefs.getInt(_shortBreakMinutesKey) ?? 5).clamp(1, 60);
    longBreakMinutes = (prefs.getInt(_longBreakMinutesKey) ?? 15).clamp(1, 120);
    longBreakEvery = (prefs.getInt(_longBreakEveryKey) ?? 4).clamp(2, 12);
    completedFocusSessions = prefs.getInt(_completedKey) ?? 0;

    final savedPhase = prefs.getString(_phaseKey);
    phase = PomodoroPhase.values.firstWhere(
      (item) => item.name == savedPhase,
      orElse: () => PomodoroPhase.focus,
    );
    remainingSeconds = (prefs.getInt(_remainingKey) ??
            _durationFor(phase) * 60)
        .clamp(0, 10800);
    isRunning = prefs.getBool(_runningKey) ?? false;
    _endTimeMs = prefs.getInt(_endTimeKey);

    isLoaded = true;
    if (isRunning && _endTimeMs != null) {
      _updateRemaining();
      if (remainingSeconds == 0) {
        await _finishPhase();
      } else {
        _startTicker();
        await _scheduleEndNotification();
      }
    } else {
      isRunning = false;
      _endTimeMs = null;
      if (remainingSeconds == 0) {
        remainingSeconds = _durationFor(phase) * 60;
      }
    }
    await _save();
    notifyListeners();
  }

  int _durationFor(PomodoroPhase value) {
    switch (value) {
      case PomodoroPhase.focus:
        return focusMinutes;
      case PomodoroPhase.shortBreak:
        return shortBreakMinutes;
      case PomodoroPhase.longBreak:
        return longBreakMinutes;
    }
  }

  Future<bool> setDurations({
    required int focus,
    required int shortBreak,
    required int longBreak,
    required int longBreakAfter,
  }) async {
    if (isRunning ||
        focus < 1 || focus > 180 ||
        shortBreak < 1 || shortBreak > 60 ||
        longBreak < 1 || longBreak > 120 ||
        longBreakAfter < 2 || longBreakAfter > 12) {
      return false;
    }
    focusMinutes = focus;
    shortBreakMinutes = shortBreak;
    longBreakMinutes = longBreak;
    longBreakEvery = longBreakAfter;
    remainingSeconds = _durationFor(phase) * 60;
    await _save();
    notifyListeners();
    return true;
  }

  Future<bool> start() async {
    if (!isLoaded || isRunning) return false;
    if (remainingSeconds <= 0) {
      remainingSeconds = _durationFor(phase) * 60;
    }
    _endTimeMs = DateTime.now().millisecondsSinceEpoch +
        remainingSeconds * 1000;
    isRunning = true;
    await _save();
    _startTicker();
    await _scheduleEndNotification();
    notifyListeners();
    return true;
  }

  Future<void> pause() async {
    if (!isRunning) return;
    _updateRemaining();
    _ticker?.cancel();
    _ticker = null;
    isRunning = false;
    _endTimeMs = null;
    await notifications.cancelPomodoroEnd();
    await _save();
    notifyListeners();
  }

  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    isRunning = false;
    _endTimeMs = null;
    await notifications.cancelPomodoroEnd();
    phase = PomodoroPhase.focus;
    remainingSeconds = focusMinutes * 60;
    await _save();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
      notifyListeners();
      if (remainingSeconds == 0) {
        unawaited(_finishPhase());
      } else if (remainingSeconds % 10 == 0 &&
          remainingSeconds != _lastPersistedSecond) {
        _lastPersistedSecond = remainingSeconds;
        unawaited(_save());
      }
    });
  }

  void _updateRemaining() {
    final end = _endTimeMs;
    if (end == null) return;
    final difference = end - DateTime.now().millisecondsSinceEpoch;
    remainingSeconds = difference <= 0 ? 0 : (difference / 1000).ceil();
  }

  Future<void> _finishPhase() async {
    if (_isFinishing || !isRunning) return;
    _isFinishing = true;
    _ticker?.cancel();
    _ticker = null;
    isRunning = false;
    _endTimeMs = null;
    await notifications.cancelPomodoroEnd();

    final finishedPhase = phase;
    if (finishedPhase == PomodoroPhase.focus) {
      completedFocusSessions++;
      phase = completedFocusSessions % longBreakEvery == 0
          ? PomodoroPhase.longBreak
          : PomodoroPhase.shortBreak;
      remainingSeconds = _durationFor(phase) * 60;
    } else {
      phase = PomodoroPhase.focus;
      remainingSeconds = focusMinutes * 60;
    }

    // Persist the phase transition before awarding study time to prevent
    // an expired focus timer from awarding the same session after restart.
    await _save();
    if (finishedPhase == PomodoroPhase.focus) {
      await player.addStudyTime(focusMinutes);
      await notifications.addNotification(
        'POMODORO FOCUS COMPLETED',
        'Focus session complete. ${phaseLabel.toLowerCase()} is ready.',
        type: 'pomodoro',
      );
    } else {
      await notifications.addNotification(
        'POMODORO BREAK COMPLETED',
        'Break complete. Your next focus session is ready.',
        type: 'pomodoro',
      );
    }

    _isFinishing = false;
    notifyListeners();
  }

  Future<void> _scheduleEndNotification() async {
    final end = _endTimeMs;
    if (!isRunning || end == null) return;
    final isFocus = phase == PomodoroPhase.focus;
    await notifications.schedulePomodoroEnd(
      endTime: DateTime.fromMillisecondsSinceEpoch(end),
      title: isFocus ? 'POMODORO FOCUS COMPLETED' : 'POMODORO BREAK COMPLETED',
      body: isFocus
          ? 'Your focus session is complete. Take your scheduled break.'
          : 'Your break is complete. Return to your focus session.',
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_focusMinutesKey, focusMinutes);
    await prefs.setInt(_shortBreakMinutesKey, shortBreakMinutes);
    await prefs.setInt(_longBreakMinutesKey, longBreakMinutes);
    await prefs.setInt(_longBreakEveryKey, longBreakEvery);
    await prefs.setInt(_completedKey, completedFocusSessions);
    await prefs.setString(_phaseKey, phase.name);
    await prefs.setInt(_remainingKey, remainingSeconds);
    await prefs.setBool(_runningKey, isRunning);
    if (_endTimeMs == null) {
      await prefs.remove(_endTimeKey);
    } else {
      await prefs.setInt(_endTimeKey, _endTimeMs!);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
