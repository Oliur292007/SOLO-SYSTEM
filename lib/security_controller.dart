import 'package:flutter/foundation.dart';

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

  // Emergency unlock state
  DateTime? _emergencyUnlockUntil;

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

  /// Clear old emergency unlock window (called on app reload).
  Future<void> initialize() async {
    _emergencyUnlockUntil = null;
    _lastCodeGeneratedAt = null;
    _lastError = null;
    notifyListeners();
  }

  // ============================================================
  // GENERATE CODES
  // ============================================================

  Future<bool> requestCodes() async {
    if (_isGeneratingCode) return false;
    if (!isRegistered) {
      _lastError = 'Not registered yet. Connect to internet.';
      notifyListeners();
      return false;
    }

    _isGeneratingCode = true;
    _lastError = null;
    notifyListeners();

    try {
      final result = await supabaseService.generateCodes();
      if (result.success) {
        _lastCodeGeneratedAt = DateTime.now();
        _lastError = null;
        _isGeneratingCode = false;
        notifyListeners();
        return true;
      } else {
        _lastError = result.error ?? 'Failed to generate codes';
        _isGeneratingCode = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = 'Network error. Try again.';
      _isGeneratingCode = false;
      notifyListeners();
      return false;
    }
  }

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
      _lastError = null;
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
}