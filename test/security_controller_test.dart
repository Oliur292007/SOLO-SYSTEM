import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/security_controller.dart';
import '../lib/supabase_service.dart';
import '../lib/uid_manager.dart';

class _FakeSupabaseService extends SupabaseService {
  _FakeSupabaseService({required super.uidManager});

  bool nextSuccess = true;
  String? nextError;
  String? lastCode;
  String? lastType;

  @override
  int get emergencyUnlockMinutes => 30;

  @override
  Future<({bool success, String? error})> validateCode({
    required String code,
    required String type,
  }) async {
    lastCode = code;
    lastType = type;
    return (success: nextSuccess, error: nextError);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UidManager uidManager;
  late _FakeSupabaseService supabase;
  late SecurityController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    uidManager = UidManager();
    await uidManager.initialize();
    supabase = _FakeSupabaseService(uidManager: uidManager);
    controller = SecurityController(
      uidManager: uidManager,
      supabaseService: supabase,
    );
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
  });

  test('emergency unlock is persisted and restored after controller restart',
      () async {
    final result = await controller.validateEmergencyUnlock('emu-abcd-1234');

    expect(result.success, isTrue);
    expect(supabase.lastType, 'emergency_unlock');
    expect(supabase.lastCode, 'emu-abcd-1234');
    expect(controller.isEmergencyUnlockActive, isTrue);

    final prefs = await SharedPreferences.getInstance();
    final storedExpiry = prefs.getInt('emergency_unlock_until_ms');
    expect(storedExpiry, isNotNull);
    expect(storedExpiry!, greaterThan(DateTime.now().millisecondsSinceEpoch));

    controller.dispose();
    controller = SecurityController(
      uidManager: uidManager,
      supabaseService: supabase,
    );
    await controller.initialize();

    expect(controller.isEmergencyUnlockActive, isTrue);
    expect(controller.emergencyUnlockRemaining.inMinutes, lessThanOrEqualTo(30));
  });

  test('failed emergency code never activates or persists an unlock', () async {
    supabase
      ..nextSuccess = false
      ..nextError = 'Invalid code';

    final result = await controller.validateEmergencyUnlock('EMU-INVALID');

    expect(result.success, isFalse);
    expect(result.error, 'Invalid code');
    expect(controller.isEmergencyUnlockActive, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('emergency_unlock_until_ms'), isNull);
  });

  test('uninstall authorization uses its own code type and never unlocks apps',
      () async {
    final result = await controller.validateUninstall('UNI-ABCD-1234');

    expect(result.success, isTrue);
    expect(supabase.lastType, 'uninstall');
    expect(supabase.lastCode, 'UNI-ABCD-1234');
    expect(controller.isEmergencyUnlockActive, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('emergency_unlock_until_ms'), isNull);
  });

  test('expired emergency unlock is cleared during initialization', () async {
    SharedPreferences.setMockInitialValues({
      'emergency_unlock_until_ms':
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    });

    final expiredController = SecurityController(
      uidManager: uidManager,
      supabaseService: supabase,
    );
    await expiredController.initialize();

    expect(expiredController.isEmergencyUnlockActive, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('emergency_unlock_until_ms'), isNull);
    expiredController.dispose();
  });
}
