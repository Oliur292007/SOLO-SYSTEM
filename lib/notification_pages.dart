import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'notification_service.dart';

class NotificationHistoryPage extends StatelessWidget {
  final MissionNotificationService notificationService;

  const NotificationHistoryPage({
    super.key,
    required this.notificationService,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NOTIFICATIONS'),
        actions: [
          IconButton(
            tooltip: 'Clear today\'s notifications',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await notificationService.clearHistory();
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: notificationService,
        builder: (context, _) {
          final items = notificationService.history.reversed.toList();
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none, size: 54,
                        color: colors.primary),
                    const SizedBox(height: 12),
                    const Text('NO NOTIFICATIONS YET',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Mission updates and system alerts will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    item.type == 'failed'
                        ? Icons.warning_amber_rounded
                        : item.type == 'reward'
                            ? Icons.stars
                            : item.type == 'level'
                                ? Icons.trending_up
                                : item.type == 'title'
                                    ? Icons.military_tech
                                    : Icons.notifications_active_outlined,
                    color: colors.primary,
                  ),
                  title: Text(item.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(item.body),
                  ),
                  trailing: Text(
                    TimeOfDay.fromDateTime(item.createdAt).format(context),
                    style: TextStyle(fontSize: 10,
                        color: colors.onSurfaceVariant),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SystemMessagePage extends StatelessWidget {
  final String message;

  const SystemMessagePage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('SYSTEM MESSAGE')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome, color: colors.primary, size: 30),
                  const SizedBox(height: 14),
                  Text('DAILY SYSTEM MESSAGE',
                      style: TextStyle(color: colors.primary,
                          fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  Text(
                    message.isEmpty
                        ? 'Complete your Wakeup Mission to receive today\'s System Message.'
                        : message,
                    style: const TextStyle(fontSize: 15, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PermissionManagementPage extends StatefulWidget {
  final MissionNotificationService notificationService;

  const PermissionManagementPage({
    super.key,
    required this.notificationService,
  });

  @override
  State<PermissionManagementPage> createState() =>
      _PermissionManagementPageState();
}

class _PermissionManagementPageState extends State<PermissionManagementPage>
    with WidgetsBindingObserver {
  static const MethodChannel _channel =
      MethodChannel('solo_system/app_restriction');
  bool _notificationsEnabled = false;
  bool _exactAlarmsEnabled = false;
  bool _accessibilityEnabled = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final notifications =
        await widget.notificationService.areNotificationsEnabled();
    final exactAlarms =
        await widget.notificationService.canScheduleExactNotifications();
    bool accessibility = false;
    try {
      accessibility =
          await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = notifications;
      _exactAlarmsEnabled = exactAlarms;
      _accessibilityEnabled = accessibility;
      _checking = false;
    });
  }

  Future<void> _open(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open settings: ${error.message}')),
      );
    }
  }

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: colors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: _checking
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(enabled ? Icons.check_circle : Icons.error_outline,
                      color: enabled ? Colors.green : Colors.orange),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right),
                ],
              ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PERMISSIONS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('APP PERMISSION MANAGEMENT',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          const Text('Check each permission here. Android may require you to enable it in system settings.'),
          const SizedBox(height: 14),
          _permissionTile(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications',
            subtitle: 'Mission reminders, rewards and System updates',
            enabled: _notificationsEnabled,
            onTap: () => _open('openAppNotificationSettings'),
          ),
          _permissionTile(
            icon: Icons.alarm,
            title: 'Exact Alarm / Schedule Reminders',
            subtitle: 'Allow precise reminders five minutes before each schedule',
            enabled: _exactAlarmsEnabled,
            onTap: () async {
              final granted =
                  await widget.notificationService.requestExactAlarmPermission();
              if (!mounted) return;
              await _refresh();
              if (!granted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Exact alarm access is still disabled.'),
                  ),
                );
              }
            },
          ),
          _permissionTile(
            icon: Icons.accessibility_new,
            title: 'Accessibility / Study App Protection',
            subtitle: 'Required to restrict other apps during an active mission timer',
            enabled: _accessibilityEnabled,
            onTap: () => _open('openAccessibilitySettings'),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Restricted Settings Help'),
              subtitle: const Text('For sideloaded apps, Android may require Allow restricted settings before Accessibility can be enabled.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('ALLOW RESTRICTED SETTINGS'),
                  content: const Text(
                    '1. Open Accessibility Settings once.\n\n'
                    '2. Return to the Home Screen and long-press Shadow Learner. Open App info.\n\n'
                    '3. Tap the three-dot menu (⋮) and choose Allow restricted settings.\n\n'
                    '4. Return to Shadow Learner > Settings > Permissions, then enable Accessibility.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('CLOSE'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _open('openAppDetailsSettings');
                      },
                      child: const Text('OPEN APP INFO'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _permissionTile(
            icon: Icons.app_settings_alt,
            title: 'App Info & Restricted Settings',
            subtitle: 'Open Android App Info to manage restricted settings and other app permissions',
            enabled: true,
            onTap: () => _open('openAppDetailsSettings'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('REFRESH PERMISSION STATUS'),
          ),
          const SizedBox(height: 8),
          Text(
            'Some permissions cannot be switched on directly by an app. Use the Android settings screen and return here to refresh their status.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }
}
