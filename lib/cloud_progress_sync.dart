import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';
import 'uid_manager.dart';

enum CloudSyncStatus {
  synced,
  restored,
  noBackup,
  notPaired,
  offline,
  unauthorized,
  failed,
}

class CloudSyncResult {
  final CloudSyncStatus status;
  final String? message;

  const CloudSyncResult(this.status, [this.message]);
}

/// Synchronizes only known SOLO SYSTEM progress preferences.
/// Account credentials, device tokens, app settings and service caches are
/// deliberately excluded from cloud snapshots.
class CloudProgressSync {
  static const String _deviceTokenKey = 'cloud_progress_device_token';
  static const String _localChangedKey = 'cloud_progress_local_changed_ms';
  static const String _cloudUpdatedKey = 'cloud_progress_updated_ms';
  static const int schemaVersion = 1;

  static const Set<String> _progressKeys = {
    // Player
    'player_name',
    'player_level',
    'player_xp',
    'player_total_xp',
    'total_study_minutes',
    'today_study_minutes',
    'study_date',
    'player_hp',
    'player_mp',
    'player_strength',
    'player_intellect',
    'hp_damage_history',

    // Quests and penalties
    'quest_date',
    'completed_quests',
    'missed_quests',
    'skipped_quests',
    'quest_snapshot',
    'penalty_until',
    'night_lock_active',
    'quest_timer_starts',

    // Study timer
    'timer_quest_id',
    'timer_end_time',
    'timer_remaining',
    'timer_running',
    'timer_finished',
    'timer_reserved_mp',
    'timer_started_at',

    // Timetable and rest
    'study_timetable',
    'short_rest_start',
    'short_rest_applied',
    'long_rest_start',
  };

  final UidManager uidManager;
  final SupabaseService supabaseService;

  bool _isApplyingRemote = false;
  bool _isSyncing = false;
  Timer? _debounce;
  String? _cachedDeviceToken;

  CloudProgressSync({
    required this.uidManager,
    required this.supabaseService,
  });

  bool get isPaired =>
      _cachedDeviceToken != null && _cachedDeviceToken!.isNotEmpty;

  bool get isApplyingRemote => _isApplyingRemote;

