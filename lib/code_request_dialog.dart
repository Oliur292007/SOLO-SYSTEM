import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'security_controller.dart';
import 'supabase_service.dart';
import 'uid_manager.dart';

class CodeRequestDialog extends StatefulWidget {
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
      barrierDismissible: false,
      builder: (_) => CodeRequestDialog(
        controller: controller,
        uidManager: uidManager,
        supabaseService: supabaseService,
      ),
    );
  }

  @override
  State<CodeRequestDialog> createState() => _CodeRequestDialogState();
}

class _CodeRequestDialogState extends State<CodeRequestDialog> {
  bool _requested = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _autoRequest();
  }

  Future<void> _autoRequest() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await widget.controller.requestCodes();

    if (!mounted) return;

    setState(() {
      _loading = false;
      _requested = ok;
      _error = ok ? null : widget.controller.lastError;
    });
  }

  Future<void> _openWhatsApp() async {
    final number = widget.supabaseService.whatsappNumber.replaceAll('+', '');
    final uid = widget.uidManager.uid ?? 'UNKNOWN';
    final message = Uri.encodeComponent(
      'Hello, I need unlock code for SOLO SYSTEM.\n\n'
      'UID: $uid\n'
      'Request: Emergency Unlock / Uninstall Code',
    );
    final url = 'https://wa.me/$number?text=$message';

    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (_) {}

    if (!mounted) return;
    _showSnack(
      'Opening WhatsApp... If not opened, link copied.',
      Colors.blue,
    );
  }

  Future<void> _copyUid() async {
    final uid = widget.uidManager.uid ?? '';
    await Clipboard.setData(ClipboardData(text: uid));
    if (!mounted) return;
    _showSnack('UID copied to clipboard', Colors.green);
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final whatsapp = widget.supabaseService.whatsappNumber;
    final uid = widget.uidManager.uid ?? '—';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.security, color: Colors.cyan.shade700),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'CODE REQUEST',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Text(
                'Generating request...',
                textAlign: TextAlign.center,
              ),
            ] else if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _autoRequest,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('RETRY'),
                ),
              ),
            ] else if (_requested) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Request generated. Contact Help Center to receive your codes.',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'YOUR UID',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        uid,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: _copyUid,
                    tooltip: 'Copy UID',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'CONTACT HELP CENTER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.chat_bubble,
                            color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          whatsapp,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Send your UID to this WhatsApp number. The developer will reply with:',
                      style: TextStyle(fontSize: 11, height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '•  EMU-XXXX-XXXX  (emergency unlock, 30 min)\n'
                      '•  UNI-XXXX-XXXX  (uninstall authorization)',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openWhatsApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('OPEN WHATSAPP'),
                ),
              ),
            ],
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
}