
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerSystem extends ChangeNotifier {
  static const String _nameKey = 'player_name';
  static const String _levelKey = 'player_level';
  static const String _xpKey = 'player_xp';
  static const String _totalXpKey = 'player_total_xp';

  static const String _totalStudyKey = 'total_study_minutes';
  static const String _todayStudyKey = 'today_study_minutes';
  static const String _studyDateKey = 'study_date';

  String playerName = 'Shadow Hunter';

  int level = 1;
  int xp = 0;
  int totalXp = 0;

  int totalStudyMinutes = 0;
  int todayStudyMinutes = 0;

  String _studyDate = '';

  bool isLoaded = false;

  int get xpRequired => 1000 + ((level - 1) * 250);

  double get xpProgress =>
      (xp / xpRequired).clamp(0.0, 1.0).toDouble();

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

  Future<void> loadPlayer() async {
    final prefs = await SharedPreferences.getInstance();

    playerName = prefs.getString(_nameKey) ?? 'Player';

    level = prefs.getInt(_levelKey) ?? 1;
    xp = prefs.getInt(_xpKey) ?? 0;
    totalXp = prefs.getInt(_totalXpKey) ?? 0;

    totalStudyMinutes = prefs.getInt(_totalStudyKey) ?? 0;
    todayStudyMinutes = prefs.getInt(_todayStudyKey) ?? 0;

    _studyDate = prefs.getString(_studyDateKey) ?? '';

    if (_studyDate != _currentDateKey) {
      _studyDate = _currentDateKey;
      todayStudyMinutes = 0;

      await prefs.setString(_studyDateKey, _studyDate);
      await prefs.setInt(_todayStudyKey, 0);
    }

    isLoaded = true;
    notifyListeners();
  }

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

    await _savePlayer();

    notifyListeners();

    return leveledUp;
  }

  Future<void> _savePlayer() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_nameKey, playerName);
    await prefs.setInt(_levelKey, level);
    await prefs.setInt(_xpKey, xp);
    await prefs.setInt(_totalXpKey, totalXp);
  }
}
