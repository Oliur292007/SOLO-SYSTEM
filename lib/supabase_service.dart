import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'uid_manager.dart';

class SupabaseService {
  static const String _configCacheKey = 'supabase_config_cache';
  static const String _whitelistCacheKey = 'supabase_whitelist_cache';
  static const String _lastSyncKey = 'supabase_last_sync';
  static const String _cloudDeviceTokenKey = 'cloud_progress_device_token';

  // Global variable to store the last error for the UI Diagnostic
  static String? lastRegistrationError;

  final UidManager uidManager;

  SupabaseService({required this.uidManager});

  SupabaseClient? _client;

  // Cached state
  Map<String, String> _config = Map.from(SupabaseConfig.fallbackConfig);
  List<Map<String, dynamic>> _whitelist = SupabaseConfig.fallbackWhitelist
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  bool _isOnline = false;
  DateTime? _lastSync;

  Timer? _retryTimer;

  // Getters
  SupabaseClient? get client => _client;
  Map<String, String> get config => Map.unmodifiable(_config);
  List<Map<String, dynamic>> get whitelist => List.unmodifiable(_whitelist);
  
  bool get isOnline {
    if (_isOnline) return true;
    if (_lastSync == null) return false;
    return DateTime.now().difference(_lastSync!) < const Duration(minutes: 2);
  }

  DateTime? get lastSync => _lastSync;

  String get whatsappNumber =>
      _config['whatsapp_number'] ?? SupabaseConfig.fallbackConfig['whatsapp_number']!;

  int get codeExpiryMinutes =>
      int.tryParse(_config['code_expiry_minutes'] ?? '30') ?? 30;

  int get emergencyUnlockMinutes =>
      int.tryParse(_config['emergency_unlock_minutes'] ?? '30') ?? 30;

  int get youtubeWarningIntervalMinutes =>
      int.tryParse(_config['youtube_warning_interval_minutes'] ?? '5') ?? 5;

  int get youtubeHpDamageIntervalMinutes =>
      int.tryParse(_config['youtube_hp_damage_interval_minutes'] ?? '30') ?? 30;

  double get youtubeHpDamageBasePercent =>
      double.tryParse(_config['youtube_hp_damage_base_percent'] ?? '5') ?? 5.0;

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.publishableKey,
      );
      _client = Supabase.instance.client;
    } catch (e) {
      debugPrint('Supabase init failed: $e');
      _client = null;
    }

    await _loadCache();
    await _tryNetworkSync();
  }

  // ============================================================
  // CACHE
  // ============================================================

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final configRaw = prefs.getString(_configCacheKey);
      if (configRaw != null) {
        final decoded = jsonDecode(configRaw) as Map<String, dynamic>;
        _config = decoded.map((k, v) => MapEntry(k, v.toString()));
      }

      final whitelistRaw = prefs.getString(_whitelistCacheKey);
      if (whitelistRaw != null) {
        final decoded = jsonDecode(whitelistRaw) as List<dynamic>;
        _whitelist = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      final lastSyncMs = prefs.getInt(_lastSyncKey);
      if (lastSyncMs != null) {
        _lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
      }
    } catch (e) {
      debugPrint('Cache load failed: $e');
    }
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configCacheKey, jsonEncode(_config));
    await prefs.setString(_whitelistCacheKey, jsonEncode(_whitelist));
    if (_lastSync != null) {
      await prefs.setInt(_lastSyncKey, _lastSync!.millisecondsSinceEpoch);
    }
  }

  // ============================================================
  // NETWORK SYNC
  // ============================================================

  Future<void> _tryNetworkSync() async {
    if (_client == null) {
      _isOnline = false;
      _scheduleRetry();
      return;
    }

    try {
      final configRes = await _client!
          .rpc('get_config')
          .timeout(const Duration(seconds: 10));

      if (configRes is Map) {
        _config = Map<String, String>.from(
          configRes.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }

      final whitelistRes = await _client!
          .rpc('get_whitelist')
          .timeout(const Duration(seconds: 10));

      if (whitelistRes is List) {
        _whitelist = whitelistRes
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      _isOnline = true;
      _lastSync = DateTime.now();
      await _saveCache();

      _retryTimer?.cancel();
      _retryTimer = null;
    } catch (e) {
      _isOnline = false;
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      SupabaseConfig.syncRetryInterval,
      (_) async {
        if (_isOnline) {
          _retryTimer?.cancel();
          _retryTimer = null;
          return;
        }
        await _tryNetworkSync();
      },
    );
  }

  Future<bool> forceSync() async {
    await _tryNetworkSync();
    return _isOnline;
  }

  // ============================================================
  // GENERATE CODES
  // ============================================================

  Future<({bool success, String? error, DateTime? expiresAt})> generateCodes() async {
    if (!uidManager.hasUid) {
      return (success: false, error: 'UID not initialized', expiresAt: null);
    }

    if (!uidManager.isRegistered) {
      return (
        success: false,
        error: 'Not registered. Connect to internet first.',
        expiresAt: null,
      );
    }

    if (_client == null) {
      return (success: false, error: 'No internet connection', expiresAt: null);
    }

    try {
      final result = await _client!
          .rpc('generate_codes', params: {'p_uid': uidManager.uid})
          .timeout(const Duration(seconds: 15));

      if (result is! Map) {
        return (success: false, error: 'Invalid response format', expiresAt: null);
      }

      if (result['success'] == true) {
        final expiresAtStr = result['expires_at'] as String?;
        final expiresAt =
            expiresAtStr != null ? DateTime.parse(expiresAtStr) : null;
        _isOnline = true;
        return (success: true, error: null, expiresAt: expiresAt);
      }

      return (
        success: false,
        error: result['error']?.toString() ?? 'Failed to generate codes',
        expiresAt: null,
      );
    } catch (e) {
      _isOnline = false;
      return (
        success: false,
        error: 'Exception: $e',
        expiresAt: null,
      );
    }
  }

  // ============================================================
  // VALIDATE CODE
  // ============================================================

  Future<({bool success, String? error})> validateCode({
    required String code,
    required String type,
  }) async {
    if (!uidManager.hasUid) {
      return (success: false, error: 'UID not initialized');
    }

    if (_client == null) {
      return (success: false, error: 'No internet connection');
    }

    try {
      final result = await _client!
          .rpc('validate_code', params: {
            'p_uid': uidManager.uid,
            'p_code': code.trim().toUpperCase(),
            'p_type': type,
            'p_device_token': (await SharedPreferences.getInstance())
                .getString(_cloudDeviceTokenKey),
          })
          .timeout(const Duration(seconds: 15));

      if (result is! Map) {
        return (success: false, error: 'Invalid response');
      }

      if (result['success'] == true) {
        _isOnline = true;
        return (success: true, error: null);
      }

      return (
        success: false,
        error: result['error']?.toString() ?? 'Invalid code',
      );
    } catch (e) {
      _isOnline = false;
      return (success: false, error: 'Exception: $e');
    }
  }

  // ============================================================
  // WHITELIST HELPERS
  // ============================================================

  bool isWhitelisted(String packageName) {
    return _whitelist.any(
      (e) =>
          e['package_name'] == packageName &&
          (e['category'] == 'allowed' || e['category'] == 'youtube_special'),
    );
  }

  bool isYouTube(String packageName) {
    final entry =
        _whitelist.firstWhere(
      (e) => e['package_name'] == packageName,
      orElse: () => {},
    );
    return entry['category'] == 'youtube_special';
  }

  bool isRestricted(String packageName) {
    return !isWhitelisted(packageName);
  }

  void dispose() {
    _retryTimer?.cancel();
  }
}