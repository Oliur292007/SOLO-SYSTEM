import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_system.dart';
import 'timetable_system.dart';
import 'rest_system.dart';

class StudyQuest {
  final String id;
  final String name;
  final String subject;
  final int durationMinutes;
  final bool requiresTimer;
  final bool isOptional;
  final DateTime? deadline;
  final DateTime? availableFrom;

  const StudyQuest({
    required this.id,
    required this.name,
    required this.subject,
    required this.durationMinutes,
    this.requiresTimer = true,
    this.isOptional = false,
    this.deadline,
    this.availableFrom,
  });

  int get xpReward {
    if (isOptional || durationMinutes <= 0) return 0;
    return (durationMinutes / 15).ceil() * 25;
  }

  bool get isOverdue {
    if (deadline == null) return false;
    return DateTime.now().isAfter(deadline!);
  }

  bool get isAvailable {
    final now = DateTime.now();
    if (availableFrom != null && now.isBefore(availableFrom!)) {
      return false;
    }
    return true;
  }
}

enum QuestState {
  upcoming,
  available,
  active,
  completed,
  skipped,
  missed,
  locked,
}

class QuestSystem extends ChangeNotifier {
  static const String _dateKey = 'quest_date';
  static const String _completedKey = 'completed_quests';
  static const String _missedKey = 'missed_quests';
  static const String _skippedKey = 'skipped_quests';
  static const String _snapshotKey = 'quest_snapshot';
  static const String _penaltyKey = 'penalty_until';
  static const String _nightLockKey = 'night_lock_active';
  static const String _timerStartsKey = 'quest_timer_starts';

  static const Duration penaltyDuration = Duration(hours: 4);
  static const Duration hpCriticalPenalty = Duration(hours: 2);

  static const String _scheduleIdPrefix = 'schedule_';

  final TimetableSystem timetableSystem;
  final RestSystem restSystem;

  QuestSystem({
    required this.timetableSystem,
    required this.restSystem,
  }) {
    timetableSystem.addListener(_onTimetableChanged);
    restSystem.player.addListener(_onPlayerChanged);
  }

  final Set<String> completedQuestIds = {};
  final Set<String> missedQuestIds = {};
  final Set<String> skippedQuestIds = {};

  final Map<String, int> _timerStarts = {};

  bool isLoaded = false;
  bool isNightLockActive = false;

  DateTime? penaltyUntil;

  Timer? _deadlineTimer;
  Timer? _penaltyTicker;

  bool _hpCriticalPenaltyApplied = false;

  String _loadedDateKey = '';

  bool _isCheckingDeadlines = false;
  bool _isSavingSnapshot = false;

  // ============================================================
  // DATE
  // ============================================================

