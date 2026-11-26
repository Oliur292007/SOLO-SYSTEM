# Shadow Learner

**A gamified self-improvement, study-planning, and digital-discipline system for Android.**

Shadow Learner turns everyday goals into a progression-based experience. Instead of treating study and personal routines as a plain checklist, it gives the user a Player profile, Quests, XP, Levels, Ranks, HP, MP, Rest mechanics, schedules, and device-level study restrictions.

The project is developed under the **Solo System** brand and created by **MD Oliur Rahman**.

> **Project identity:** Shadow Learner  
> **Developer / project brand:** Solo System  
> **Creator:** MD Oliur Rahman  
> **Platform:** Android  
> **Application ID:** `com.solosystem.shadowlearner`  
> **Current app version:** `4.1.22+133`

---

## Table of contents

- [Vision](#vision)
- [How the system works](#how-the-system-works)
- [Player progression](#player-progression)
- [HP and MP](#hp-and-mp)
- [Quests and daily missions](#quests-and-daily-missions)
- [Penalty and Night Lock](#penalty-and-night-lock)
- [Rest and recovery](#rest-and-recovery)
- [Study timetable](#study-timetable)
- [Study Timer and Study Protection](#study-timer-and-study-protection)
- [Screen Time management](#screen-time-management)
- [Notifications](#notifications)
- [Player UID, Telegram, and cloud sync](#player-uid-telegram-and-cloud-sync)
- [Security and authorization](#security-and-authorization)
- [Local data and privacy](#local-data-and-privacy)
- [Permissions](#permissions)
- [Technology](#technology)
- [Project structure](#project-structure)
- [Build and release](#build-and-release)
- [Limitations and Android notes](#limitations-and-android-notes)
- [Credits](#credits)

---

## Vision

Shadow Learner is designed around one central idea:

**Make real-life self-improvement feel like progressing through a game, while keeping the underlying goals real.**

The app connects study sessions, routines, and personal discipline to a game-inspired system:

- Complete real tasks to earn progress.
- Build a consistent study timetable.
- Complete missions before their deadlines.
- Earn XP and advance through Levels and Ranks.
- Manage HP and MP rather than ignoring rest.
- Use Study Protection to reduce distractions during focused work.
- Keep recoverable progress backed up through the cloud when the account is paired.

The game mechanics are intended to support real-world habits; they do not replace the user's actual work.

## How the system works

At a high level, the daily loop is:

1. Open Shadow Learner and review the Player dashboard, current status, Quests, and schedule.
2. Complete available daily or scheduled missions.
3. Run the Study Timer for missions that require focused study.
4. Receive the mission's applicable XP reward and update the Player's progression.
5. Manage HP and MP. If the Player needs recovery, use Short Rest or complete the sleep/wakeup routine.
6. Review notifications, timetable progress, and Screen Time information.
7. If the account is registered and paired, let Shadow Learner synchronize recoverable progress with Supabase.

Mission availability, deadlines, completion state, penalties, rest state, and timer state are handled by the app's systems. Important progress is persisted so that closing or reopening the app does not simply reset the Player's day.

## Player progression

Every user has a Player profile with a Player Name, Level, XP, total XP, study-time statistics, HP, MP, and progression title.

- XP is awarded by eligible mission completion and other supported rewards.
- XP progress contributes to automatic Level advancement.
- The required XP increases as the Player advances.
- Rank and Title are derived from the current Level.
- HP and MP capacity increase with Level.

### Rank and Title progression

| Level | Rank | Title |
|---:|---|---|
| 1–5 | E-Rank | The Awakener |
| 6–10 | D-Rank | Rookie Hunter |
| 11–20 | C-Rank | Rising Hunter |
| 21–35 | B-Rank | Elite Hunter |
| 36–50 | A-Rank | Master Hunter |
| 51–75 | S-Rank | Shadow Monarch |
| 76+ | National Level | Monarch of Shadows |

The Player's name and progression are part of the saved Player profile.

## HP and MP

HP (Health Points) and MP (Mana Points) are core Player resources.

- **HP** represents the Player's condition. Missing mandatory missions can cause HP damage.
- **MP** is a resource used by the app's study and progression mechanics.
- Maximum HP and MP scale with Player Level.
- Current values and one-time recovery/deduction events are persisted to prevent accidental duplicate application.
- HP damage history records recent damage events.

When HP reaches the critical state, the app prevents starting another mission until the Player rests. A persisted critical-HP penalty state prevents the same critical condition from repeatedly applying its penalty after every restart.

## Quests and daily missions

Quests turn the user's routine into time-aware tasks. A Quest can be upcoming, available, active, completed, skipped, missed, or locked.

### Scheduled study Quests

The user creates study entries in the weekly timetable. Each scheduled entry can define:

- Day of the week
- Subject or activity name
- Start time
- Duration
- Mandatory or optional status
- Apps allowed during that scheduled Quest
- Physical-study mode

A scheduled Quest uses its timetable entry to determine its study duration and deadline. Eligible scheduled study sessions use the Study Timer.

### Wakeup mission

- Becomes available at **5:00 AM**.
- Deadline: **8:30 AM**.
- Completing it ends the overnight lock routine.
- Missing it applies the configured wakeup-mission consequences, including the regular missed-mission penalty.
- On a first installation/initialization after the 8:30 AM deadline, the Wakeup mission is initialized as completed so that a new user is not immediately penalized for a day that began before setup.

### Sleeping mission

- Becomes available at **8:00 PM**.
- Deadline: **11:58 PM**.
- Completing it starts Long Rest and activates Night Lock.
- Missing it at its deadline also activates Night Lock as the special sleeping-mission consequence.

### Weekly special mission

Shadow Learner can provide a weekly special mission. Its schedule, description, category, completion state, and XP reward are stored as part of the weekly mission data.

### Optional missions

Optional scheduled missions are distinguished from mandatory missions. Missing an optional schedule does not trigger the standard mandatory-mission penalty.

## Penalty and Night Lock

Shadow Learner uses time-based restrictions to make mission deadlines meaningful.

- Missing a mandatory mission normally starts a **4-hour penalty**.
- The penalty countdown is based on the missed deadline and is persisted across app restarts.
- Missing the Wakeup mission has its configured wakeup consequence and penalty.
- The Sleeping mission uses its special Night Lock rule rather than the ordinary missed-mission flow.
- A critical HP condition has a separate **2-hour HP-critical penalty**.
- Optional scheduled missions do not receive the ordinary mandatory-mission penalty.

Night Lock is tied to the sleeping and wakeup routine. Completing the Sleeping mission activates it; the Wakeup routine ends it. Missing the Sleeping mission deadline also activates it, while missing Wakeup invokes its configured penalty behavior.

The app exposes the current lock state and remaining penalty time in its system status.

## Rest and recovery

Rest is a real part of the progression loop. A Player cannot start a new mission while a rest session is active, and a Player with critical HP must rest before continuing.

### Short Rest

- Short Rest is a timed recovery session.
- Recovery is applied in **10-minute intervals**.
- Each completed interval restores the configured HP and MP amount.
- The rest start time and already-applied intervals are saved, allowing recovery to be reconciled after the app is reopened.

### Long Rest

Long Rest is connected to the Sleeping and Wakeup missions.

- Completing the Sleeping mission starts Long Rest.
- The rest period ends at the next morning's **8:30 AM** Wakeup deadline, or when the Wakeup flow ends it.
- Recovery is calculated from the elapsed rest duration.
- Long Rest applies its base recovery and the configured **25% sleeping bonus**.
- Recovery events are identified and persisted so that a restart does not award the same recovery twice.

## Study timetable

The timetable is a reusable weekly plan rather than a one-day checklist.

Users can add, edit, and delete schedule entries. Entries are associated with weekdays and can include a subject, start time, duration, optional status, allowed app packages, and physical-study setting.

The timetable:

- Supplies the day's scheduled Quests.
- Tracks completion by date.
- Checks schedule validity and time overlaps.
- Supports scheduled app policies for focused Quests.
- Feeds mission reminders into the notification system.

## Study Timer and Study Protection

The Study Timer is used for timed study Quests. Study Protection connects the active study plan to Android's Accessibility Service and Usage Access capabilities.

When enabled and configured:

- Shadow Learner can detect which app is currently in the foreground.
- During a scheduled Quest with an app policy, only the apps selected for that Quest are allowed to keep the timer running.
- Physical-study mode does not grant a third-party app exception.
- Outside a custom scheduled-Quest app policy, YouTube has the app's configured special handling.
- If the user switches to an app that should pause the Quest Timer, the app uses a **10-second foreground grace period** and re-checks the destination before pausing. This avoids pausing for a brief launcher or app-transition event.
- Turning the screen off or locking the device is not treated as intentionally switching to another app.
- Returning to Shadow Learner allows the app to reconcile the timer state.
- Study Protection can redirect the user to the Home Screen when an app is disallowed by an active study or penalty policy.

The Accessibility Service is an Android system service. The user must explicitly enable it in Android Settings; Shadow Learner cannot silently grant this permission.

## Screen Time management

Shadow Learner includes a Screen Time page that reads Android UsageStats and displays daily app usage information.

The current implementation includes:

- Daily usage totals for Social Media and Games categories.
- Per-app usage information.
- Configurable daily limits supplied by the app's remote configuration.
- Category overrides and app classification support.
- Usage-limit enforcement while the monitoring service is active.
- A settings route to grant Android Usage Access.

Usage information is read from Android on the device. Usage Access is a separate Android permission from Accessibility Service and must be granted by the user.

## Notifications

The notification system handles both scheduled reminders and in-app system history.

Notification types include relevant events such as:

- Mission reminders
- Mission completion
- Mission failure
- XP rewards
- Level advancement
- Rank or Title changes
- Daily system messages
- Notification-permission confirmation

Weekly schedule reminders and the special Wakeup/Sleeping reminders are scheduled through Android notifications. If exact-alarm access is unavailable, the app can fall back to Android's inexact scheduling mode. Notification history is stored locally and included in recoverable cloud progress.

## Player UID, Telegram, and cloud sync

Shadow Learner uses a Player UID to identify a registered Player for account pairing and cloud progress.

### Telegram companion bot

The Telegram companion bot is a separate companion service. It is used for the registration and developer-approval workflows connected to a Player UID.

The intended flow is:

1. Shadow Learner initializes or displays the Player UID.
2. The user opens the official Shadow Learner Telegram companion bot and completes the registration/linking flow.
3. The bot handles registration and code-request interactions.
4. Approved authorization codes are delivered privately through Telegram.
5. The user enters the relevant code in Shadow Learner for the matching protected action.

Registration authority belongs to the Telegram bot flow; the app does not independently approve a new registration.

### Supabase cloud progress

Supabase provides the remote configuration and cloud progress backend.

When a registered Player has paired the device and the service is reachable, Shadow Learner can:

- Upload a snapshot of recoverable Player progress.
- Restore a saved snapshot to a paired installation.
- Reconcile local changes with the cloud copy.
- Retry synchronization after temporary network failures.
- Keep local progress usable when the device is offline.

The progress snapshot includes supported Player, Quest, timetable, rest, preference, and notification-history data. Authentication secrets, device-bound tokens, temporary authorization grants, and Android-owned permission state are deliberately excluded from the recoverable progress snapshot.

Cloud sync requires successful UID registration/pairing and network access. It is not a replacement for Android permission setup.

## Security and authorization

Shadow Learner provides two distinct developer-issued code flows:

### Emergency Unlock Authorization

- Requires an Emergency Unlock code.
- Temporarily disables the app's configured restrictions for the duration set by remote configuration.
- The active unlock expiry is persisted and restored after an app restart.
- It is separate from uninstall authorization.

### Uninstall Authorization

- Requires a different, one-time Uninstall Authorization code.
- A valid code authorizes the in-app uninstall route and opens the relevant Android app-information route.
- An Emergency Unlock code cannot be used as an uninstall code.

**Important Android limitation:** This is an in-app authorization flow, not an absolute Android uninstall lock. Without device-owner/device-management privileges, Android Settings can still be used to Force Stop the app, clear its data, disable Accessibility, or uninstall it outside the app's protected route. Shadow Learner does not claim to make those operating-system actions impossible.

## Local data and privacy

Shadow Learner is designed to keep its core experience available locally.

- Player progress, Quest state, rest state, timetable data, and preferences are persisted on the device.
- Cloud synchronization is used for supported recoverable progress after account pairing.
- Android UsageStats is used for the Screen Time and foreground-app policy features.
- The Accessibility Service reads app/window transition information needed to enforce the configured study policy; it is not intended to inspect the content inside other apps.
- Android permissions remain under the user's control.
- Sensitive device credentials and temporary authorization grants are not included in the cloud progress snapshot.

For exact data handling and backend configuration, consult the app's implementation and the privacy information provided within the application.

## Permissions

Depending on which features the user enables, Shadow Learner may request:

| Android capability | Why it is needed |
|---|---|
| Notifications | Mission reminders, system messages, and progress events |
| Exact alarms / scheduled notifications | More precise timetable and mission reminders; inexact scheduling may be used when exact access is unavailable |
| Accessibility Service | Foreground-app detection and enforcement of Study Protection policies |
| Usage Access | Daily Screen Time totals, app usage categories, and foreground-app monitoring |
| Network access | Supabase configuration, UID-related services, and cloud progress synchronization |

Granting a permission is always an Android system-level action. Availability and behavior can vary by Android version and device manufacturer.

## Technology

The project uses:

- **Flutter / Dart** for the Android application and user interface.
- **Kotlin** for native Android integration, including Accessibility Service and UsageStats policy enforcement.
- **SharedPreferences** for persisted local application state and native policy coordination.
- **Supabase** for remote configuration, UID-linked services, and recoverable cloud progress.
- **Telegram Bot** as the companion registration and developer-authorization channel.
- **flutter_local_notifications** and Android scheduling APIs for reminders and notification history.

The Android application package is `com.solosystem.shadowlearner`.

## Project structure

The repository is organized around the following main areas:

| Path | Responsibility |
|---|---|
| `lib/main.dart` | Application startup, theme, navigation shell, and system coordination |
| `lib/player_system.dart` | Player profile, XP, Level, Rank, Title, HP, MP, and study statistics |
| `lib/quest_system.dart` | Daily Quests, mission state, deadlines, penalties, and Night Lock |
| `lib/study_timer.dart` | Focus-session timer behavior |
| `lib/timetable_system.dart` | Weekly schedule data and validation |
| `lib/rest_system.dart` | Short Rest, Long Rest, and recovery calculations |
| `lib/notification_service.dart` | Local notifications, scheduled reminders, and notification history |
| `lib/cloud_progress_sync.dart` | Recoverable progress snapshots and Supabase synchronization |
| `lib/supabase_service.dart` | Remote configuration and Supabase service integration |
| `lib/uid_manager.dart` | Local Player UID and registration state |
| `lib/security_controller.dart` | Emergency Unlock and Uninstall Authorization validation |
| `lib/security_page.dart` | UID, code requests, security status, and authorization UI |
| `lib/screen_time_page.dart` | Screen Time dashboard and Android usage access UI |
| `android/app/src/main/kotlin/com/solosystem/shadowlearner/` | Native Android services and platform integration |

The Telegram companion bot is maintained in its own repository: [SOLO-SYSTEM-TELEGRAM-BOT](https://github.com/Oliur292007/SOLO-SYSTEM-TELEGRAM-BOT).

## Build and release

Shadow Learner is a Flutter Android project.

A local development environment needs:

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`.
- Android SDK and Android build tools.
- A configured Android signing setup for signed release APKs.
- The required project configuration and backend values for the features being tested.

Typical development commands:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The repository also contains a GitHub Actions release workflow at `.github/workflows/build-apk.yml`. It is manually dispatched and uses the repository's configured release/signing secrets. A successful CI build confirms that the workflow produced an APK; device-specific permission behavior and Android manufacturer restrictions should still be tested on a real device.

Do not commit signing keys, service-role keys, bot tokens, device tokens, or other private credentials to the repository.

## Limitations and Android notes

- Study Protection depends on the user enabling Android Accessibility Service and, where required, Usage Access.
- Android may restrict background services, alarms, and usage reporting differently across manufacturers and OS versions.
- Exact notification timing depends on Android alarm permissions and battery-management behavior.
- The in-app uninstall authorization route does not prevent uninstalling from Android Settings.
- Cloud restore and synchronization require a registered/paired Player UID, a paired device, and a working network connection.
- Screen Time totals and enforcement depend on Android UsageStats availability and the configured app categories and limits.

These constraints are stated so that the app's capabilities are not confused with operating-system privileges it does not have.

## Credits

**Created by:** MD Oliur Rahman  
**Developed under:** Solo System  
**Application:** Shadow Learner  
**Repository:** [Oliur292007/SOLO-SYSTEM](https://github.com/Oliur292007/SOLO-SYSTEM)

Shadow Learner is an independently developed project focused on turning study, routines, and personal discipline into a structured progression system.
