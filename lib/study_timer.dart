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
  static const String _pomodoroEnabledKey = 'quest_pomodoro_enabled';
  static const String _pomodoroPhaseKey = 'quest_pomodoro_phase';
  static const String _pomodoroPhaseRemainingKey = 'quest_pomodoro_phase_remaining';
  static const String _pomodoroPhaseDurationKey = 'quest_pomodoro_phase_duration';
  static const String _pomodoroFocusAtStartKey = 'quest_pomodoro_focus_at_start';
  static const String _pomodoroSessionsKey = 'quest_pomodoro_sessions';
  static const String _pomodoroRecoveryKey = 'quest_pomodoro_recovery_applied';

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
        {'active': isRunning && !isPomodoroBreak},
      );
    } on PlatformException catch (error) {
      debugPrint('APP RESTRICTION SYNC ERROR: ${error.message}');
    } catch (error) {
      debugPrint('APP RESTRICTION SYNC ERROR: $error');
    }
  }

  Timer? _ticker;
  PlayerSystem? _activePlayer;

  bool pomodoroEnabled = false;
  String pomodoroPhase = 'focus';
  int phaseRemainingSeconds = 0;
  int phaseDurationSeconds = 0;
  int focusRemainingAtPhaseStart = 0;
  int completedFocusSessions = 0;
  int recoveryIntervalsApplied = 0;

  bool get isPomodoroBreak => pomodoroEnabled && (pomodoroPhase == 'short_break' || pomodoroPhase == 'long_break');
  String get pomodoroPhaseLabel => !pomodoroEnabled ? '' : pomodoroPhase == 'short_break' ? 'SHORT BREAK' : pomodoroPhase == 'long_break' ? 'LONG BREAK' : 'FOCUS SESSION ' + ((completedFocusSessions % 4) + 1).toString() + '/4';
  int get displayedSeconds => isPomodoroBreak ? phaseRemainingSeconds : remainingSeconds;
  String get focusRemainingFormatted {
    final minutes = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

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

  /// Difficulty is determined by Player Level, not by timer duration.
  String getDifficulty(int playerLevel) {
    if (playerLevel <= 30) return 'Easy';
    if (playerLevel <= 60) return 'Normal';
    return 'Hard';
  }

  /// MP is charged in 15-minute blocks at the player's current level tier.
  int calculateMpCost(int durationMinutes, {int playerLevel = 1}) {
    if (durationMinutes <= 0) return 0;
    final difficulty = getDifficulty(playerLevel);
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
    final display = displayedSeconds;
    final minutes = (display ~/ 60).toString().padLeft(2, '0');
    final seconds = (display % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> loadTimer({PlayerSystem? player}) async {
    _activePlayer = player;
    final prefs = await SharedPreferences.getInstance();

    activeQuestId = prefs.getString(_questIdKey);
    remainingSeconds = prefs.getInt(_remainingKey) ?? 0;
    endTime = prefs.getInt(_endTimeKey);
    isRunning = prefs.getBool(_runningKey) ?? false;
    isFinished = prefs.getBool(_finishedKey) ?? false;

    reservedMp = prefs.getInt(_reservedMpKey) ?? 0;
    pomodoroEnabled = prefs.getBool(_pomodoroEnabledKey) ?? false;
    pomodoroPhase = prefs.getString(_pomodoroPhaseKey) ?? 'focus';
    phaseRemainingSeconds = prefs.getInt(_pomodoroPhaseRemainingKey) ?? 0;
    phaseDurationSeconds = prefs.getInt(_pomodoroPhaseDurationKey) ?? 0;
    focusRemainingAtPhaseStart = prefs.getInt(_pomodoroFocusAtStartKey) ?? remainingSeconds;
    completedFocusSessions = prefs.getInt(_pomodoroSessionsKey) ?? 0;
    recoveryIntervalsApplied = prefs.getInt(_pomodoroRecoveryKey) ?? 0;

    final startedMs = prefs.getInt(_startedAtKey);
    startedAt = startedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startedMs)
        : null;

    if (activeQuestId == null) {
      reservedMp = 0;
      startedAt = null;
      _resetPomodoroState();
      await prefs.remove(_reservedMpKey);
      await prefs.remove(_startedAtKey);
    await prefs.remove(_pomodoroEnabledKey);
    await prefs.remove(_pomodoroPhaseKey);
    await prefs.remove(_pomodoroPhaseRemainingKey);
    await prefs.remove(_pomodoroPhaseDurationKey);
    await prefs.remove(_pomodoroFocusAtStartKey);
    await prefs.remove(_pomodoroSessionsKey);
    await prefs.remove(_pomodoroRecoveryKey);
    }

    if (isRunning && endTime != null && pomodoroEnabled) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      var transitions = 0;
      while (isRunning &&
          endTime != null &&
          endTime! <= nowMs &&
          transitions < 200) {
        phaseRemainingSeconds = 0;
        if (isPomodoroBreak) await _applyPomodoroRecovery(player);
        final completedAt = endTime!;
        await _finishPomodoroPhase(phaseEndAnchorMs: completedAt);
        transitions++;
      }

      if (isRunning && endTime != null) {
        phaseRemainingSeconds = ((endTime! - nowMs) / 1000)
            .ceil()
            .clamp(0, phaseDurationSeconds);
        if (pomodoroPhase == 'focus') {
          remainingSeconds = (focusRemainingAtPhaseStart -
                  (phaseDurationSeconds - phaseRemainingSeconds))
              .clamp(0, focusRemainingAtPhaseStart);
        } else {
          await _applyPomodoroRecovery(player);
        }
        _startTicker();
      }
    } else if (isRunning && endTime != null) {
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

    // Enforce rest/mission exclusivity at the timer layer as well as in the UI.
    if (questSystem != null &&
        (questSystem.restSystem.isShortRestActive ||
            questSystem.restSystem.isLongRestActive)) {
      return false;
    }

    final mpCost = calculateMpCost(
      durationMinutes,
      playerLevel: player.level,
    );
    if (availableMp(player) < mpCost) return false;

    _activePlayer = player;
    activeQuestId = questId;
    reservedMp = mpCost;

    remainingSeconds = durationMinutes * 60;
    pomodoroEnabled = durationMinutes > 30;
    pomodoroPhase = 'focus';
    completedFocusSessions = 0;
    recoveryIntervalsApplied = 0;
    focusRemainingAtPhaseStart = remainingSeconds;
    phaseDurationSeconds = pomodoroEnabled ? (25 * 60).clamp(0, remainingSeconds) : remainingSeconds;
    phaseRemainingSeconds = phaseDurationSeconds;

    final now = DateTime.now();
    startedAt = now;

    endTime = now
        .add(Duration(seconds: pomodoroEnabled ? phaseRemainingSeconds : remainingSeconds))
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

    if (pomodoroEnabled) {
      _updatePomodoroPhaseRemaining();
      if (isPomodoroBreak) await _applyPomodoroRecovery(_activePlayer);
      if (phaseRemainingSeconds <= 0) {
        await _finishPomodoroPhase();
        if (isFinished) {
          _ticker?.cancel();
          _ticker = null;
          notifyListeners();
          return;
        }
        _updatePomodoroPhaseRemaining();
      }
    } else {
      _updateRemaining();
    }
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
    if ((!pomodoroEnabled && remainingSeconds <= 0) || isFinished) return;
    if (pomodoroEnabled && phaseRemainingSeconds <= 0) return;

    endTime = DateTime.now()
        .add(Duration(seconds: pomodoroEnabled ? phaseRemainingSeconds : remainingSeconds))
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

        final sessionKey = startedAt!.millisecondsSinceEpoch;
        hpDamageApplied = await player.applyHpDamageOnce(
          'cancel:${activeQuestId ?? 'unknown'}:$sessionKey',
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
    _resetPomodoroState();

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
    await prefs.remove(_pomodoroEnabledKey);
    await prefs.remove(_pomodoroPhaseKey);
    await prefs.remove(_pomodoroPhaseRemainingKey);
    await prefs.remove(_pomodoroPhaseDurationKey);
    await prefs.remove(_pomodoroFocusAtStartKey);
    await prefs.remove(_pomodoroSessionsKey);
    await prefs.remove(_pomodoroRecoveryKey);

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
        if (pomodoroEnabled) {
          await _tickPomodoro();
          notifyListeners();
          return;
        }
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

  void _updatePomodoroPhaseRemaining() {
    if (endTime == null) return;
    phaseRemainingSeconds = ((endTime! - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(0, phaseDurationSeconds);
    if (pomodoroPhase == 'focus') {
      remainingSeconds = (focusRemainingAtPhaseStart - (phaseDurationSeconds - phaseRemainingSeconds)).clamp(0, focusRemainingAtPhaseStart);
    }
  }

  Future<void> _tickPomodoro() async {
    _updatePomodoroPhaseRemaining();
    if (isPomodoroBreak) await _applyPomodoroRecovery(_activePlayer);
    if (phaseRemainingSeconds <= 0) {
      await _finishPomodoroPhase();
    } else {
      await _saveTimer();
    }
  }

  Future<void> _applyPomodoroRecovery(PlayerSystem? player) async {
    if (player == null || !player.isLoaded || !isPomodoroBreak) return;
    final elapsed = phaseDurationSeconds - phaseRemainingSeconds;
    final interval = pomodoroPhase == 'short_break' ? 150 : 180;
    final maximum = pomodoroPhase == 'short_break' ? 2 : 5;
    final earned = (elapsed ~/ interval).clamp(0, maximum);
    final pending = earned - recoveryIntervalsApplied;
    if (pending <= 0) return;
    final sessionKey = startedAt?.millisecondsSinceEpoch ?? (endTime ?? 0);
    await player.recoverVitalsOnce(
      'pomodoro:$activeQuestId:$sessionKey:$pomodoroPhase:$earned',
      hpAmount: pending,
      mpAmount: pending,
    );
    recoveryIntervalsApplied = earned;
    await _saveTimer();
  }

  Future<void> _finishPomodoroPhase({int? phaseEndAnchorMs}) async {
    if (pomodoroPhase == 'focus') {
      remainingSeconds = (focusRemainingAtPhaseStart - phaseDurationSeconds).clamp(0, focusRemainingAtPhaseStart);
      completedFocusSessions++;
      if (remainingSeconds <= 0) {
        remainingSeconds = 0;
        isRunning = false;
        isFinished = true;
        endTime = null;
        phaseRemainingSeconds = 0;
        await _saveTimer();
        await _syncNativeRestriction();
        return;
      }
      final longBreak = completedFocusSessions % 4 == 0;
      pomodoroPhase = longBreak ? 'long_break' : 'short_break';
      phaseDurationSeconds = longBreak ? 15 * 60 : 5 * 60;
      phaseRemainingSeconds = phaseDurationSeconds;
      recoveryIntervalsApplied = 0;
      focusRemainingAtPhaseStart = remainingSeconds;
    } else {
      pomodoroPhase = 'focus';
      phaseDurationSeconds = (25 * 60).clamp(0, remainingSeconds);
      phaseRemainingSeconds = phaseDurationSeconds;
      focusRemainingAtPhaseStart = remainingSeconds;
      recoveryIntervalsApplied = 0;
    }
    final phaseAnchor = phaseEndAnchorMs ?? DateTime.now().millisecondsSinceEpoch;
    endTime = phaseAnchor + (phaseRemainingSeconds * 1000);
    isRunning = true;
    await _saveTimer();
    await _syncNativeRestriction();
  }

  void _resetPomodoroState() {
    pomodoroEnabled = false;
    pomodoroPhase = 'focus';
    phaseRemainingSeconds = 0;
    phaseDurationSeconds = 0;
    focusRemainingAtPhaseStart = 0;
    completedFocusSessions = 0;
    recoveryIntervalsApplied = 0;
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
      final mpToDeduct = reservedMp;

      if (mpToDeduct <= 0) {
        debugPrint('CLAIM ERROR: Reserved MP is zero');
        return null;
      }

      final sessionKey = startedAt?.millisecondsSinceEpoch ?? (endTime ?? 0);
      final mpEventId = 'quest-mp:$questId:$sessionKey';

      if (questId.startsWith('weekly_special_')) {
        final mission = questSystem.weeklySpecialMission;
        if (mission == null ||
            questId != 'weekly_special_${mission.weekKey}' ||
            mission.durationMinutes <= 0) {
          debugPrint('CLAIM ERROR: Timed special mission not found');
          return null;
        }

        final earnedXp =
            await questSystem.completeWeeklySpecialMission(player);
        if (earnedXp == null && !mission.isCompleted) {
          debugPrint('CLAIM ERROR: Special mission could not be completed');
          return null;
        }

        // If the app was terminated after mission completion but before the
        // MP write, allow the claim to finish. The event ledger prevents a
        // second deduction if the MP write had already succeeded.
        await player.deductMpOnce(mpEventId, mpToDeduct);
        await player.addStudyTime(mission.durationMinutes);
        await _clearSession();
        return earnedXp ?? 0;
      }

      final quest = questSystem.getQuestById(questId);
      if (quest == null || !quest.requiresTimer) {
        debugPrint('CLAIM ERROR: Quest not found or timer not required');
        return null;
      }

      final studyMinutes = quest.durationMinutes;
      final earnedXp = await questSystem.completeQuest(questId, player);

      if (earnedXp == null && !questSystem.isCompleted(questId)) {
        debugPrint('CLAIM ERROR: QuestSystem returned null');
        return null;
      }

      // MP is deducted only after the quest is confirmed complete. This also
      // safely finishes a claim interrupted after quest completion.
      await player.deductMpOnce(mpEventId, mpToDeduct);
      await player.addStudyTime(studyMinutes);
      await _clearSession();
      return earnedXp ?? 0;
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
    _resetPomodoroState();

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
    await prefs.remove(_pomodoroEnabledKey);
    await prefs.remove(_pomodoroPhaseKey);
    await prefs.remove(_pomodoroPhaseRemainingKey);
    await prefs.remove(_pomodoroPhaseDurationKey);
    await prefs.remove(_pomodoroFocusAtStartKey);
    await prefs.remove(_pomodoroSessionsKey);
    await prefs.remove(_pomodoroRecoveryKey);

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
    await prefs.setBool(_pomodoroEnabledKey, pomodoroEnabled);
    await prefs.setString(_pomodoroPhaseKey, pomodoroPhase);
    await prefs.setInt(_pomodoroPhaseRemainingKey, phaseRemainingSeconds);
    await prefs.setInt(_pomodoroPhaseDurationKey, phaseDurationSeconds);
    await prefs.setInt(_pomodoroFocusAtStartKey, focusRemainingAtPhaseStart);
    await prefs.setInt(_pomodoroSessionsKey, completedFocusSessions);
    await prefs.setInt(_pomodoroRecoveryKey, recoveryIntervalsApplied);

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