  String get todayKey {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  DateTime _dateAt(int hour, int minute) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  // ============================================================
  // QUEST LIST
  // ============================================================

  List<StudyQuest> get quests {
    final List<StudyQuest> result = [];

    final wakeupStart = _dateAt(5, 0);
    final wakeupDeadline = _dateAt(8, 30);

    result.add(
      StudyQuest(
        id: 'wakeup',
        name: 'Wakeup',
        subject: 'Daily Routine',
        durationMinutes: 0,
        requiresTimer: false,
        deadline: wakeupDeadline,
        availableFrom: wakeupStart,
      ),
    );

    final now = DateTime.now();

    for (final schedule in timetableSystem.getSchedulesForDay(now.weekday)) {
      final timeParts = schedule.startTime.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final start = DateTime(now.year, now.month, now.day, hour, minute);
      final deadline = start.add(Duration(minutes: schedule.durationMinutes));

      result.add(
        StudyQuest(
          id: '$_scheduleIdPrefix${schedule.id}',
          name: schedule.subject,
          subject: schedule.subject,
          durationMinutes: schedule.durationMinutes,
          requiresTimer: true,
          isOptional: schedule.isOptional,
          deadline: deadline,
          availableFrom: start,
        ),
      );
    }

    result.add(
      StudyQuest(
        id: 'sleeping',
        name: 'Sleeping',
        subject: 'Daily Routine',
        durationMinutes: 0,
        requiresTimer: false,
        deadline: _dateAt(23, 58),
        availableFrom: _dateAt(20, 0),
      ),
    );

    return result;
  }

  // ============================================================
  // PROGRESS
  // ============================================================

  int get totalQuests => quests.length;
  int get totalCount => totalQuests;
  int get completedCount => completedQuestIds.length;
  int get remainingCount => totalQuests - completedCount;

  double get progress {
    if (totalQuests == 0) return 0;
    return (completedCount / totalQuests).clamp(0.0, 1.0).toDouble();
  }

  bool isCompleted(String questId) => completedQuestIds.contains(questId);
  bool isMissed(String questId) => missedQuestIds.contains(questId);
  bool isSkipped(String questId) => skippedQuestIds.contains(questId);

  StudyQuest? getQuestById(String questId) {
    for (final quest in quests) {
      if (quest.id == questId) return quest;
    }
    return null;
  }

  String? scheduleIdFromQuestId(String questId) {
    if (!questId.startsWith(_scheduleIdPrefix)) return null;
    return questId.substring(_scheduleIdPrefix.length);
  }

  // ============================================================
  // TIMER DEADLINE VALIDATION
  // ============================================================

  DateTime? timerStartedAt(String questId) {
    final ms = _timerStarts[questId];
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool wasTimerStartedBeforeDeadline(String questId) {
    final quest = getQuestById(questId);
    if (quest == null || quest.deadline == null) return false;

    final startedAt = timerStartedAt(questId);
    if (startedAt == null) return false;

    return !startedAt.isAfter(quest.deadline!);
  }

  Future<void> registerTimerStart(String questId, DateTime startedAt) async {
    _timerStarts[questId] = startedAt.millisecondsSinceEpoch;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_timerStartsKey, jsonEncode(_timerStarts));
  }

  ({bool allowed, String? reason}) canStartTimer(String questId) {
    if (!isLoaded) {
      return (allowed: false, reason: 'System not loaded yet.');
    }

    final quest = getQuestById(questId);
    if (quest == null) {
      return (allowed: false, reason: 'Quest not found.');
    }

    if (isCompleted(questId)) {
      return (allowed: false, reason: 'Already completed.');
    }

    if (restSystem.player.isCriticalHp) {
      return (
        allowed: false,
        reason: 'HP CRITICAL — Rest required to continue.',
      );
    }

    final now = DateTime.now();

    // Flexible Schedule Timer: scheduled study missions may begin early.
    // Fixed missions (Wakeup/Sleeping) keep their configured availability windows.
    if (scheduleIdFromQuestId(questId) == null &&
        quest.availableFrom != null &&
        now.isBefore(quest.availableFrom!)) {
      return (allowed: false, reason: 'Mission not available yet.');
    }

    if (quest.deadline != null && now.isAfter(quest.deadline!)) {
      return (allowed: false, reason: 'Deadline has passed.');
    }

    return (allowed: true, reason: null);
  }

  // ============================================================
  // QUEST STATE
  // ============================================================

  QuestState getQuestState(String questId) {
    final quest = getQuestById(questId);
    if (quest == null) return QuestState.locked;

    if (isCompleted(questId)) return QuestState.completed;
    if (isSkipped(questId)) return QuestState.skipped;
    if (isMissed(questId)) return QuestState.missed;

    final now = DateTime.now();

    if (quest.deadline != null && now.isAfter(quest.deadline!)) {
      return quest.isOptional ? QuestState.skipped : QuestState.missed;
    }

    if (quest.availableFrom != null &&
        now.isBefore(quest.availableFrom!) &&
        scheduleIdFromQuestId(questId) == null) {
      return QuestState.upcoming;
    }

    return QuestState.available;
  }

  // ============================================================
  // LOCK STATUS
  // ============================================================

  bool get isPenaltyActive {
    if (penaltyUntil == null) return false;
    return DateTime.now().isBefore(penaltyUntil!);
  }

  bool get isAppLockActive => isPenaltyActive || isNightLockActive;

  String get lockStatus {
    if (isPenaltyActive) return 'PENALTY ACTIVE';
    if (isNightLockActive) return 'NIGHT LOCK ACTIVE';
    return 'UNLOCKED';
  }

  Duration get penaltyRemaining {
    if (!isPenaltyActive || penaltyUntil == null) return Duration.zero;
    final remaining = penaltyUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ============================================================
  // HP DAMAGE — LEVEL SCALED (with cap)
  // ============================================================

  /// Base percentages (of maxHp) — before level multiplier.
  static const double _mandatoryMissPercent = 15.0;
  static const double _wakeupMissPercent = 18.0;
  static const double _sleepingMissPercent = 15.0;
  static const double _cancelDamagePercent = 8.0;

  /// Hard cap per miss (fraction of maxHp).
  static const double _damageCapFraction = 0.40;

  Future<void> _applyMissDamage(
    PlayerSystem player,
    double basePercent,
    String reason,
  ) async {
    if (player.hp <= 0) return;

    final levelMultiplier = 1.0 + ((player.level - 1) * 0.05);
    final rawDamage = player.maxHp * (basePercent / 100.0) * levelMultiplier;
    final cappedDamage = rawDamage.clamp(
      0.0,
      player.maxHp * _damageCapFraction,
    );
    final damage = cappedDamage.round();

    await player.applyHpDamage(damage, reason: reason);
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> loadQuests() async {
    if (!restSystem.isLoaded) {
      throw StateError('RestSystem must be loaded before QuestSystem.');
    }

    final prefs = await SharedPreferences.getInstance();

    final savedDate = prefs.getString(_dateKey);
    final savedCompleted = prefs.getStringList(_completedKey);
    final savedMissed = prefs.getStringList(_missedKey);
    final savedSkipped = prefs.getStringList(_skippedKey);

    completedQuestIds
      ..clear()
      ..addAll(savedCompleted ?? []);
    missedQuestIds
      ..clear()
      ..addAll(savedMissed ?? []);
    skippedQuestIds
      ..clear()
      ..addAll(savedSkipped ?? []);

    _timerStarts.clear();
    final timerStartsRaw = prefs.getString(_timerStartsKey);
    if (timerStartsRaw != null && timerStartsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(timerStartsRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          _timerStarts[key] = (value as num).toInt();
        });
      } catch (_) {
        _timerStarts.clear();
      }
    }

    final savedPenalty = prefs.getInt(_penaltyKey);
    if (savedPenalty != null) {
      penaltyUntil = DateTime.fromMillisecondsSinceEpoch(savedPenalty);
    }

    isNightLockActive = prefs.getBool(_nightLockKey) ?? false;

    final snapshotData = prefs.getString(_snapshotKey);

    if (savedDate == null || savedDate.isEmpty) {
      _loadedDateKey = todayKey;

      completedQuestIds.clear();
      missedQuestIds.clear();
      skippedQuestIds.clear();
      _timerStarts.clear();

      final now = DateTime.now();
      if (now.isAfter(_dateAt(8, 30))) {
        completedQuestIds.add('wakeup');
      }

      await _saveCompleted();
      await _saveMissed();
      await _saveSkipped();
      await _saveTimerStarts();
      await _saveDate();
      await _saveQuestSnapshot();
    } else if (savedDate != todayKey) {
      _loadedDateKey = savedDate;

      await _evaluatePreviousDay(snapshotData);

      completedQuestIds.clear();
      missedQuestIds.clear();
      skippedQuestIds.clear();
      _timerStarts.clear();

      _loadedDateKey = todayKey;

      await _saveCompleted();
      await _saveMissed();
      await _saveSkipped();
      await _saveTimerStarts();
      await _saveDate();
      await _saveQuestSnapshot();
    } else {
      _loadedDateKey = todayKey;
      if (snapshotData == null || snapshotData.isEmpty) {
        await _saveQuestSnapshot();
      }
    }

    isLoaded = true;

    await _cleanupOrphanQuestIds();
    await _checkDeadlines();
    _startDeadlineChecker();
    _syncPenaltyTicker();
    notifyListeners();
  }

  Future<void> _cleanupOrphanQuestIds() async {
    final validScheduleIds =
        timetableSystem.allSchedules.map((s) => s.id).toSet();

    bool changed = false;

    void cleanup(Set<String> set) {
      final toRemove = <String>[];
      for (final questId in set) {
        final scheduleId = scheduleIdFromQuestId(questId);
        if (scheduleId == null) continue;
        if (!validScheduleIds.contains(scheduleId)) {
          toRemove.add(questId);
        }
      }
      if (toRemove.isNotEmpty) {
        for (final id in toRemove) {
          set.remove(id);
          _timerStarts.remove(id);
        }
        changed = true;
      }
    }

    cleanup(completedQuestIds);
    cleanup(missedQuestIds);
    cleanup(skippedQuestIds);

    if (changed) {
      await _saveCompleted();
      await _saveMissed();
      await _saveSkipped();
      await _saveTimerStarts();
    }
  }

  // ============================================================
  // COMPLETE MISSIONS
  // ============================================================

  Future<int?> completeFixedMission(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;
    if (questId != 'wakeup' && questId != 'sleeping') return null;

    final quest = getQuestById(questId);
    if (quest == null) return null;
    if (isCompleted(questId)) return null;
    if (isMissed(questId) || isSkipped(questId)) return null;
    if (!quest.isAvailable) return null;

    // Fixed daily missions must be completed within their configured window.
    // Sleeping: 8:00 PM–11:58 PM. Wakeup: 5:00 AM–8:30 AM.
    final now = DateTime.now();
    if (quest.deadline != null && now.isAfter(quest.deadline!)) {
      debugPrint('FIXED MISSION BLOCKED: deadline passed for $questId.');
      return null;
    }

    if (player.isCriticalHp) return null;

    return _completeMission(quest, player);
  }

  Future<int?> completeQuest(
    String questId,
    PlayerSystem player,
  ) async {
    if (!isLoaded) return null;

    final quest = getQuestById(questId);
    if (quest == null) return null;
    if (!quest.requiresTimer) return null;
    if (isCompleted(questId)) return null;
    if (isMissed(questId)) return null;
    if (isSkipped(questId)) return null;
    if (player.isCriticalHp) return null;

    // A schedule timer can be started and completed before its timetable slot.
    // Fixed daily missions remain restricted to their configured windows.
    if (scheduleIdFromQuestId(questId) == null &&
        quest.availableFrom != null &&
        DateTime.now().isBefore(quest.availableFrom!)) {
      return null;
    }

    if (quest.deadline != null &&
        DateTime.now().isAfter(quest.deadline!) &&
        !wasTimerStartedBeforeDeadline(questId)) {
      debugPrint('CLAIM BLOCKED: deadline passed and timer not started in time.');
      return null;
    }

    return _completeMission(quest, player);
  }

  Future<int?> _completeMission(
    StudyQuest quest,
    PlayerSystem player,
  ) async {
    if (isCompleted(quest.id)) return null;
    if (isSkipped(quest.id)) return null;

    if (quest.id == 'sleeping') {
      final started = await restSystem.startLongRest();
      if (!started) return null;
    }

    if (quest.id == 'wakeup') {
      await restSystem.endLongRest();
    }

    completedQuestIds.add(quest.id);
    missedQuestIds.remove(quest.id);
    skippedQuestIds.remove(quest.id);

    await _saveCompleted();
    await _saveMissed();
    await _saveSkipped();

    final scheduleId = scheduleIdFromQuestId(quest.id);
    if (scheduleId != null) {
      await timetableSystem.markCompleted(scheduleId, dateKey: todayKey);
    }

    if (quest.id == 'sleeping') {
      isNightLockActive = true;
      await _saveNightLock();
    }

    if (quest.id == 'wakeup') {
      isNightLockActive = false;
      await _saveNightLock();
    }

    final earnedXp = quest.xpReward;
    if (earnedXp > 0) {
      await player.addXp(earnedXp);
    }

    _syncPenaltyTicker();
    notifyListeners();
    return earnedXp;
  }

  // ============================================================
  // DEADLINE CHECKER
  // ============================================================

  void _startDeadlineChecker() {
    _deadlineTimer?.cancel();
    _deadlineTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        if (!isLoaded) return;
        await _checkDeadlines();
      },
    );
  }

  Future<void> _checkDeadlines() async {
    if (_isCheckingDeadlines || !isLoaded) return;
    _isCheckingDeadlines = true;

    try {
      await _checkDateRollover();

      final now = DateTime.now();
      final player = restSystem.player;

      for (final quest in quests) {
        if (isCompleted(quest.id)) continue;
        if (isMissed(quest.id)) continue;
        if (isSkipped(quest.id)) continue;
        if (quest.deadline == null) continue;

        if (!now.isAfter(quest.deadline!)) continue;

        if (quest.requiresTimer && wasTimerStartedBeforeDeadline(quest.id)) {
          continue;
        }

        // Optional → skipped (no penalty, no HP loss).
        if (quest.isOptional) {
          skippedQuestIds.add(quest.id);
          await _saveSkipped();
          continue;
        }

        // Sleeping miss: Night Lock + HP damage, no penalty timer.
        if (quest.id == 'sleeping') {
          isNightLockActive = true;
          missedQuestIds.add(quest.id);
          await _saveNightLock();
          await _saveMissed();

          await _applyMissDamage(
            player,
            _sleepingMissPercent,
            'Sleeping Missed',
          );

          _maybeApplyHpCriticalPenalty(player);
          continue;
        }

        // Wakeup miss: end long rest, clear night lock, HP damage + penalty.
        if (quest.id == 'wakeup') {
          await restSystem.endLongRest(endedAt: quest.deadline!);
          isNightLockActive = false;
          await _saveNightLock();
          await _startPenalty(quest.deadline!);
          missedQuestIds.add(quest.id);
          await _saveMissed();

          await _applyMissDamage(
            player,
            _wakeupMissPercent,
            'Wakeup Missed',
          );

          _maybeApplyHpCriticalPenalty(player);
          continue;
        }

        // Other mandatory timer missions.
        await _startPenalty(quest.deadline!);
        missedQuestIds.add(quest.id);
        await _saveMissed();

        await _applyMissDamage(
          player,
          _mandatoryMissPercent,
          'Mission Missed: ${quest.name}',
        );

        _maybeApplyHpCriticalPenalty(player);
      }

      await _savePenalty();
      _syncPenaltyTicker();
      notifyListeners();
    } finally {
      _isCheckingDeadlines = false;
    }
  }

  // ============================================================
  // DATE ROLLOVER
  // ============================================================

  Future<void> _checkDateRollover() async {
    if (_loadedDateKey == todayKey) return;

    final prefs = await SharedPreferences.getInstance();
    final snapshotData = prefs.getString(_snapshotKey);

    await _evaluatePreviousDay(snapshotData);

    completedQuestIds.clear();
    missedQuestIds.clear();
    skippedQuestIds.clear();
    _timerStarts.clear();

    _loadedDateKey = todayKey;

    await _saveCompleted();
    await _saveMissed();
    await _saveSkipped();
    await _saveTimerStarts();
    await _saveDate();
    await _saveQuestSnapshot();
  }

  // ============================================================
  // PREVIOUS DAY EVALUATION
  // ============================================================

  Future<void> _evaluatePreviousDay(String? snapshotData) async {
    if (snapshotData == null || snapshotData.isEmpty) return;

    final player = restSystem.player;

    try {
      final List<dynamic> decoded = jsonDecode(snapshotData);
      final List<Map<String, dynamic>> previousQuests =
          decoded.map((item) => Map<String, dynamic>.from(item)).toList();

      previousQuests.sort((a, b) {
        final aDeadline = a['deadline'] as int;
        final bDeadline = b['deadline'] as int;
        return aDeadline.compareTo(bDeadline);
      });

      for (final item in previousQuests) {
        final id = item['id'] as String;
        final itemDateKey = item['dateKey'] as String?;
        if (itemDateKey != null && itemDateKey == todayKey) continue;

        final deadline =
            DateTime.fromMillisecondsSinceEpoch(item['deadline'] as int);
        final isOptional = item['optional'] as bool? ?? false;

        if (completedQuestIds.contains(id)) continue;
        if (isOptional) continue;

        // A timer started before the deadline may finish late on the same day,
        // but an unfinished quest must still be marked missed after date rollover.
        // Do not let a stale timer-start flag exempt it from previous-day penalties.

        if (id == 'sleeping') {
          isNightLockActive = true;
          await _saveNightLock();
          await _applyMissDamage(
            player,
            _sleepingMissPercent,
            'Sleeping Missed (previous day)',
          );
          _maybeApplyHpCriticalPenalty(player);
          continue;
        }

        if (id == 'wakeup') {
          isNightLockActive = false;
          await _saveNightLock();
          await _startPenalty(deadline);
          await _applyMissDamage(
            player,
            _wakeupMissPercent,
            'Wakeup Missed (previous day)',
          );
          _maybeApplyHpCriticalPenalty(player);
          continue;
        }

        await _startPenalty(deadline);
        await _applyMissDamage(
          player,
          _mandatoryMissPercent,
          'Mission Missed (previous day)',
        );
        _maybeApplyHpCriticalPenalty(player);
      }
    } catch (_) {
      // Ignore corrupted snapshot.
    }

    await _savePenalty();
  }

  // ============================================================
  // PENALTY
  // ============================================================

  Future<void> _startPenalty(DateTime missedDeadline) async {
    final newPenaltyEnd = missedDeadline.add(penaltyDuration);

    if (!DateTime.now().isBefore(newPenaltyEnd)) return;
    if (penaltyUntil != null && penaltyUntil!.isAfter(newPenaltyEnd)) return;

    penaltyUntil = newPenaltyEnd;
    await _savePenalty();
    _syncPenaltyTicker();
  }

  void _maybeApplyHpCriticalPenalty(PlayerSystem player) {
    if (player.isCriticalHp && !_hpCriticalPenaltyApplied) {
      _hpCriticalPenaltyApplied = true;
      final newEnd = DateTime.now().add(hpCriticalPenalty);
      if (penaltyUntil == null || penaltyUntil!.isBefore(newEnd)) {
        penaltyUntil = newEnd;
        _savePenalty();
        _syncPenaltyTicker();
      }
    }
    // Reset flag if HP restored.
    if (!player.isCriticalHp) {
      _hpCriticalPenaltyApplied = false;
    }
  }

  // ============================================================
  // PENALTY TICKER (1-second countdown)
  // ============================================================

  void _syncPenaltyTicker() {
    final shouldRun = isPenaltyActive || isNightLockActive;
    if (shouldRun && (_penaltyTicker == null || !_penaltyTicker!.isActive)) {
      _startPenaltyTicker();
    } else if (!shouldRun) {
      _stopPenaltyTicker();
    }
  }

  void _startPenaltyTicker() {
    _penaltyTicker?.cancel();
    _penaltyTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!isPenaltyActive && !isNightLockActive) {
          _stopPenaltyTicker();
          return;
        }
        // If penalty just expired, save cleared state.
        if (penaltyUntil != null && !isPenaltyActive) {
          penaltyUntil = null;
          _savePenalty();
        }
        notifyListeners();
      },
    );
  }

  void _stopPenaltyTicker() {
    _penaltyTicker?.cancel();
    _penaltyTicker = null;
  }

  // ============================================================
  // SNAPSHOT
  // ============================================================

  Future<void> _saveQuestSnapshot() async {
    if (_isSavingSnapshot) return;
    _isSavingSnapshot = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, Map<String, dynamic>> snapshot = {};
      final today = todayKey;

      for (final quest in quests) {
        if (quest.deadline == null) continue;
        if (isCompleted(quest.id)) continue;

        snapshot[quest.id] = {
          'id': quest.id,
          'deadline': quest.deadline!.millisecondsSinceEpoch,
          'optional': quest.isOptional,
          'timerStarted': wasTimerStartedBeforeDeadline(quest.id),
          'dateKey': today,
        };
      }

      await prefs.setString(
        _snapshotKey,
        jsonEncode(snapshot.values.toList()),
      );
    } finally {
      _isSavingSnapshot = false;
    }
  }

  // ============================================================
  // TIMETABLE CHANGE
  // ============================================================

  void _onTimetableChanged() {
    if (!isLoaded) return;
    _handleTimetableChange();
  }

  Future<void> _handleTimetableChange() async {
    await _cleanupOrphanQuestIds();
    await _saveQuestSnapshot();
    await _checkDeadlines();
    notifyListeners();
  }

  void _onPlayerChanged() {
    // HP restored → clear HP-critical flag & ticker sync.
    if (!restSystem.player.isCriticalHp && _hpCriticalPenaltyApplied) {
      _hpCriticalPenaltyApplied = false;
    }
  }

  // ============================================================
  // PERSISTENCE
  // ============================================================

  Future<void> _saveCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedKey, completedQuestIds.toList());
  }

  Future<void> _saveMissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_missedKey, missedQuestIds.toList());
  }

  Future<void> _saveSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_skippedKey, skippedQuestIds.toList());
  }

  Future<void> _saveTimerStarts() async {
    final prefs = await SharedPreferences.getInstance();
    if (_timerStarts.isEmpty) {
      await prefs.remove(_timerStartsKey);
    } else {
      await prefs.setString(_timerStartsKey, jsonEncode(_timerStarts));
    }
  }

  Future<void> _saveDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dateKey, _loadedDateKey);
  }

  Future<void> _savePenalty() async {
    final prefs = await SharedPreferences.getInstance();
    if (penaltyUntil != null) {
      await prefs.setInt(
        _penaltyKey,
        penaltyUntil!.millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_penaltyKey);
    }
  }

  Future<void> _saveNightLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nightLockKey, isNightLockActive);
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    _penaltyTicker?.cancel();
    timetableSystem.removeListener(_onTimetableChanged);
    restSystem.player.removeListener(_onPlayerChanged);
    super.dispose();
  }
}