import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HpDamageEvent {
  final String reason;
  final int damage;
  final DateTime timestamp;

  const HpDamageEvent({
    required this.reason,
    required this.damage,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'reason': reason,
        'damage': damage,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory HpDamageEvent.fromJson(Map<String, dynamic> json) {
    return HpDamageEvent(
      reason: json['reason'] as String,
      damage: json['damage'] as int,
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }
}

class PlayerSystem extends ChangeNotifier {
  // PLAYER DATA KEYS
  static const String _nameKey = 'player_name';
  static const String _levelKey = 'player_level';
  static const String _xpKey = 'player_xp';
  static const String _totalXpKey = 'player_total_xp';

  // STUDY TIME KEYS
  static const String _totalStudyKey = 'total_study_minutes';
  static const String _todayStudyKey = 'today_study_minutes';
  static const String _studyDateKey = 'study_date';

  // ATTRIBUTE KEYS
  static const String _hpKey = 'player_hp';
  static const String _mpKey = 'player_mp';
  static const String _strengthKey = 'player_strength';
  static const String _intellectKey = 'player_intellect';

  // HP DAMAGE HISTORY
  static const String _hpDamageHistoryKey = 'hp_damage_history';
  static const int _maxHistoryEntries = 20;

  String playerName = 'Shadow Hunter';

  int level = 1;
  int xp = 0;
  int totalXp = 0;

  int totalStudyMinutes = 0;
  int todayStudyMinutes = 0;

  // PLAYER ATTRIBUTES
  int hp = 100;
  int mp = 100;

  int strength = 0;
  int intellect = 0;

  /// Recent HP damage events (newest last).
  final List<HpDamageEvent> hpDamageHistory = [];

  String _studyDate = '';

  bool isLoaded = false;

  // ============================================================
  // CAPACITY GETTERS
  // ============================================================

  int get maxHp => 100 + ((level - 1) * 10);
  int get maxMp => 100 + ((level - 1) * 10);

  double get hpProgress => (hp / maxHp).clamp(0.0, 1.0).toDouble();
  double get mpProgress => (mp / maxMp).clamp(0.0, 1.0).toDouble();

  double get strengthProgress =>
      (strength / 100).clamp(0.0, 1.0).toDouble();
  double get intellectProgress =>
      (intellect / 100).clamp(0.0, 1.0).toDouble();

  // ============================================================
  // HP CRITICAL STATE
  // ============================================================

  /// True when HP is depleted — player cannot start quests.
  bool get isCriticalHp => hp <= 0;

  /// HP percentage threshold for warning UI.
  bool get isLowHp => hpProgress < 0.25 && hp > 0;

  // ============================================================
  // XP SYSTEM
  // ============================================================

  int get xpRequired => 1000 + ((level - 1) * 600);
  double get xpProgress => (xp / xpRequired).clamp(0.0, 1.0).toDouble();

  // ============================================================
  // RANK & TITLE
  // ============================================================

  String get rank {
    if (level <= 5) return 'E-Rank';
    if (level <= 10) return 'D-Rank';
    if (level <= 20) return 'C-Rank';
    if (level <= 35) return 'B-Rank';
    if (level <= 50) return 'A-Rank';
    if (level <= 75) return 'S-Rank';
    return 'National Level';
  }

  String get title {
    if (level <= 5) return 'The Awakener';
    if (level <= 10) return 'Rookie Hunter';
    if (level <= 20) return 'Rising Hunter';
    if (level <= 35) return 'Elite Hunter';
    if (level <= 50) return 'Master Hunter';
    if (level <= 75) return 'Shadow Monarch';
    return 'Monarch of Shadows';
  }

  // ============================================================
  // DATE HELPERS
  // ============================================================

  String get _currentDateKey {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int get currentTodayStudyMinutes {
    if (_studyDate != _currentDateKey) return 0;
    return todayStudyMinutes;
  }

  // ============================================================
  // STUDY TIME FORMATTING
  // ============================================================

  String _formatStudyTime(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${remainingMinutes.toString().padLeft(2, '0')}';
  }

  String get todayStudyTimeFormatted =>
      _formatStudyTime(currentTodayStudyMinutes);
  String get totalStudyTimeFormatted => _formatStudyTime(totalStudyMinutes);

  // ============================================================
  // LOAD PLAYER DATA
  // ============================================================

  Future<void> loadPlayer() async {
    final prefs = await SharedPreferences.getInstance();

    playerName = prefs.getString(_nameKey) ?? 'Shadow Hunter';

    level = prefs.getInt(_levelKey) ?? 1;
    xp = prefs.getInt(_xpKey) ?? 0;
    totalXp = prefs.getInt(_totalXpKey) ?? 0;

    totalStudyMinutes = prefs.getInt(_totalStudyKey) ?? 0;
    todayStudyMinutes = prefs.getInt(_todayStudyKey) ?? 0;

    _studyDate = prefs.getString(_studyDateKey) ?? '';

    hp = prefs.getInt(_hpKey) ?? 100;
    mp = prefs.getInt(_mpKey) ?? 100;
    strength = prefs.getInt(_strengthKey) ?? 0;
    intellect = prefs.getInt(_intellectKey) ?? 0;

    // Load damage history
    hpDamageHistory.clear();
    final historyRaw = prefs.getStringList(_hpDamageHistoryKey);
    if (historyRaw != null) {
      try {
        for (final entry in historyRaw) {
          // Store as simple string "reason|damage|timestamp"
          final parts = entry.split('|');
          if (parts.length != 3) continue;
          hpDamageHistory.add(
            HpDamageEvent(
              reason: parts[0],
              damage: int.parse(parts[1]),
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                int.parse(parts[2]),
              ),
            ),
          );
        }
      } catch (_) {
        hpDamageHistory.clear();
      }
    }

    // Clamp
    hp = hp.clamp(0, maxHp);
    mp = mp.clamp(0, maxMp);

    // Daily study reset
    final currentKey = _currentDateKey;
    if (_studyDate != currentKey) {
      _studyDate = currentKey;
      todayStudyMinutes = 0;
    }

    await _saveAll();

    isLoaded = true;
    notifyListeners();
  }

  // ============================================================
  // CHANGE PLAYER NAME
  // ============================================================

  Future<void> setPlayerName(String name) async {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) return;

    playerName = cleanedName;
    await _saveAll();
    notifyListeners();
  }

  // ============================================================
  // STUDY TIME
  // ============================================================

  Future<void> addStudyTime(int minutes) async {
    if (minutes <= 0) return;

    final currentKey = _currentDateKey;
    if (_studyDate != currentKey) {
      _studyDate = currentKey;
      todayStudyMinutes = 0;
    }

    todayStudyMinutes += minutes;
    totalStudyMinutes += minutes;

    await _saveStudyTime();
    notifyListeners();
  }

  Future<void> resetDailyStudy() async {
    _studyDate = _currentDateKey;
    todayStudyMinutes = 0;
    await _saveStudyTime();
    notifyListeners();
  }

  // ============================================================
  // XP & LEVEL
  // ============================================================

  Future<bool> addXp(int amount) async {
    if (amount <= 0) return false;

    xp += amount;
    totalXp += amount;

    bool leveledUp = false;

    while (xp >= xpRequired) {
      xp -= xpRequired;
      level++;
      leveledUp = true;
    }

    hp = hp.clamp(0, maxHp);
    mp = mp.clamp(0, maxMp);

    await _saveAll();
    notifyListeners();
    return leveledUp;
  }

  // ============================================================
  // HP / MP — BASIC
  // ============================================================

  Future<void> setHp(int value) async {
    hp = value.clamp(0, maxHp);
    await _saveAttributes();
    notifyListeners();
  }

  Future<void> setMp(int value) async {
    mp = value.clamp(0, maxMp);
    await _saveAttributes();
    notifyListeners();
  }

  Future<void> recoverHp(int amount) async {
    if (amount <= 0) return;
    hp = (hp + amount).clamp(0, maxHp);
    await _saveAttributes();
    notifyListeners();
  }

  Future<void> recoverMp(int amount) async {
    if (amount <= 0) return;
    mp = (mp + amount).clamp(0, maxMp);
    await _saveAttributes();
    notifyListeners();
  }

  // ============================================================
  // HP DAMAGE — NEW
  // ============================================================

  /// Applies HP damage (already-calculated integer amount).
  /// Returns the actual damage dealt (clamped to current HP).
  /// Logs to history for future stats UI.
  Future<int> applyHpDamage(
    int damage, {
    String? reason,
  }) async {
    if (damage <= 0) return 0;
    if (hp <= 0) return 0; // already critical

    final actualDamage = damage.clamp(0, hp);
    hp = (hp - damage).clamp(0, maxHp);

    // Log event
    hpDamageHistory.add(
      HpDamageEvent(
        reason: reason ?? 'Unknown',
        damage: actualDamage,
        timestamp: DateTime.now(),
      ),
    );
    if (hpDamageHistory.length > _maxHistoryEntries) {
      hpDamageHistory.removeRange(
        0,
        hpDamageHistory.length - _maxHistoryEntries,
      );
    }

    await _saveAttributes();
    await _saveHpDamageHistory();
    notifyListeners();

    return actualDamage;
  }

  /// Clears damage history (future UI action).
  Future<void> clearHpDamageHistory() async {
    hpDamageHistory.clear();
    await _saveHpDamageHistory();
    notifyListeners();
  }

  // ============================================================
  // ATTRIBUTES
  // ============================================================

  Future<void> addStrength(int amount) async {
    if (amount <= 0) return;
    strength += amount;
    await _saveAttributes();
    notifyListeners();
  }

  Future<void> addIntellect(int amount) async {
    if (amount <= 0) return;
    intellect += amount;
    await _saveAttributes();
    notifyListeners();
  }

  // ============================================================
  // PERSISTENCE
  // ============================================================

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_nameKey, playerName);
    await prefs.setInt(_levelKey, level);
    await prefs.setInt(_xpKey, xp);
    await prefs.setInt(_totalXpKey, totalXp);

    await prefs.setInt(_totalStudyKey, totalStudyMinutes);
    await prefs.setInt(_todayStudyKey, todayStudyMinutes);
    await prefs.setString(_studyDateKey, _studyDate);

    await prefs.setInt(_hpKey, hp);
    await prefs.setInt(_mpKey, mp);
    await prefs.setInt(_strengthKey, strength);
    await prefs.setInt(_intellectKey, intellect);
  }

  Future<void> _saveStudyTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_totalStudyKey, totalStudyMinutes);
    await prefs.setInt(_todayStudyKey, todayStudyMinutes);
    await prefs.setString(_studyDateKey, _studyDate);
  }

  Future<void> _saveAttributes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hpKey, hp);
    await prefs.setInt(_mpKey, mp);
    await prefs.setInt(_strengthKey, strength);
    await prefs.setInt(_intellectKey, intellect);
  }

  Future<void> _saveHpDamageHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = hpDamageHistory
        .map((e) => '${e.reason}|${e.damage}|${e.timestamp.millisecondsSinceEpoch}')
        .toList();
    await prefs.setStringList(_hpDamageHistoryKey, encoded);
  }
}