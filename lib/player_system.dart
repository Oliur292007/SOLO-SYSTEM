
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String _studyDate = '';

  bool isLoaded = false;

  // MAXIMUM HP AND MP

  int get maxHp => 100 + ((level - 1) * 10);

  int get maxMp => 100 + ((level - 1) * 10);

  double get hpProgress =>
      (hp / maxHp).clamp(0.0, 1.0).toDouble();

  double get mpProgress =>
      (mp / maxMp).clamp(0.0, 1.0).toDouble();

  // ATTRIBUTE PERCENTAGES

  double get strengthProgress =>
      (strength / 100).clamp(0.0, 1.0).toDouble();

  double get intellectProgress =>
      (intellect / 100).clamp(0.0, 1.0).toDouble();

  // XP SYSTEM

  int get xpRequired => 1000 + ((level - 1) * 600);

  double get xpProgress =>
      (xp / xpRequired).clamp(0.0, 1.0).toDouble();

  // RANK SYSTEM

  String get rank {
    if (level <= 5) return 'E-Rank';
    if (level <= 10) return 'D-Rank';
    if (level <= 20) return 'C-Rank';
    if (level <= 35) return 'B-Rank';
    if (level <= 50) return 'A-Rank';
    if (level <= 75) return 'S-Rank';
    return 'National Level';
  }

  // TITLE SYSTEM

  String get title {
    if (level <= 5) return 'The Awakener';
    if (level <= 10) return 'Rookie Hunter';
    if (level <= 20) return 'Rising Hunter';
    if (level <= 35) return 'Elite Hunter';
    if (level <= 50) return 'Master Hunter';
    if (level <= 75) return 'Shadow Monarch';
    return 'Monarch of Shadows';
  }

  // CURRENT DATE

  String get _currentDateKey {
    final now = DateTime.now();

    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int get currentTodayStudyMinutes {
    if (_studyDate != _currentDateKey) {
      return 0;
    }

    return todayStudyMinutes;
  }

  // STUDY TIME FORMATTING

  String _formatStudyTime(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${remainingMinutes.toString().padLeft(2, '0')}';
  }

  String get todayStudyTimeFormatted =>
      _formatStudyTime(currentTodayStudyMinutes);

  String get totalStudyTimeFormatted =>
      _formatStudyTime(totalStudyMinutes);

  // LOAD PLAYER DATA

  Future<void> loadPlayer() async {
    final prefs = await SharedPreferences.getInstance();

    playerName = prefs.getString(_nameKey) ?? 'Shadow Hunter';

    level = prefs.getInt(_levelKey) ?? 1;
    xp = prefs.getInt(_xpKey) ?? 0;
    totalXp = prefs.getInt(_totalXpKey) ?? 0;

    totalStudyMinutes = prefs.getInt(_totalStudyKey) ?? 0;
    todayStudyMinutes = prefs.getInt(_todayStudyKey) ?? 0;

    _studyDate = prefs.getString(_studyDateKey) ?? '';

    // LOAD ATTRIBUTES
    hp = prefs.getInt(_hpKey) ?? 100;
    mp = prefs.getInt(_mpKey) ?? 100;

    strength = prefs.getInt(_strengthKey) ?? 0;
    intellect = prefs.getInt(_intellectKey) ?? 0;

    // HANDLE LEVEL-BASED MAXIMUMS
    hp = hp.clamp(0, maxHp);
    mp = mp.clamp(0, maxMp);

    // DAILY STUDY RESET
    if (_studyDate != _currentDateKey) {
      _studyDate = _currentDateKey;
      todayStudyMinutes = 0;

      await prefs.setString(_studyDateKey, _studyDate);
      await prefs.setInt(_todayStudyKey, 0);
    }

    await _saveAttributes();

    isLoaded = true;
    notifyListeners();
  }

  // CHANGE PLAYER NAME

  Future<void> setPlayerName(String name) async {
    final cleanedName = name.trim();

    if (cleanedName.isEmpty) return;

    playerName = cleanedName;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_nameKey, playerName);

    notifyListeners();
  }

  // ADD COMPLETED STUDY TIME

  Future<void> addStudyTime(int minutes) async {
    if (minutes <= 0) return;

    final prefs = await SharedPreferences.getInstance();

    if (_studyDate != _currentDateKey) {
      _studyDate = _currentDateKey;
      todayStudyMinutes = 0;
    }

    todayStudyMinutes += minutes;
    totalStudyMinutes += minutes;

    await prefs.setString(_studyDateKey, _studyDate);
    await prefs.setInt(_todayStudyKey, todayStudyMinutes);
    await prefs.setInt(_totalStudyKey, totalStudyMinutes);

    notifyListeners();
  }

  // ADD XP AND HANDLE LEVEL UPS

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

    // MAXIMUM HP/MP INCREASES WITH LEVEL.
    // CURRENT HP/MP WILL NOT AUTOMATICALLY REFILL.
    hp = hp.clamp(0, maxHp);
    mp = mp.clamp(0, maxMp);

    await _savePlayer();
    await _saveAttributes();

    notifyListeners();

    return leveledUp;
  }

  // SET HP

  Future<void> setHp(int value) async {
    hp = value.clamp(0, maxHp);

    await _saveAttributes();
    notifyListeners();
  }

  // SET MP

  Future<void> setMp(int value) async {
    mp = value.clamp(0, maxMp);

    await _saveAttributes();
    notifyListeners();
  }

  // RECOVER HP

  Future<void> recoverHp(int amount) async {
    if (amount <= 0) return;

    hp = (hp + amount).clamp(0, maxHp);

    await _saveAttributes();
    notifyListeners();
  }

  // RECOVER MP

  Future<void> recoverMp(int amount) async {
    if (amount <= 0) return;

    mp = (mp + amount).clamp(0, maxMp);

    await _saveAttributes();
    notifyListeners();
  }

  // ADD STRENGTH

  Future<void> addStrength(int amount) async {
    if (amount <= 0) return;

    strength += amount;

    await _saveAttributes();
    notifyListeners();
  }

  // ADD INTELLECT

  Future<void> addIntellect(int amount) async {
    if (amount <= 0) return;

    intellect += amount;

    await _saveAttributes();
    notifyListeners();
  }

  // SAVE PLAYER DATA

  Future<void> _savePlayer() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_nameKey, playerName);
    await prefs.setInt(_levelKey, level);
    await prefs.setInt(_xpKey, xp);
    await prefs.setInt(_totalXpKey, totalXp);
  }

  // SAVE ATTRIBUTE DATA

  Future<void> _saveAttributes() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_hpKey, hp);
    await prefs.setInt(_mpKey, mp);
    await prefs.setInt(_strengthKey, strength);
    await prefs.setInt(_intellectKey, intellect);
  }
}
