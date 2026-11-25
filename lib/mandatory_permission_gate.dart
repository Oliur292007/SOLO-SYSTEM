import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'notification_pages.dart';
import 'notification_service.dart';

/// Keeps the app's functional areas unavailable until every required Android
/// permission is enabled. Android Settings remains under the user's control.
class MandatoryPermissionGate extends StatefulWidget {
  final MissionNotificationService notificationService;
  final Widget child;

  const MandatoryPermissionGate({
    super.key,
    required this.notificationService,
    required this.child,
  });

  @override
  State<MandatoryPermissionGate> createState() =>
      _MandatoryPermissionGateState();
}

class _MandatoryPermissionGateState extends State<MandatoryPermissionGate>
    with WidgetsBindingObserver {
  static const MethodChannel _channel =
      MethodChannel('solo_system/app_restriction');

  bool _checking = true;
  bool _ready = false;
  bool _refreshInProgress = false;
  Timer? _permissionPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
    _startPermissionPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_ready && mounted) {
        setState(() {
          _ready = false;
          _checking = true;
        });
        _startPermissionPolling();
      }
      _refreshPermissions();
    }
  }

  void _startPermissionPolling() {
    _permissionPollTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (!_ready) _refreshPermissions();
      },
    );
  }

  Future<void> _refreshPermissions() async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    var notifications = false;
    var exactAlarms = false;
    var accessibilityEnabled = false;
    var accessibilityConnected = false;
    var usageAccess = false;
    var batteryExemption = false;

    try {
      notifications =
          await widget.notificationService.areNotificationsEnabled();
      exactAlarms =
          await widget.notificationService.canScheduleExactNotifications();
      accessibilityEnabled =
          await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
      accessibilityConnected =
          await _channel.invokeMethod<bool>(
                'isAccessibilityServiceConnected',
              ) ??
              false;
      usageAccess =
          await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
      batteryExemption =
          await _channel.invokeMethod<bool>(
                'isIgnoringBatteryOptimizations',
              ) ??
              false;
    } catch (error) {
      debugPrint('MANDATORY PERMISSION CHECK ERROR: $error');
    }

    _refreshInProgress = false;
    if (!mounted) return;
    final allGranted = notifications &&
        exactAlarms &&
        accessibilityEnabled &&
        accessibilityConnected &&
        usageAccess &&
        batteryExemption;
    if (_ready != allGranted || _checking) {
      setState(() {
        _ready = allGranted;
        _checking = false;
      });
    }
    if (_ready) {
      _permissionPollTimer?.cancel();
      _permissionPollTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;

    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF050B18),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PermissionManagementPage(
      notificationService: widget.notificationService,
    );
  }
}
