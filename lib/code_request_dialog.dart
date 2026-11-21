import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'security_controller.dart';
import 'supabase_service.dart';
import 'uid_manager.dart';

class CodeRequestDialog extends StatelessWidget {
  final SecurityController controller;
  final UidManager uidManager;
  final SupabaseService supabaseService;

  const CodeRequestDialog({
    super.key,
    required this.controller,
    required this.uidManager,
    required this.supabaseService,
  });

  static Future<void> show({
    required BuildContext context,
    required SecurityController controller,
    required UidManager uidManager,
    required SupabaseService supabaseService,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => CodeRequestDialog(
        controller: controller,
        uidManager: uidManager,
        supabaseService: supabaseService,
      ),
    );
  }

  Future<void> _copyCommand(BuildContext context, String command) async {
    await Clipboard.setData(ClipboardData(text: command));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telegram command copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = uidManager.uid ?? '';
    final unlockCommand = 'GIVE Unlock Code, UID = $uid';
    final uninstallCommand = 'GIVE Uninstall Code, UID = $uid';

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.send, color: Color(0xFF229ED9)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'TELEGRAM CODE REQUEST',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open the SOLO SYSTEM Telegram Bot using the Telegram account linked to this UID. Copy and send the correct command:',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 14),
            _commandTile(
              context,
              title: 'Emergency Unlock',
              command: unlockCommand,
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            _commandTile(
              context,
              title: 'Protected Uninstall',
              command: uninstallCommand,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 14),
            const Text(
              'The bot creates a request for developer approval. After approval, the code is delivered privately to your linked Telegram account. Emergency Unlock and Uninstall codes are separate and cannot be exchanged.',
              style: TextStyle(fontSize: 11, height: 1.45),
            ),
            const SizedBox(height: 8),
            const Text(
              'GitHub Actions polling may take a few minutes. Developer approval may take additional time.',
              style: TextStyle(fontSize: 11, height: 1.4, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }

  Widget _commandTile(
    BuildContext context, {
    required String title,
    required String command,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 7),
          SelectableText(
            command,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _copyCommand(context, command),
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('COPY COMMAND'),
            ),
          ),
        ],
      ),
    );
  }
}
