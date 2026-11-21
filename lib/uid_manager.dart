import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class UidManager {
  static const String _uidKey = 'solo_uid';
  static const String _deviceIdKey = 'solo_device_id';
  static const String _registeredKey = 'solo_uid_registered';
  static const String _registrationAttemptsKey = 'solo_reg_attempts';

  String? _uid;
  String? _deviceId;
  bool _isRegistered = false;
  int _registrationAttempts = 0;

  String? get uid => _uid;
  String? get deviceId => _deviceId;
  bool get isRegistered => _isRegistered;
  bool get hasUid => _uid != null && _uid!.isNotEmpty;
  int get registrationAttempts => _registrationAttempts;

  Future<bool> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _uid = prefs.getString(_uidKey);
    _deviceId = prefs.getString(_deviceIdKey);
    _isRegistered = prefs.getBool(_registeredKey) ?? false;
    _registrationAttempts = prefs.getInt(_registrationAttemptsKey) ?? 0;

    var isNew = false;
    if (_uid == null || _uid!.isEmpty) {
      _uid = _generateUid();
      _deviceId = _generateDeviceId();
      _isRegistered = false;
      _registrationAttempts = 0;
      isNew = true;
      await prefs.setString(_uidKey, _uid!);
      await prefs.setString(_deviceIdKey, _deviceId!);
      await prefs.setBool(_registeredKey, false);
      await prefs.setInt(_registrationAttemptsKey, 0);
    } else if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _generateDeviceId();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }
    return isNew;
  }

  String _generateUid() {
    const uuid = Uuid();
    final raw = uuid.v4().replaceAll('-', '').toUpperCase();
    return 'SOLO-${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8, 12)}';
  }

  String _generateDeviceId() => const Uuid().v4();

  /// Use only after Telegram Bot verified this UID and issued a pairing token.
  Future<void> restoreRegisteredUid(String recoveredUid) async {
    final normalized = recoveredUid.trim().toUpperCase();
    if (!RegExp(r'^SOLO-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$')
        .hasMatch(normalized)) {
      throw ArgumentError('Invalid SOLO UID format.');
    }

    _uid = normalized;
    _deviceId ??= _generateDeviceId();
    _isRegistered = true;
    _registrationAttempts = 0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uidKey, normalized);
    await prefs.setString(_deviceIdKey, _deviceId!);
    await prefs.setBool(_registeredKey, true);
    await prefs.setInt(_registrationAttemptsKey, 0);
  }

  Future<void> markRegistered() async {
    _isRegistered = true;
    _registrationAttempts = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_registeredKey, true);
    await prefs.setInt(_registrationAttemptsKey, 0);
  }

  Future<void> incrementRegistrationAttempts() async {
    _registrationAttempts++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_registrationAttemptsKey, _registrationAttempts);
  }

  /// Dev-only: clear UID (for testing). Do not expose in UI.
  Future<void> clearAll() async {
    _uid = null;
    _deviceId = null;
    _isRegistered = false;
    _registrationAttempts = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_uidKey);
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_registeredKey);
    await prefs.remove(_registrationAttemptsKey);
  }
}
