import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'security_controller.dart';
import 'uid_manager.dart';

class CodeRequestDialog extends StatelessWidget {
  final SecurityController controller;
  final UidManager uidManager;

  const CodeRequestDialog({
    super.key,
    required this.controller,
    required this.uidManager,
  });

  static Future<void> show({
    required BuildContext context,
    required SecurityController controller,
    required UidManager uidManager,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => CodeRequestDialog(
        controller: controller,
        uidManager: uidManager,
      ),
    );
  }

  Future<void> _openTelegram(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse('https://t.me/Solo_Sysyem_Bot'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Telegram. Open @Solo_Sysyem_Bot manually.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = uidManager.uid ?? '—';

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
              'Your linked UID is already saved by the Shadow Learner companion bot. '
              'You do not need to copy a command or type your UID again.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 10),
            SelectableText(
              'Linked UID: $uid',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 14),
            _requestTypeTile(
              title: 'Emergency Unlock',
              description: 'In the bot menu, press Emergency Unlock.',
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            _requestTypeTile(
              title: 'Uninstall Authorization',
              description: 'In the bot menu, press Uninstall Authorization.',
              color: Colors.redAccent,
            ),
            const SizedBox(height: 14),
            const Text(
              'The bot sends your request for Solo System administrator approval. '
              'After approval, the code is delivered privately to your linked Telegram account. '
              'These two codes are separate and cannot be exchanged.',
              style: TextStyle(fontSize: 11, height: 1.45),
            ),
            const SizedBox(height: 8),
            const Text(
              'GitHub Actions polling may take a few minutes. Administrator approval may take additional time.',
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
        FilledButton.icon(
          onPressed: () => _openTelegram(context),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('OPEN TELEGRAM BOT'),
        ),
      ],
    );
  }

  Widget _requestTypeTile({
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
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
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(fontSize: 11, height: 1.35)),
        ],
      ),
    );
  }
}
