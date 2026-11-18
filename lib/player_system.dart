
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerSystem extends ChangeNotifier {
  static const String _nameKey = 'player_name';
  static const String _levelKey = 'player_level';
  static const String _xpKey = 'player_xp';
  static const String _totalXpKey = 'player_total_xp';

  String playerName = 'Player';
  int level = 1;
  int xp = 0;
  int totalXp = 0;

  bool isLoaded = false;

  int get xpRequired => 1000 + ((level - 1) * 250);

  double get xpProgress =>
      (xp / xpRequired).clamp(0.0, 1.0);

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

  Future<void> loadPlayer() async {
    final prefs = await SharedPreferences.getInstance();

    playerName = prefs.getString(_nameKey) ?? 'Player';
    level = prefs.getInt(_levelKey) ?? 1;
    xp = prefs.getInt(_xpKey) ?? 0;
    totalXp = prefs.getInt(_totalXpKey) ?? 0;

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
