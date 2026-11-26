import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const Color _accent = Color(0xFF00BFFF);

  static const List<_PolicySection> _sections = [
    _PolicySection('1. Information we process', [
      'Depending on the features you use, Shadow Learner may process your generated Player UID, device identifier, player name, registration/status timestamps, and phone number you choose to provide.',
      'Player progress may include level, XP, rank/title, HP, MP, study progress, mission and timetable state, rest/recovery state, screen-time totals, and related preferences.',
      'Security records may include protected-action code requests, code status and expiry/use timestamps, uninstall requests, and UID-linked audit events.',
      'If you link Telegram, the service processes your Telegram user ID, username, chat/message metadata, and pending registration or linking actions. If you share your phone contact with the bot, it processes that number for registration/linking.',
      'When enabled, Android Usage Access checks foreground app/package usage and duration. The Accessibility service reads the foreground app package identifier to enforce Study Protection. It is not designed to read message contents, passwords, or text typed into other apps.',
      'The Android app does not request Contacts, SMS, Phone, or Location permissions. A phone number may still be processed if you voluntarily share it with the Telegram bot.',
    ]),
    _PolicySection('2. Information stored on your device', [
      'Operational settings and player data are stored locally so core features can work offline. This may include player progress, timetable and mission state, protection preferences, cached public configuration, and notification/scheduling state.',
      'Clearing app storage or uninstalling the app may remove locally stored information. Cloud backup, when paired, is separate.',
    ]),
    _PolicySection('3. Cloud services and Telegram', [
      'If you register or use cloud backup, relevant account and progress records are sent to Supabase, which hosts the app backend database and processes data on the app operator’s behalf.',
      'If you use the Telegram bot, Telegram processes your bot interactions under Telegram’s own terms and privacy policy. The bot uses details you send for registration, linking, support, and account-management actions.',
      'The app may contact the GitHub Releases API to check for a newer version. This update check is not intended to send your Player UID or progress data to GitHub.',
    ]),
    _PolicySection('4. Android permissions', [
      'Internet and network state are used for cloud services and update checks. Notifications show mission reminders and system notifications. Exact alarms schedule reminders and time-based protection events.',
      'Usage Access identifies foreground app usage and duration for Screen Time and protection features. Accessibility identifies the foreground app package and enforces Study Protection while an applicable session is active; it does not inspect text or contents displayed inside other apps.',
      'Boot/time-change receivers restore scheduled reminders and protection after reboot, app update, or device time/time-zone changes. A battery-optimization exemption may be requested to help background protection and reminders run reliably.',
      'You can review or revoke special access such as Usage Access and Accessibility in Android Settings. Revoking them may disable related monitoring or protection features.',
    ]),
    _PolicySection('5. How information is used', [
      'Information is used to create and maintain your Player UID, save and restore progress, run missions and schedules, show reminders, provide Screen Time and Study Protection, verify protected-action requests, operate Telegram registration/linking, respond to support requests, maintain security, and diagnose service issues.',
    ]),
    _PolicySection('6. Sharing and sale', [
      'We do not sell your personal information. Information is shared only when needed to operate features you request (for example, with Supabase or Telegram), protect the service, comply with applicable law, or when you ask us to do so. Third-party providers have their own terms and privacy practices.',
    ]),
    _PolicySection('7. Retention and account deletion', [
      'Cloud information is retained while needed to provide your account, progress backup, security, and support features. To request deletion of cloud account data, contact oliur292007@gmail.com or @SOLO_SYSTEM_BOT and provide your Player UID.',
      'After the request is verified, an administrator can delete cloud records linked to that UID, including account, progress, UID-linked security/code records, and related Telegram/WhatsApp bot records. Shared service configuration and global allowlist records are not part of an individual UID deletion.',
      'Local device data is separate. You are responsible for clearing app local storage or uninstalling the app if you also want local information removed. If Uninstall Protection is enabled, follow the protected-uninstall process.',
      'Deletion from active cloud records does not necessarily mean immediate removal from provider-level encrypted backups or legally required records. Such copies, if any, follow provider backup/retention processes and applicable requirements.',
    ]),
    _PolicySection('8. Security', [
      'Reasonable technical and organizational measures are used to protect information, including access controls for privileged account-management operations. No internet transmission or storage system can be guaranteed completely secure. Keep your Player UID and authorization codes private.',
    ]),
    _PolicySection('9. Children’s privacy', [
      'Shadow Learner is not designed to knowingly collect personal information from children without appropriate permission or supervision. Contact us if you believe a child has provided personal information improperly.',
    ]),
    _PolicySection('10. Changes to this policy', [
      'This policy may be updated when app features, services, or legal requirements change. The latest effective date is shown in this screen and in the published policy document.',
    ]),
  ];

  Future<void> _contactEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'oliur292007@gmail.com',
      queryParameters: {'subject': 'Shadow Learner Privacy Request'},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openTelegram() async {
    await launchUrl(
      Uri.parse('https://t.me/SOLO_SYSTEM_BOT'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final panel = theme.colorScheme.surfaceContainerHighest;

    return Scaffold(
      appBar: AppBar(title: const Text('PRIVACY POLICY')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accent.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SHADOW LEARNER',
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Effective date: 26 November 2026',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text(
                  'This policy explains what information the app and its optional Telegram features process, why it is used, and the choices available to you.',
                  style: TextStyle(color: textColor, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final section in _sections)
            Card(
              color: panel,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _accent.withValues(alpha: dark ? 0.22 : 0.16),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final paragraph in section.paragraphs) ...[
                      Text(
                        paragraph,
                        style: TextStyle(
                          color: textColor,
                          height: 1.55,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 9),
                    ],
                  ],
                ),
              ),
            ),
          Card(
            color: panel,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _accent.withValues(alpha: 0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '11. Contact',
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'For privacy questions, access or deletion requests, or support, contact us. Include your Player UID for account-specific requests. Do not send passwords or one-time authorization codes.',
                    style: TextStyle(color: textColor, height: 1.5, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.email_outlined, color: _accent),
                    title: const Text('oliur292007@gmail.com'),
                    subtitle: const Text('Email support'),
                    onTap: _contactEmail,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.send_rounded, color: _accent),
                    title: const Text('@SOLO_SYSTEM_BOT'),
                    subtitle: const Text('Telegram support'),
                    onTap: _openTelegram,
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

class _PolicySection {
  final String title;
  final List<String> paragraphs;

  const _PolicySection(this.title, this.paragraphs);
}
