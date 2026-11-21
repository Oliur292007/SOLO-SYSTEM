import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'code_entry_dialog.dart';
import 'code_request_dialog.dart';
import 'security_controller.dart';
import 'supabase_service.dart';
import 'uid_manager.dart';

// Reuse the SystemColors from main.dart
import 'main.dart' show SystemColors;

const MethodChannel _studyRestrictionChannel =
    MethodChannel('solo_system/app_restriction');


class SecurityPage extends StatefulWidget {
  final SecurityController controller;
  final UidManager uidManager;
  final SupabaseService supabaseService;

  const SecurityPage({
    super.key,
    required this.controller,
    required this.uidManager,
    required this.supabaseService,
  });

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  bool _initialSyncDone = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
    _autoSync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _autoSync() async {
    if (_initialSyncDone) return;
    _initialSyncDone = true;
    await widget.controller.forceSync();
  }

  Future<void> _copyUid() async {
    await Clipboard.setData(
      ClipboardData(text: widget.uidManager.uid ?? ''),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('UID copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleRequestCodes() async {
    await CodeRequestDialog.show(
      context: context,
      controller: widget.controller,
      uidManager: widget.uidManager,
      supabaseService: widget.supabaseService,
    );
  }

  Future<void> _openStudyProtectionSettings() async {
    try {
      await _studyRestrictionChannel.invokeMethod<void>(
        'openAccessibilitySettings',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Accessibility Settings: ${error.message}')),
      );
    }
  }

  Future<void> _handleEmergencyUnlock() async {
    final success = await CodeEntryDialog.show(
      context: context,
      controller: widget.controller,
      codeType: 'emergency_unlock',
    );
    if (success == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Emergency unlock active for '
            '${widget.supabaseService.emergencyUnlockMinutes} minutes',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _handleUninstallCode() async {
    final success = await CodeEntryDialog.show(
      context: context,
      controller: widget.controller,
      codeType: 'uninstall',
    );
    if (success == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uninstall authorized. You may uninstall the app now.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _handleForceSync() async {
    await widget.controller.forceSync();

    if (!mounted) return;

    final isOnline = widget.supabaseService.isOnline;
    final isRegistered = widget.controller.isRegistered;
    final uid = widget.uidManager.uid ?? 'NO UID';
    final error = SupabaseService.lastRegistrationError ?? 'None';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SYNC DIAGNOSTIC'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _diagRow('UID', uid),
              _diagRow('Registered', '$isRegistered'),
              _diagRow('Online', '$isOnline'),
              _diagRow('Supabase client',
                  widget.supabaseService.client != null ? 'OK' : 'NULL'),
              _diagRow('Registration authority', 'Telegram Bot'),
              _diagRow('Config count',
                  widget.supabaseService.config.length.toString()),
              _diagRow('Whitelist count',
                  widget.supabaseService.whitelist.length.toString()),
              const Divider(),
              _diagRow('Error', error),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(
                    fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = widget.uidManager.uid ?? '—';
    final isRegistered = widget.controller.isRegistered;
    final isOnline = widget.controller.isOnline;
    final emergencyActive = widget.controller.isEmergencyUnlockActive;
    final emergencyRemaining = widget.controller.emergencyUnlockRemaining;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.panel,
        foregroundColor: c.text,
        elevation: 0,
        title: Text(
          'SECURITY',
          style: TextStyle(
            color: c.cyan,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.sync, color: c.cyan),
            onPressed: _handleForceSync,
            tooltip: 'Force sync',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // ============ UID CARD ============
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [Color(0xFF102B50), Color(0xFF091426)]
                    : const [Color(0xFF0077B6), Color(0xFF0096C7)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.blue.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: c.blue.withValues(alpha: 0.15),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fingerprint, color: c.cyan, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'PLAYER UID',
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    _statusChip(isRegistered, isOnline),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        uid,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, color: c.cyan, size: 18),
                      onPressed: _copyUid,
                      tooltip: 'Copy UID',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isRegistered
                      ? 'Registered with SOLO SYSTEM servers.'
                      : 'Not registered — connect to internet.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ============ EMERGENCY UNLOCK STATUS ============
          if (emergencyActive)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_open, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMERGENCY UNLOCK ACTIVE',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Restricted apps unlocked for '
                          '${emergencyRemaining.inHours.toString().padLeft(2, '0')}:'
                          '${emergencyRemaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
                          '${emergencyRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ============ ACTIONS ============
          _SectionLabel(text: 'CODE ACTIONS', color: c.muted),
          const SizedBox(height: 8),

          _ActionTile(
            colors: c,
            icon: Icons.vpn_key,
            iconColor: c.cyan,
            title: 'Generate Unlock / Uninstall Code',
            subtitle: isRegistered
                ? 'Request codes from Help Center'
                : 'Requires registration',
            enabled: isRegistered && !widget.controller.isGeneratingCode,
            onTap: _handleRequestCodes,
          ),

          const SizedBox(height: 8),

          _ActionTile(
            colors: c,
            icon: Icons.shield,
            iconColor: Colors.cyanAccent,
            title: 'Enable Study App Protection',
            subtitle: 'Turn on SOLO SYSTEM Study Protection in Android Accessibility Settings',
            enabled: true,
            onTap: _openStudyProtectionSettings,
          ),

          const SizedBox(height: 8),

          _ActionTile(
            colors: c,
            icon: Icons.lock_open,
            iconColor: Colors.green,
            title: 'Enter Emergency Unlock Code',
            subtitle: 'Unblock restricted apps for 60 minutes',
            enabled: isRegistered,
            onTap: _handleEmergencyUnlock,
          ),

          const SizedBox(height: 8),

          _ActionTile(
            colors: c,
            icon: Icons.delete_forever,
            iconColor: Colors.redAccent,
            title: 'Enter Uninstall Code',
            subtitle: 'Authorize app uninstall',
            enabled: isRegistered,
            onTap: _handleUninstallCode,
          ),

          const SizedBox(height: 24),

          // ============ INFO ============
          _SectionLabel(text: 'HOW IT WORKS', color: c.muted),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoStep(
                  colors: c,
                  number: '1',
                  text: 'Tap "Generate Unlock / Uninstall Code".',
                ),
                _InfoStep(
                  colors: c,
                  number: '2',
                  text: 'Send the matching GIVE command to the SOLO SYSTEM Telegram Bot from your linked Telegram account.',
                ),
                _InfoStep(
                  colors: c,
                  number: '3',
                  text:
                      'The Bot sends your request for developer approval, then privately delivers the approved code.',
                ),
                _InfoStep(
                  colors: c,
                  number: '4',
                  text:
                      'Enter the code here to unlock apps or enable uninstall.',
                ),
                _InfoStep(
                  colors: c,
                  number: '5',
                  text: 'Emergency Unlock and Protected Uninstall require separate codes.',
                  isLast: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ============ TELEGRAM SUPPORT ============
          _SectionLabel(text: 'TELEGRAM BOT', color: c.muted),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF229ED9).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF229ED9).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.send, color: Color(0xFF229ED9), size: 27),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Use the SOLO SYSTEM Telegram Bot from the Telegram account linked to this UID. Code requests require developer approval and are delivered privately by the Bot.',
                    style: TextStyle(color: c.text, fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _statusChip(bool registered, bool online) {
    final Color color;
    final String label;

    if (registered && online) {
      color = Colors.greenAccent;
      label = 'ONLINE';
    } else if (registered && !online) {
      color = Colors.orangeAccent;
      label = 'OFFLINE';
    } else {
      color = Colors.redAccent;
      label = 'PENDING';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SHARED SMALL WIDGETS
// ============================================================

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: color,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final SystemColors colors;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTile({
    required this.colors,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? colors.blue.withValues(alpha: 0.35)
                : colors.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (enabled ? iconColor : colors.muted)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: enabled ? iconColor : colors.muted,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: enabled ? colors.text : colors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: enabled ? colors.muted : colors.divider,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final SystemColors colors;
  final String number;
  final String text;
  final bool isLast;

  const _InfoStep({
    required this.colors,
    required this.number,
    required this.text,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colors.cyan,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}