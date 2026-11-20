import 'package:flutter/material.dart';

import 'security_controller.dart';

class CodeEntryDialog extends StatefulWidget {
  final SecurityController controller;
  final String codeType; // 'emergency_unlock' or 'uninstall'

  const CodeEntryDialog({
    super.key,
    required this.controller,
    required this.codeType,
  });

  static Future<bool?> show({
    required BuildContext context,
    required SecurityController controller,
    required String codeType,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CodeEntryDialog(
        controller: controller,
        codeType: codeType,
      ),
    );
  }

  @override
  State<CodeEntryDialog> createState() => _CodeEntryDialogState();
}

class _CodeEntryDialogState extends State<CodeEntryDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Enter code');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = widget.codeType == 'emergency_unlock'
        ? await widget.controller.validateEmergencyUnlock(code)
        : await widget.controller.validateUninstall(code);

    if (!mounted) return;

    setState(() {
      _loading = false;
      _error = result.success ? null : result.error;
    });

    if (result.success && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmergency = widget.codeType == 'emergency_unlock';
    final title = isEmergency ? 'EMERGENCY UNLOCK' : 'UNINSTALL AUTHORIZATION';
    final hint = isEmergency ? 'EMU-XXXX-XXXX' : 'UNI-XXXX-XXXX';
    final minutes = widget.controller.supabaseService.emergencyUnlockMinutes;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isEmergency ? Icons.lock_open : Icons.delete_forever,
            color: isEmergency ? Colors.green.shade700 : Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEmergency
                ? 'Enter emergency unlock code from Help Center.\nThis will unblock restricted apps for $minutes minutes.'
                : 'Enter uninstall authorization code from Help Center.\nThis will enable app uninstall.',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_loading,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
              border: const OutlineInputBorder(),
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('VERIFY'),
        ),
      ],
    );
  }
}