  String? get _deviceToken => _cachedDeviceToken;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedDeviceToken = prefs.getString(_deviceTokenKey);
  }

  /// Claims a one-time pairing token supplied by the Telegram bot.
  Future<bool> claimPairingToken(
    String pairingToken, {
    String? uidOverride,
  }) async {
    final client = supabaseService.client;
    final uid = (uidOverride ?? uidManager.uid)?.trim().toUpperCase();

    if (client == null || uid == null || uid.isEmpty) return false;
    if (!RegExp(r'^SOLO-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$')
        .hasMatch(uid)) {
      return false;
    }
    if (pairingToken.trim().isEmpty) return false;

    try {
      final response = await client.rpc(
        'claim_progress_device',
        params: {
          'p_uid': uid,
          'p_pairing_token': pairingToken.trim(),
        },
      ).timeout(const Duration(seconds: 15));

      if (response is! Map || response['status'] != 'claimed') {
        return false;
      }

      final token = response['device_token']?.toString();
      if (token == null || token.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceTokenKey, token);
      _cachedDeviceToken = token;

      if (uidManager.uid != uid) {
        await uidManager.restoreRegisteredUid(uid);
      } else {
        await uidManager.markRegistered();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Restores a newer cloud snapshot, or uploads local progress when local
  /// progress is newer. The RPC validates the per-device token.
  Future<CloudSyncResult> syncNow() async {
    if (_isSyncing) {
      return const CloudSyncResult(
        CloudSyncStatus.failed,
        'Sync already running.',
      );
    }

    final client = supabaseService.client;
    final uid = uidManager.uid;
    final token = _deviceToken;

    if (client == null) {
      return const CloudSyncResult(CloudSyncStatus.offline);
    }
    if (uid == null || uid.isEmpty || token == null || token.isEmpty) {
      return const CloudSyncResult(CloudSyncStatus.notPaired);
    }

    _isSyncing = true;
    try {
      final response = await client.rpc(
        'restore_player_progress',
        params: {'p_uid': uid, 'p_device_token': token},
      ).timeout(const Duration(seconds: 20));

      if (response is! Map) {
        return const CloudSyncResult(
          CloudSyncStatus.failed,
          'Invalid cloud response.',
        );
      }

      final status = response['status']?.toString();
      if (status == 'unauthorized') {
        return const CloudSyncResult(CloudSyncStatus.unauthorized);
      }

      if (status == 'no_backup') {
        final saved = await _uploadSnapshot();
        return saved
            ? const CloudSyncResult(CloudSyncStatus.synced)
            : const CloudSyncResult(
                CloudSyncStatus.failed,
                'Could not create first backup.',
              );
      }

      if (status != 'restored') {
        return CloudSyncResult(
          CloudSyncStatus.failed,
          status ?? 'Unknown cloud status.',
        );
      }

      final snapshot = response['snapshot'];
      if (snapshot is! Map) {
        return const CloudSyncResult(
          CloudSyncStatus.failed,
          'Cloud backup is invalid.',
        );
      }

      final cloudUpdatedAt =
          DateTime.tryParse(response['updated_at']?.toString() ?? '');
      final prefs = await SharedPreferences.getInstance();
      final localChangedMs = prefs.getInt(_localChangedKey) ?? 0;
      final cloudMs = cloudUpdatedAt?.millisecondsSinceEpoch ?? 0;

      if (localChangedMs == 0 || cloudMs > localChangedMs) {
        await _applySnapshot(Map<String, dynamic>.from(snapshot));
        await prefs.setInt(_localChangedKey, cloudMs);
        await prefs.setInt(_cloudUpdatedKey, cloudMs);
        return const CloudSyncResult(CloudSyncStatus.restored);
      }

      final saved = await _uploadSnapshot();
      return saved
          ? const CloudSyncResult(CloudSyncStatus.synced)
          : const CloudSyncResult(
              CloudSyncStatus.failed,
              'Upload failed.',
            );
    } catch (e) {
      return CloudSyncResult(CloudSyncStatus.failed, e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _uploadSnapshot() async {
    final client = supabaseService.client;
    final uid = uidManager.uid;
    final token = _deviceToken;
    if (client == null || uid == null || token == null || token.isEmpty) {
      return false;
    }

    try {
      final snapshot = await _captureSnapshot();
      final response = await client.rpc(
        'save_player_progress',
        params: {
          'p_uid': uid,
          'p_device_token': token,
          'p_snapshot': snapshot,
          'p_schema_version': schemaVersion,
        },
      ).timeout(const Duration(seconds: 20));

      if (response is! Map || response['status'] != 'saved') return false;

      final updatedAt =
          DateTime.tryParse(response['updated_at']?.toString() ?? '');
      if (updatedAt != null) {
        final prefs = await SharedPreferences.getInstance();
        final timestamp = updatedAt.millisecondsSinceEpoch;
        await prefs.setInt(_cloudUpdatedKey, timestamp);
        await prefs.setInt(_localChangedKey, timestamp);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _captureSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final progress = <String, dynamic>{};

    for (final key in _progressKeys) {
      final value = prefs.get(key);
      if (value is String ||
          value is bool ||
          value is int ||
          value is double) {
        progress[key] = value;
      } else if (value is List<String>) {
        progress[key] = List<String>.from(value);
      }
    }

    return {
      'schema_version': schemaVersion,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'preferences': progress,
    };
  }

  Future<void> _applySnapshot(Map<String, dynamic> envelope) async {
    final values = envelope['preferences'];
    if (values is! Map) {
      throw const FormatException('Missing preferences map.');
    }

    final remote = Map<String, dynamic>.from(values);
    if (remote.keys.any((key) => !_progressKeys.contains(key))) {
      throw const FormatException('Cloud snapshot contains unknown keys.');
    }

    _isApplyingRemote = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Only remove missing keys that belong to the progress allowlist.
      // Theme, onboarding, security and other app preferences remain intact.
      for (final key in _progressKeys) {
        if (!remote.containsKey(key)) await prefs.remove(key);
      }

      for (final entry in remote.entries) {
        final key = entry.key;
        final value = entry.value;

        if (value is String) {
          await prefs.setString(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is List) {
          await prefs.setStringList(
            key,
            value.map((item) => item.toString()).toList(),
          );
        } else {
          throw FormatException('Unsupported value for $key.');
        }
      }
    } finally {
      _isApplyingRemote = false;
    }
  }

  Future<void> markLocalChange() async {
    if (_isApplyingRemote || _isSyncing || !isPaired) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _localChangedKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  void scheduleSync({Duration delay = const Duration(seconds: 3)}) {
    if (!isPaired || _isApplyingRemote) return;

    _debounce?.cancel();
    _debounce = Timer(delay, () async {
      await markLocalChange();
      await _uploadSnapshot();
    });
  }

  void dispose() {
    _debounce?.cancel();
  }
}
