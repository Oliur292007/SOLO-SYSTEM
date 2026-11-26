# Shadow Learner — Privacy Policy

**Effective date: 26 November 2026**

Shadow Learner (also referred to as SOLO SYSTEM) is a personal productivity and study-protection app. This policy explains what information the app and its optional Telegram registration/support features process, why it is used, and the choices available to you.

## 1. Information we process

Depending on the features you use, Shadow Learner may process:

- **Account and device details:** your generated Player UID, device identifier, player name, registration/status timestamps, and the phone number you choose to provide for registration or account support.
- **Player progress:** level, XP, rank/title, HP, MP, study progress, mission and timetable state, rest/recovery state, screen-time totals, and related app preferences needed to back up and restore your progress.
- **Security and authorization records:** protected-action code requests, code status and expiry/use timestamps, uninstall requests, and security/audit events associated with your UID.
- **Telegram linking details (optional):** Telegram user ID, username, chat ID/message metadata, and pending registration/linking actions. If you share your phone contact with the Telegram bot, the bot processes that phone number for registration/linking.
- **Device activity needed for protection:** when you enable Android Usage Access, the app checks foreground app/package usage and usage duration to support screen-time monitoring. When you enable the Accessibility service, it reads the foreground app's package identifier to enforce your configured Study Protection rules. The service is not designed to read message contents, passwords, or text typed into other apps.

The Android app does not request the Contacts, SMS, Phone, or Location permissions. A phone number can still be processed if you voluntarily share it with the Telegram bot.

## 2. Information stored on your device

The app stores operational settings and player data locally so core features can work and remain available when offline. This can include your player profile/progress, timetable and mission state, protection preferences, cached public configuration, and notification/scheduling state. Clearing app storage or uninstalling the app may remove locally stored information. Cloud backup, if paired, is separate.

## 3. Cloud services and Telegram

If you register or use cloud backup, relevant account and progress records are sent to **Supabase**, which hosts the app's backend database and processes the data on the app operator's behalf.

If you use the Telegram bot, Telegram processes your bot interactions under Telegram's own terms and privacy policy. The bot uses the details you send to complete registration, linking, support, and account-management actions.

The app may contact the GitHub Releases API to check whether a newer app version is available. This update check is not intended to send your Player UID or progress data to GitHub.

## 4. Android permissions and how they are used

- **Internet / network state:** connect to cloud services and check for app updates.
- **Notifications:** show mission reminders and system notifications.
- **Exact alarms:** schedule reminders and time-based protection events.
- **Usage Access:** identify foreground app usage and calculate usage duration for Screen Time and protection features.
- **Accessibility service:** identify the foreground app package and enforce Study Protection while an applicable session is active. It does not inspect the text or contents displayed inside other apps.
- **Boot completed / time-change receivers:** restore scheduled reminders and protection after a reboot, app update, or device time/time-zone change.
- **Battery-optimization exemption request:** help Android keep scheduled background protection and reminders running reliably.

You choose whether to grant special access such as Usage Access and Accessibility. You can review or revoke these permissions in Android Settings. Revoking them can disable the related protection or monitoring features.

## 5. How information is used

Information is used to:
- create and maintain your Player UID registration;
- save and restore your progress across devices;
- run missions, schedules, reminders, Screen Time, and Study Protection;
- verify protected-action requests and prevent unauthorized use;
- operate Telegram registration/linking and respond to support requests;
- diagnose service issues, maintain security, and improve reliability.

## 6. Sharing and sale

We do not sell your personal information. We share information only when needed to operate the features you request (for example, with Supabase or Telegram), to protect the service, to comply with applicable law, or when you ask us to do so. Third-party providers process information under their own terms and privacy practices.

## 7. Retention and account deletion

Cloud information is retained while it is needed to provide your account, progress backup, security, and support features. You may request deletion of your cloud account data by contacting **oliur292007@gmail.com** or the support Telegram account **@SOLO_SYSTEM_BOT** and providing your Player UID.

After the request is verified, an administrator can delete the cloud records linked to that UID, including its account, progress, UID-linked security/code records, and related Telegram/WhatsApp bot records. Shared service configuration and global allowlist records are not part of an individual UID deletion.

**Local device data is separate.** You are responsible for clearing the app's local storage or uninstalling the app from your device if you also want local information removed. If Uninstall Protection is enabled, follow the app's protected-uninstall process.

Deletion from active cloud records does not necessarily mean immediate removal from provider-level encrypted backups or legally required records; such copies, if any, are retained only according to the provider's backup/retention processes and applicable requirements.

## 8. Security

Reasonable technical and organizational measures are used to protect information, including access controls for privileged account-management operations. No internet transmission or storage system can be guaranteed to be completely secure. Keep your Player UID and any authorization codes private, and do not share one-time codes with anyone.

## 9. Children's privacy

Shadow Learner is not designed to knowingly collect personal information from children without appropriate permission or supervision. If you believe a child has provided personal information improperly, contact us so we can review the request.

## 10. Changes to this policy

This policy may be updated when app features, services, or legal requirements change. The latest effective date will be shown at the top of this document and in the app's Privacy Policy screen.

## 11. Contact

For privacy questions, access or deletion requests, or support:

- **Email:** [oliur292007@gmail.com](mailto:oliur292007@gmail.com)
- **Telegram:** [@SOLO_SYSTEM_BOT](https://t.me/SOLO_SYSTEM_BOT)

Please include your Player UID when asking about account-specific data. Do not send passwords or one-time authorization codes.
