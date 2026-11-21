import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';
import 'uid_manager.dart';

/// Tracks security-related state: UID, online status,
/// code request cooldown, emergency unlock window.
class SecurityController extends ChangeNotifier {
  final UidManager uidManager;
  final SupabaseService supabaseService;

  SecurityController({
    required this.uidManager,
    required this.supabaseService,
  });

  // Request state
  bool _isGeneratingCode = false;
  String? _lastError;
  DateTime? _lastCodeGeneratedAt;

  // Emergency unlock state (persisted so app restarts do not erase the window).
  static const String _emergencyUnlockUntilKey = 'emergency_unlock_until_ms';
  DateTime? _emergencyUnlockUntil;
  Timer? _unlockTicker;

  // Getters
  bool get isGeneratingCode => _isGeneratingCode;
  String? get lastError => _lastError;
  DateTime? get lastCodeGeneratedAt => _lastCodeGeneratedAt;

  bool get isRegistered => uidManager.isRegistered;
  bool get isOnline => supabaseService.isOnline;
  String? get uid => uidManager.uid;

  /// True if emergency unlock is currently active.
  bool get isEmergencyUnlockActive {
    if (_emergencyUnlockUntil == null) return false;
    return DateTime.now().isBefore(_emergencyUnlockUntil!);
  }

  Duration get emergencyUnlockRemaining {
    if (!isEmergencyUnlockActive) return Duration.zero;
    return _emergencyUnlockUntil!.difference(DateTime.now());
  }

  /// Cooldown check — allow request only if no active code.
  bool get canRequestCode {
    if (_lastCodeGeneratedAt == null) return true;
    final expiry = supabaseService.codeExpiryMinutes;
    return DateTime.now().isAfter(
      _lastCodeGeneratedAt!.add(Duration(minutes: expiry)),
    );
  }

  Duration? get requestCooldownRemaining {
    if (_lastCodeGeneratedAt == null) return null;
    final expiry = _lastCodeGeneratedAt!
        .add(Duration(minutes: supabaseService.codeExpiryMinutes));
    if (DateTime.now().isAfter(expiry)) return null;
    return expiry.difference(DateTime.now());
  }

  /// Restore the unlock expiry after app restart and keep its countdown live.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryMs = prefs.getInt(_emergencyUnlockUntilKey);
    _emergencyUnlockUntil = expiryMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiryMs);
    _lastError = null;
    await refreshEmergencyUnlock();
    if (isEmergencyUnlockActive) _startUnlockTicker();
    notifyListeners();
  }

  Future<void> refreshEmergencyUnlock() async {
    final expiry = _emergencyUnlockUntil;
    if (expiry != null && !DateTime.now().isBefore(expiry)) {
      _emergencyUnlockUntil = null;
      _unlockTicker?.cancel();
      _unlockTicker = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_emergencyUnlockUntilKey);
    }
    notifyListeners();
  }

  void _startUnlockTicker() {
    _unlockTicker?.cancel();
    _unlockTicker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final expiry = _emergencyUnlockUntil;
      if (expiry == null || !DateTime.now().isBefore(expiry)) {
        await refreshEmergencyUnlock();
        _unlockTicker?.cancel();
        _unlockTicker = null;
        return;
      }
      notifyListeners();
    });
  }

  // Code requests are submitted to the linked Telegram Bot for developer approval.
  // The app must never generate security codes directly.

  // ============================================================
  // VALIDATE EMERGENCY UNLOCK
  // ============================================================

  Future<({bool success, String? error})> validateEmergencyUnlock(
    String code,
  ) async {
    final result = await supabaseService.validateCode(
      code: code,
      type: 'emergency_unlock',
    );

    if (result.success) {
      _emergencyUnlockUntil = DateTime.now().add(
        Duration(minutes: supabaseService.emergencyUnlockMinutes),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _emergencyUnlockUntilKey,
        _emergencyUnlockUntil!.millisecondsSinceEpoch,
      );
      _lastError = null;
      _startUnlockTicker();
      notifyListeners();
    }

    return (success: result.success, error: result.error);
  }

  // ============================================================
  // VALIDATE UNINSTALL
  // ============================================================

  Future<({bool success, String? error})> validateUninstall(String code) async {
    return supabaseService.validateCode(
      code: code,
      type: 'uninstall',
    );
  }

  // ============================================================
  // FORCE SYNC
  // ============================================================

  Future<void> forceSync() async {
    // Registration and UID linking are completed by the Telegram Bot only.
    await supabaseService.forceSync();
    notifyListeners();
  }

  @override
  void dispose() {
    _unlockTicker?.cancel();
    super.dispose();
  }
}