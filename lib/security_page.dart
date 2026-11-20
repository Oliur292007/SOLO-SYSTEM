import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'code_entry_dialog.dart';
import 'code_request_dialog.dart';
import 'security_controller.dart';
import 'supabase_service.dart';
import 'uid_manager.dart';

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
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _copyUid() async {
    await Clipboard.setData(
      ClipboardData(text: widget.uidManager.uid ?? ''),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('UID copied'), duration: Duration(seconds: 1)),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.supabaseService.isOnline
              ? 'Synced with server'
              : 'Still offline. Try later.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uidManager.uid ?? '—';
    final isRegistered = widget.controller.isRegistered;
    final isOnline = widget.controller.isOnline;
    final emergencyActive = widget.controller.isEmergencyUnlockActive;
    final emergencyRemaining = widget.controller.emergencyUnlockRemaining;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SECURITY'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
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
                colors: [
                  Colors.blue.shade900,
                  Colors.cyan.shade900,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyan.withValues(alpha: 0.2),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fingerprint, color: Colors.cyan, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'PLAYER UID',
                      style: TextStyle(
                        color: Colors.cyan,
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
                      child: Text(
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
                      icon: const Icon(Icons.copy,
                          color: Colors.cyan, size: 18),
                      onPressed: _copyUid,
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
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_open, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMERGENCY UNLOCK ACTIVE',
                          style: TextStyle(
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Restricted apps unlocked for '
                          '${emergencyRemaining.inMinutes}:'
                          '${emergencyRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.green.shade700,
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
          const _SectionLabel('CODE ACTIONS'),
          const SizedBox(height: 8),

          _ActionTile(
            icon: Icons.vpn_key,
            iconColor: Colors.cyan.shade700,
            title: 'Generate Unlock / Uninstall Code',
            subtitle: isRegistered
                ? 'Request codes from Help Center'
                : 'Requires registration',
            enabled: isRegistered && !widget.controller.isGeneratingCode,
            onTap: _handleRequestCodes,
          ),

          const SizedBox(height: 8),

          _ActionTile(
            icon: Icons.lock_open,
            iconColor: Colors.green.shade700,
            title: 'Enter Emergency Unlock Code',
            subtitle: 'Unblock restricted apps for 30 minutes',
            enabled: isRegistered,
            onTap: _handleEmergencyUnlock,
          ),

          const SizedBox(height: 8),

          _ActionTile(
            icon: Icons.delete_forever,
            iconColor: Colors.red.shade700,
            title: 'Enter Uninstall Code',
            subtitle: 'Authorize app uninstall',
            enabled: isRegistered,
            onTap: _handleUninstallCode,
          ),

          const SizedBox(height: 24),

          // ============ INFO ============
          const _SectionLabel('HOW IT WORKS'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoStep(
                  number: '1',
                  text: 'Tap "Generate Unlock / Uninstall Code".',
                ),
                _InfoStep(
                  number: '2',
                  text: 'Send your UID to the WhatsApp number shown.',
                ),
                _InfoStep(
                  number: '3',
                  text:
                      'Developer replies with EMU-XXXX-XXXX and UNI-XXXX-XXXX codes.',
                ),
                _InfoStep(
                  number: '4',
                  text:
                      'Enter the code here to unlock apps or enable uninstall.',
                ),
                _InfoStep(
                  number: '5',
                  text: 'Codes expire 30 minutes after generation.',
                  isLast: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ============ SUPPORT ============
          const _SectionLabel('HELP CENTER'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble, color: Colors.green.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WhatsApp Support',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.supabaseService.whatsappNumber,
                        style: TextStyle(
                          color: Colors.green.shade900,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: Colors.grey,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTile({
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled ? Colors.grey.shade300 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: enabled ? iconColor : Colors.grey,
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
                      color: enabled ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: enabled ? Colors.grey.shade700 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: enabled ? Colors.grey : Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final String number;
  final String text;
  final bool isLast;

  const _InfoStep({
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
              color: Colors.cyan.shade700,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}