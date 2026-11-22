import 'dart:async';
import 'dart:convert';

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

/// Synchronizes recoverable Shadow Learner app state.
/// Authentication secrets, device-bound tokens, temporary authorization
/// grants and OS-owned permission state are deliberately excluded.
class CloudProgressSync {
  static const String _deviceTokenKey = 'cloud_progress_device_token';
  static const String _localChangedKey = 'cloud_progress_local_changed_ms';
  static const String _cloudUpdatedKey = 'cloud_progress_updated_ms';
  static const String _lastSnapshotFingerprintKey =
      'cloud_progress_last_snapshot_fingerprint';
  static const int schemaVersion = 3;

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

    // Timetable, rest and weekly special mission
    'study_timetable',
    'short_rest_start',
    'short_rest_applied',
    'long_rest_start',
    'weekly_special_week',
    'weekly_special_day',
    'weekly_special_mission',
    'daily_system_message_date',
    'daily_system_message_text',

    // UID registration identity (never device or bearer credentials)
    'solo_uid',
    'solo_uid_registered',
    'solo_reg_attempts',
    'player_uid',
    'player_uid_registered',

    // User preferences and notification history
    'dark_mode',
    'solo_notification_history',
    'solo_notification_history_date',

    // Pomodoro timer, settings and completed-session count
    'pomodoro_focus_minutes',
    'pomodoro_short_break_minutes',
    'pomodoro_long_break_minutes',
    'pomodoro_long_break_every',
    'pomodoro_phase',
    'pomodoro_remaining_seconds',
    'pomodoro_running',
    'pomodoro_end_time_ms',
    'pomodoro_completed_focus_sessions',
  };

  final UidManager uidManager;
  final SupabaseService supabaseService;

  bool _isApplyingRemote = false;
  bool _isSyncing = false;
  Timer? _debounce;
  Timer? _autoSyncTimer;
  String? _cachedDeviceToken;
  String? _lastPairingError;

  String? get lastPairingError => _lastPairingError;

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
    _lastPairingError = null;
    final client = supabaseService.client;
    final uid = (uidOverride ?? uidManager.uid)?.trim().toUpperCase();

    if (client == null) {
      _lastPairingError = 'Supabase client is not initialized.';
      return false;
    }
    if (uid == null || uid.isEmpty) {
      _lastPairingError = 'UID is missing.';
      return false;
    }
    if (!RegExp(r'^SOLO-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$')
        .hasMatch(uid)) {
      _lastPairingError = 'Invalid UID format. Use SOLO-XXXX-XXXX-XXXX.';
      return false;
    }
    if (pairingToken.trim().isEmpty) {
      _lastPairingError = 'Pairing token is empty.';
      return false;
    }

    try {
      final response = await client.rpc(
        'claim_progress_device',
        params: {
          'p_uid': uid,
          'p_pairing_token': pairingToken.trim(),
        },
      ).timeout(const Duration(seconds: 15));

      if (response is! Map) {
        _lastPairingError = 'Unexpected response from pairing service.';
        return false;
      }
      if (response['status'] != 'claimed') {
        _lastPairingError = 'Pairing rejected: ${response['status'] ?? 'unknown status'}';
        return false;
      }

      final token = response['device_token']?.toString();
      if (token == null || token.isEmpty) {
        _lastPairingError = 'Pairing service did not return a device token.';
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceTokenKey, token);
      _cachedDeviceToken = token;

      if (uidManager.uid != uid) {
        await uidManager.restoreRegisteredUid(uid);
      } else {
        await uidManager.markRegistered();
      }
      return true;
    } catch (e) {
      _lastPairingError = e.toString();
      return false;
    }
  }

  /// Reconcile local progress against the last confirmed snapshot and cloud revision.
  /// A fingerprint detects offline edits even if the app was killed before debounce.
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

    if (client == null) return const CloudSyncResult(CloudSyncStatus.offline);
    if (uid == null || uid.isEmpty || token == null || token.isEmpty) {
      return const CloudSyncResult(CloudSyncStatus.notPaired);
    }

    _isSyncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final localSnapshot = await _captureSnapshot();
      final localFingerprint = _snapshotFingerprint(localSnapshot);
      final previousFingerprint =
          prefs.getString(_lastSnapshotFingerprintKey);
      final previousCloudMs = prefs.getInt(_cloudUpdatedKey) ?? 0;
      final localChangedMs = prefs.getInt(_localChangedKey) ?? 0;

      // A changed fingerprint alone is not proof of a user edit: a newer app
      // version may add default preferences. Only prefer local data when a
      // real local-change marker is newer than the last confirmed cloud copy.
      final hasOfflineLocalChanges = previousFingerprint != null &&
          localFingerprint != previousFingerprint &&
          localChangedMs > previousCloudMs;

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
        final saved = await _uploadSnapshot(snapshot: localSnapshot);
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
      final cloudMs = cloudUpdatedAt?.millisecondsSinceEpoch ?? 0;
      final legacyLocalChangedMs = localChangedMs;

      // Preserve local edits made while offline. For older installs that do
      // not yet have a baseline fingerprint, retain the previous timestamp
      // migration rule for the first reconciliation.
      final shouldUploadLocal = hasOfflineLocalChanges ||
          (previousFingerprint == null &&
              legacyLocalChangedMs > 0 &&
              legacyLocalChangedMs >= cloudMs);

      if (shouldUploadLocal) {
        final saved = await _uploadSnapshot(snapshot: localSnapshot);
        return saved
            ? const CloudSyncResult(CloudSyncStatus.synced)
            : const CloudSyncResult(
                CloudSyncStatus.failed,
                'Offline progress could not be uploaded yet.',
              );
      }

      if (previousFingerprint == null ||
          cloudMs > previousCloudMs) {
        await _applySnapshot(Map<String, dynamic>.from(snapshot));
        final restoredSnapshot = await _captureSnapshot();

        // Upgrade older cloud snapshots immediately. This also stores newly
        // introduced recoverable preferences without waiting for user edits.
        final migrated = await _uploadSnapshot(snapshot: restoredSnapshot);
        if (!migrated) {
          return const CloudSyncResult(
            CloudSyncStatus.failed,
            'Progress restored, but the cloud backup upgrade could not be saved.',
          );
        }
        return const CloudSyncResult(CloudSyncStatus.restored);
      }

      // Local and cloud copies are already aligned.
      return const CloudSyncResult(CloudSyncStatus.synced);
    } catch (e) {
      return CloudSyncResult(CloudSyncStatus.failed, e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _uploadSnapshot({Map<String, dynamic>? snapshot}) async {
    final client = supabaseService.client;
    final uid = uidManager.uid;
    final token = _deviceToken;
    if (client == null || uid == null || token == null || token.isEmpty) {
      return false;
    }

    try {
      final payload = snapshot ?? await _captureSnapshot();
      final response = await client.rpc(
        'save_player_progress',
        params: {
          'p_uid': uid,
          'p_device_token': token,
          'p_snapshot': payload,
          'p_schema_version': schemaVersion,
        },
      ).timeout(const Duration(seconds: 20));

      if (response is! Map || response['status'] != 'saved') return false;

      final updatedAt =
          DateTime.tryParse(response['updated_at']?.toString() ?? '');
      final timestamp =
          updatedAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cloudUpdatedKey, timestamp);
      await prefs.setInt(_localChangedKey, timestamp);
      await prefs.setString(
        _lastSnapshotFingerprintKey,
        _snapshotFingerprint(payload),
      );
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

    final level = (progress['player_level'] as int? ?? 1).clamp(1, 999);
    final title = level <= 5
        ? 'The Awakener'
        : level <= 10
            ? 'Rookie Hunter'
            : level <= 20
                ? 'Rising Hunter'
                : level <= 35
                    ? 'Elite Hunter'
                    : level <= 50
                        ? 'Master Hunter'
                        : level <= 75
                            ? 'Shadow Monarch'
                            : 'Monarch of Shadows';
    final rank = level <= 5
        ? 'E-Rank'
        : level <= 10
            ? 'D-Rank'
            : level <= 20
                ? 'C-Rank'
                : level <= 35
                    ? 'B-Rank'
                    : level <= 50
                        ? 'A-Rank'
                        : level <= 75
                            ? 'S-Rank'
                            : 'National Level';

    return {
      'schema_version': schemaVersion,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'player_summary': {
        'player_name': progress['player_name'] ?? 'Shadow Hunter',
        'level': level,
        'xp': progress['player_xp'] ?? 0,
        'total_xp': progress['player_total_xp'] ?? 0,
        'hp': progress['player_hp'] ?? 100,
        'mp': progress['player_mp'] ?? 100,
        'total_study_minutes': progress['total_study_minutes'] ?? 0,
        'rank': rank,
        'title': title,
      },
      'preferences': progress,
    };
  }

  String _snapshotFingerprint(Map<String, dynamic> snapshot) {
    final stable = Map<String, dynamic>.from(snapshot)
      ..remove('captured_at');
    return jsonEncode(stable);
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

      // Merge only values present in the incoming snapshot. A snapshot
      // created by an older app version may not contain newer keys; absence
      // must never be interpreted as an instruction to erase local data.
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

  /// Keep progress backed up while the app remains in the foreground.
  /// Local listeners still trigger faster debounced uploads between intervals.
  void startAutoSync({Duration interval = const Duration(minutes: 1)}) {
    _autoSyncTimer?.cancel();
    if (!isPaired) return;
    _autoSyncTimer = Timer.periodic(interval, (_) async {
      if (!isPaired || _isSyncing) return;
      await syncNow();
    });
  }

  void dispose() {
    _debounce?.cancel();
    _autoSyncTimer?.cancel();
  }
}
