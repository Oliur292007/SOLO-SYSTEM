import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'player_system.dart';
import 'quest_system.dart';
import 'study_timer.dart';
import 'timetable_system.dart';
import 'timetable_page.dart';
import 'rest_system.dart';
import 'uid_manager.dart';
import 'cloud_progress_sync.dart';
import 'supabase_service.dart';
import 'security_controller.dart';
import 'security_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final player = PlayerSystem();
  final timetableSystem = TimetableSystem();

  final restSystem = RestSystem(player: player);

  final questSystem = QuestSystem(
    timetableSystem: timetableSystem,
    restSystem: restSystem,
  );

  final studyTimer = StudyTimer();

  // UID Manager
  final uidManager = UidManager();
  await uidManager.initialize();

  // Supabase Service
  final supabaseService = SupabaseService(uidManager: uidManager);
  await supabaseService.initialize();

  // Telegram Bot is the only authority allowed to register a UID.
  // The app must never create a server account on its own.
  final cloudProgressSync = CloudProgressSync(
    uidManager: uidManager,
    supabaseService: supabaseService,
  );
  await cloudProgressSync.initialize();

  // Security Controller
  final securityController = SecurityController(
    uidManager: uidManager,
    supabaseService: supabaseService,
  );
  await securityController.initialize();

  // Attach UID to player
  player.attachUid(uidManager.uid, uidManager.isRegistered);

  runApp(
    SoloSystemApp(
      player: player,
      questSystem: questSystem,
      studyTimer: studyTimer,
      timetableSystem: timetableSystem,
      restSystem: restSystem,
      uidManager: uidManager,
      supabaseService: supabaseService,
      securityController: securityController,
      cloudProgressSync: cloudProgressSync,
    ),
  );
}

// ============================================================
// THEME TOKENS
// ============================================================

@immutable
class SystemColors extends ThemeExtension<SystemColors> {
  final Color bg;
  final Color panel;
  final Color blue;
  final Color cyan;
  final Color muted;
  final Color text;
  final Color divider;
  final Color barTrack;

  const SystemColors({
    required this.bg,
    required this.panel,
    required this.blue,
    required this.cyan,
    required this.muted,
    required this.text,
    required this.divider,
    required this.barTrack,
  });

  static const dark = SystemColors(
    bg: Color(0xFF050B18),
    panel: Color(0xFF0B1930),
    blue: Color(0xFF00BFFF),
    cyan: Color(0xFF00E5FF),
    muted: Color(0xFF8295B3),
    text: Colors.white,
    divider: Color(0xFF24354C),
    barTrack: Color(0xFF24354C),
  );

  static const light = SystemColors(
    bg: Color(0xFFF1F5FA),
    panel: Colors.white,
    blue: Color(0xFF0077B6),
    cyan: Color(0xFF0096C7),
    muted: Color(0xFF5A6B85),
    text: Color(0xFF0B1930),
    divider: Color(0xFFD6E0EC),
    barTrack: Color(0xFFD6E0EC),
  );

  static SystemColors of(BuildContext context) =>
      Theme.of(context).extension<SystemColors>() ?? dark;

  @override
  SystemColors copyWith({
    Color? bg,
    Color? panel,
    Color? blue,
    Color? cyan,
    Color? muted,
    Color? text,
    Color? divider,
    Color? barTrack,
  }) {
    return SystemColors(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      blue: blue ?? this.blue,
      cyan: cyan ?? this.cyan,
      muted: muted ?? this.muted,
      text: text ?? this.text,
      divider: divider ?? this.divider,
      barTrack: barTrack ?? this.barTrack,
    );
  }

  @override
  SystemColors lerp(ThemeExtension<SystemColors>? other, double t) {
    if (other is! SystemColors) return this;
    return SystemColors(
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      text: Color.lerp(text, other.text, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      barTrack: Color.lerp(barTrack, other.barTrack, t)!,
    );
  }
}

class SoloSystemApp extends StatefulWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;
  final StudyTimer studyTimer;
  final TimetableSystem timetableSystem;
  final RestSystem restSystem;
  final UidManager uidManager;
  final SupabaseService supabaseService;
  final SecurityController securityController;
  final CloudProgressSync cloudProgressSync;

  const SoloSystemApp({
    super.key,
    required this.player,
    required this.questSystem,
    required this.studyTimer,
    required this.timetableSystem,
    required this.restSystem,
    required this.uidManager,
    required this.supabaseService,
    required this.securityController,
    required this.cloudProgressSync,
  });

  @override
  State<SoloSystemApp> createState() => _SoloSystemAppState();
}

class _SoloSystemAppState extends State<SoloSystemApp> {
  bool isDarkMode = true;
  String appVersionLabel = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        appVersionLabel = info.version;
      });
    } catch (_) {
      // Keep a readable fallback if platform package metadata is unavailable.
    }
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isDarkMode = prefs.getBool('dark_mode') ?? true;
    });
  }

  Future<void> _changeTheme(bool value) async {
    setState(() {
      isDarkMode = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SOLO SYSTEM',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: SystemColors.light.bg,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0077B6),
          secondary: Color(0xFF0096C7),
          surface: Colors.white,
        ),
        extensions: const <ThemeExtension<dynamic>>[SystemColors.light],
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: SystemColors.dark.bg,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00BFFF),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF0B1930),
        ),
        extensions: const <ThemeExtension<dynamic>>[SystemColors.dark],
        useMaterial3: true,
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: SystemHome(
        player: widget.player,
        questSystem: widget.questSystem,
        isDarkMode: isDarkMode,
        onDarkModeChanged: _changeTheme,
        studyTimer: widget.studyTimer,
        timetableSystem: widget.timetableSystem,
        restSystem: widget.restSystem,
        uidManager: widget.uidManager,
        supabaseService: widget.supabaseService,
        securityController: widget.securityController,
        cloudProgressSync: widget.cloudProgressSync,
        appVersionLabel: appVersionLabel,
      ),
    );
  }
}

class SystemHome extends StatefulWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;
  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final StudyTimer studyTimer;
  final TimetableSystem timetableSystem;
  final RestSystem restSystem;
  final UidManager uidManager;
  final SupabaseService supabaseService;
  final SecurityController securityController;
  final CloudProgressSync cloudProgressSync;
  final String appVersionLabel;

  const SystemHome({
    super.key,
    required this.player,
    required this.questSystem,
    required this.isDarkMode,
    required this.onDarkModeChanged,
    required this.studyTimer,
    required this.timetableSystem,
    required this.restSystem,
    required this.uidManager,
    required this.supabaseService,
    required this.securityController,
    required this.cloudProgressSync,
    required this.appVersionLabel,
  });

  @override
  State<SystemHome> createState() => _SystemHomeState();
}

class _SystemHomeState extends State<SystemHome> with WidgetsBindingObserver {
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSystems();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.player.removeListener(_onLocalProgressChanged);
    widget.questSystem.removeListener(_onLocalProgressChanged);
    widget.studyTimer.removeListener(_onLocalProgressChanged);
    widget.timetableSystem.removeListener(_onLocalProgressChanged);
    widget.restSystem.removeListener(_onLocalProgressChanged);
    widget.cloudProgressSync.dispose();
    super.dispose();
  }

  void _onLocalProgressChanged() {
    widget.cloudProgressSync.scheduleSync();
  }

  Future<void> _reloadSystemsFromLocalStorage() async {
    await widget.player.loadPlayer();
    await widget.restSystem.loadRest();
    await widget.timetableSystem.loadTimetable();
    await widget.questSystem.loadQuests();
    await widget.studyTimer.loadTimer();
    widget.player.attachUid(widget.uidManager.uid, widget.uidManager.isRegistered);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.securityController.refreshEmergencyUnlock());
      if (widget.cloudProgressSync.isPaired) _syncCloudAndRefresh();
    } else if (state == AppLifecycleState.paused &&
        widget.cloudProgressSync.isPaired) {
      unawaited(widget.cloudProgressSync.syncNow());
    }
  }

  Future<void> _syncCloudAndRefresh() async {
    final result = await widget.cloudProgressSync.syncNow();
    if (result.status == CloudSyncStatus.restored && mounted) {
      await _reloadSystemsFromLocalStorage();
    }
  }

  Future<void> _loadSystems() async {
    await widget.player.loadPlayer();
    await widget.restSystem.loadRest();
    await widget.timetableSystem.loadTimetable();
    await widget.questSystem.loadQuests();
    await widget.studyTimer.loadTimer();

    // Re-attach UID (player.loadPlayer may reset it from prefs)
    widget.player.attachUid(
      widget.uidManager.uid,
      widget.uidManager.isRegistered,
    );

    if (widget.cloudProgressSync.isPaired) {
      final result = await widget.cloudProgressSync.syncNow();
      if (result.status == CloudSyncStatus.restored) {
        await _reloadSystemsFromLocalStorage();
      }
    }

    widget.player.addListener(_onLocalProgressChanged);
    widget.questSystem.addListener(_onLocalProgressChanged);
    widget.studyTimer.addListener(_onLocalProgressChanged);
    widget.timetableSystem.addListener(_onLocalProgressChanged);
    widget.restSystem.addListener(_onLocalProgressChanged);
    if (widget.cloudProgressSync.isPaired) {
      widget.cloudProgressSync.startAutoSync();
    }

    // Show the registration / cloud-recovery prompt until this device is paired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.cloudProgressSync.isPaired) {
        _showRegistrationPrompt();
      }
    });
  }

  Future<void> _showRegistrationPrompt() async {
    if (!mounted || widget.cloudProgressSync.isPaired) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('WELCOME TO SOLO SYSTEM'),
        content: Text(
          'Your Player UID:\n${widget.uidManager.uid ?? '—'}\n\n'
          'Complete your Telegram registration, or retrieve your existing '
          'player progress from the cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('LATER'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showRetrieveProgressDialog();
            },
            child: const Text('RETRIEVE PROGRESS'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final uid = widget.uidManager.uid ?? '';
              final command =
                  'REG. UID: $uid, USER: +8801XXXXXXXXX';
              final uri = Uri.parse(
                'https://t.me/Solo_Sysyem_Bot?text=${Uri.encodeComponent(command)}',
              );
              final opened = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (!opened && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not open Telegram. Open @Solo_Sysyem_Bot manually.',
                    ),
                  ),
                );
              }
            },
            child: const Text('COMPLETE REGISTRATION'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRetrieveProgressDialog() async {
    final uidController = TextEditingController(
      text: widget.uidManager.uid ?? '',
    );
    final tokenController = TextEditingController();
    bool isClaiming = false;

    final claimed = await showDialog<bool>(
      context: context,
      barrierDismissible: !isClaiming,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('RETRIEVE YOUR PROGRESS'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'After registration, the Telegram Bot sends a one-time '
                  '10-minute device pairing token. Paste it below.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: uidController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'SOLO UID',
                    hintText: 'SOLO-XXXX-XXXX-XXXX',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Telegram pairing token',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isClaiming
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: isClaiming
                  ? null
                  : () async {
                      final uid = uidController.text.trim().toUpperCase();
                      final token = tokenController.text.trim();
                      if (uid.isEmpty || token.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter both UID and pairing token.'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => isClaiming = true);
                      final success = await widget.cloudProgressSync
                          .claimPairingToken(token, uidOverride: uid);
                      if (!dialogContext.mounted) return;
                      if (success) {
                        Navigator.pop(dialogContext, true);
                      } else {
                        setDialogState(() => isClaiming = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Pairing failed: ${widget.cloudProgressSync.lastPairingError ?? 'Unknown error'}. '
                              'Please request a fresh token if expired.',
                            ),
                          ),
                        );
                      }
                    },
              child: isClaiming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('PAIR DEVICE'),
            ),
          ],
        ),
      ),
    );

    uidController.dispose();
    tokenController.dispose();

    if (claimed == true && mounted) {
      widget.cloudProgressSync.startAutoSync();
      final result = await widget.cloudProgressSync.syncNow();
      await _reloadSystemsFromLocalStorage();
      if (!mounted) return;
      final message = result.status == CloudSyncStatus.restored
          ? 'Cloud progress restored successfully.'
          : result.status == CloudSyncStatus.synced
              ? 'Device paired. Your current progress is now backed up.'
              : 'Device paired, but cloud sync needs attention: ${result.message ?? result.status.name}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.player,
        widget.questSystem,
        widget.studyTimer,
        widget.restSystem,
        widget.timetableSystem,
        widget.securityController,
      ]),
      builder: (context, child) {
        final pages = [
          DashboardPage(
            player: widget.player,
            questSystem: widget.questSystem,
            timetableSystem: widget.timetableSystem,
            restSystem: widget.restSystem,
            studyTimer: widget.studyTimer,
            securityController: widget.securityController,
            appVersionLabel: widget.appVersionLabel,
          ),
          QuestPage(
            player: widget.player,
            questSystem: widget.questSystem,
            studyTimer: widget.studyTimer,
            restSystem: widget.restSystem,
          ),
          StatusPage(
            player: widget.player,
            uidManager: widget.uidManager,
            supabaseService: widget.supabaseService,
            securityController: widget.securityController,
          ),
          SettingsPage(
            player: widget.player,
            isDarkMode: widget.isDarkMode,
            onDarkModeChanged: widget.onDarkModeChanged,
            appVersionLabel: widget.appVersionLabel,
          ),
        ];

        return Scaffold(
          body: SafeArea(
            child: widget.player.isLoaded &&
                    widget.restSystem.isLoaded &&
                    widget.questSystem.isLoaded &&
                    widget.timetableSystem.isLoaded
                ? pages[selectedIndex]
                : Center(
                    child: CircularProgressIndicator(color: c.cyan),
                  ),
          ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: c.panel,
            indicatorColor: c.blue.withValues(alpha: 0.18),
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              setState(() => selectedIndex = index);
            },
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined, color: c.muted),
                selectedIcon: Icon(Icons.dashboard, color: c.cyan),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.assignment_outlined, color: c.muted),
                selectedIcon: Icon(Icons.assignment, color: c.cyan),
                label: 'Quests',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline, color: c.muted),
                selectedIcon: Icon(Icons.person, color: c.cyan),
                label: 'Status',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined, color: c.muted),
                selectedIcon: Icon(Icons.settings, color: c.cyan),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// DASHBOARD PAGE
// ============================================================

class DashboardPage extends StatelessWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;
  final TimetableSystem timetableSystem;
  final RestSystem restSystem;
  final StudyTimer studyTimer;
  final SecurityController securityController;
  final String appVersionLabel;

  const DashboardPage({
    super.key,
    required this.player,
    required this.questSystem,
    required this.timetableSystem,
    required this.restSystem,
    required this.studyTimer,
    required this.securityController,
    required this.appVersionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);
    final unlockRemaining = securityController.emergencyUnlockRemaining;
    final unlockActive = securityController.isEmergencyUnlockActive;
    final unlockCountdown = '${unlockRemaining.inHours.toString().padLeft(2, '0')}:'
        '${unlockRemaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${unlockRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOLO SYSTEM',
                  style: TextStyle(
                    color: c.cyan,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'WELCOME BACK, ${player.playerName.toUpperCase()}.',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.blue.withValues(alpha: 0.4)),
              ),
              child: Icon(Icons.notifications_active_outlined, color: c.cyan),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.cyan.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome, color: c.cyan, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DAILY SYSTEM MESSAGE',
                      style: TextStyle(
                        color: c.cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      questSystem.dailySystemMessage.isEmpty
                          ? 'The System is preparing your daily message...'
                          : questSystem.dailySystemMessage,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unlockActive
                ? Colors.green.withValues(alpha: 0.12)
                : c.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: unlockActive
                  ? Colors.green.withValues(alpha: 0.55)
                  : c.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(
                unlockActive ? Icons.lock_open : Icons.lock_outline,
                color: unlockActive ? Colors.greenAccent : c.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unlockActive
                          ? 'EMERGENCY UNLOCK ACTIVE'
                          : 'EMERGENCY UNLOCK INACTIVE',
                      style: TextStyle(
                        color: unlockActive ? Colors.greenAccent : c.text,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unlockActive
                          ? 'Restricted apps unlocked · $unlockCountdown remaining'
                          : 'Restricted apps remain protected',
                      style: TextStyle(color: c.muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (unlockActive)
                const Icon(Icons.verified, color: Colors.greenAccent, size: 18),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark
                  ? const [Color(0xFF102B50), Color(0xFF091426)]
                  : const [Color(0xFFE8F4FB), Color(0xFFF7FBFF)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.blue.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: c.blue.withValues(alpha: 0.08),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.blue.withValues(alpha: 0.15),
                      border: Border.all(color: c.cyan),
                    ),
                    child: Icon(Icons.person, color: c.cyan, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PLAYER',
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 10,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          player.playerName.toUpperCase(),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${player.rank} • ${player.title}',
                          style: TextStyle(
                            color: c.cyan,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'LV. ${player.level.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: c.cyan,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'EXPERIENCE POINTS',
                    style: TextStyle(color: c.muted, fontSize: 10),
                  ),
                  Text(
                    '${player.xp} / ${player.xpRequired} XP',
                    style: TextStyle(color: c.cyan, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: player.xpProgress.clamp(0.0, 1.0),
                  minHeight: 9,
                  backgroundColor: c.barTrack,
                  color: c.cyan,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '${(player.xpRequired - player.xp).clamp(0, 999999)} XP REQUIRED FOR NEXT LEVEL',
                style: TextStyle(color: c.muted, fontSize: 9),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionTitle(title: 'PLAYER VITALS'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _HpVitalCard(player: player)),
            const SizedBox(width: 12),
            Expanded(
              child: _MpVitalCard(
                player: player,
                reservedMp: studyTimer.reservedMpAmount,
                color: const Color(0xFF00E5FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: restSystem,
          builder: (context, child) {
            final active = restSystem.isShortRestActive;
            final minutes = restSystem.elapsedShortRestMinutes;
            final recoveryRemaining = restSystem.shortRestTimeToNextRecovery;
            final recoveryMinutes = recoveryRemaining.inMinutes;
            final recoverySeconds = recoveryRemaining.inSeconds.remainder(60);

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active
                      ? c.cyan.withValues(alpha: 0.7)
                      : c.cyan.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bedtime_outlined, color: c.cyan, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'SHORT REST',
                        style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      if (active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: c.cyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: c.cyan,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    active
                        ? 'Resting for $minutes min\n'
                            'Next +5 HP / +5 MP in '
                            '${recoveryMinutes.toString().padLeft(2, '0')}:'
                            '${recoverySeconds.toString().padLeft(2, '0')}'
                        : 'Recover HP and MP by resting.\n+5 HP / +5 MP every 10 min.',
                    style: TextStyle(color: c.muted, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: active
                          ? () async {
                              await restSystem.stopShortRest();
                            }
                          : (restSystem.isLongRestActive ||
                                  studyTimer.activeQuestId != null)
                              ? null
                              : () async {
                                  await restSystem.startShortRest();
                                },
                      child: Text(active ? 'END REST' : 'START SHORT REST'),
                    ),
                  ),
                  if (restSystem.isLongRestActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Long Rest is currently active.',
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (restSystem.isLongRestActive)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.greenAccent.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.nightlight_round,
                      color: Colors.greenAccent,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'LONG REST ACTIVE',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(restSystem.remainingLongRestMinutes ~/ 60).toString().padLeft(2, '0')}:'
                      '${(restSystem.remainingLongRestMinutes % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Recovery in progress...\nWakeup Mission ends Long Rest.',
                  style: TextStyle(color: c.muted, height: 1.5),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        AnimatedBuilder(
          animation: questSystem,
          builder: (context, child) {
            final isPenalty = questSystem.isPenaltyActive;
            final isNight = questSystem.isNightLockActive;
            final isHpCritical = player.isCriticalHp;

            final Color statusColor = isHpCritical
                ? Colors.redAccent
                : isPenalty
                    ? Colors.redAccent
                    : isNight
                        ? Colors.blueAccent
                        : Colors.greenAccent;

            final IconData statusIcon = isHpCritical
                ? Icons.warning
                : isPenalty
                    ? Icons.shield
                    : isNight
                        ? Icons.nightlight_round
                        : Icons.lock_open;

            final String statusTitle = isHpCritical
                ? 'HP CRITICAL'
                : isPenalty
                    ? 'PENALTY LOCK'
                    : isNight
                        ? 'NIGHT LOCK'
                        : 'SYSTEM UNLOCKED';

            String remainingText;
            if (isHpCritical) {
              remainingText = 'Take a rest to recover HP before continuing.';
            } else if (isPenalty) {
              final remaining = questSystem.penaltyRemaining;
              final hours = remaining.inHours;
              final minutes = remaining.inMinutes.remainder(60);
              final seconds = remaining.inSeconds.remainder(60);
              remainingText =
                  'Remaining: ${hours.toString().padLeft(2, '0')}:'
                  '${minutes.toString().padLeft(2, '0')}:'
                  '${seconds.toString().padLeft(2, '0')}';
            } else if (isNight) {
              remainingText = 'Complete your Wakeup Mission to unlock.';
            } else {
              remainingText = 'All restrictions are currently inactive.';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 22),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 25),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'APP RESTRICTION STATUS',
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 9,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          statusTitle,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          remainingText,
                          style: TextStyle(color: c.muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: timetableSystem,
          builder: (context, child) {
            final todaySchedules =
                timetableSystem.getSchedulesForDay(DateTime.now().weekday);

            return Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "TODAY'S SCHEDULE",
                        style: TextStyle(
                          color: c.cyan,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        "${todaySchedules.length} Tasks",
                        style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (todaySchedules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_available,
                            size: 17,
                            color: c.muted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "No study schedule for today.",
                            style: TextStyle(color: c.muted),
                          ),
                        ],
                      ),
                    )
                  else
                    ...todaySchedules.take(3).map((item) {
                      final isCompleted =
                          item.completedDate == timetableSystem.todayKey;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              isCompleted
                                  ? Icons.check_circle
                                  : Icons.schedule,
                              size: 17,
                              color: isCompleted ? Colors.green : c.cyan,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.subject,
                                style: TextStyle(
                                  color: isCompleted ? c.muted : c.text,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (item.isOptional)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  'OPT',
                                  style: TextStyle(
                                    color: c.cyan,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (isCompleted)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  'DONE',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            Text(
                              item.startTime,
                              style: TextStyle(color: c.muted),
                            ),
                          ],
                        ),
                      );
                    }),
                  if (todaySchedules.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${todaySchedules.length - 3} more',
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TimetablePage(
                              timetableSystem: timetableSystem,
                            ),
                          ),
                        );
                      },
                      child: const Text("OPEN TIMETABLE"),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SectionTitle(title: 'DAILY QUEST'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.blue.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.assignment, color: c.cyan),
                  const SizedBox(width: 10),
                  Text(
                    "TODAY'S OBJECTIVES",
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Quest Completion',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  Text(
                    '${questSystem.completedCount} / ${questSystem.totalCount}',
                    style: TextStyle(color: c.cyan, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: questSystem.progress.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: c.barTrack,
                  color: c.blue,
                ),
              ),
              const SizedBox(height: 15),
              ...questSystem.quests.map((quest) {
                final state = questSystem.getQuestState(quest.id);
                return QuestRow(
                  name: quest.name,
                  duration: quest.requiresTimer
                      ? '${quest.durationMinutes} Min'
                      : '',
                  state: state,
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionTitle(title: 'SYSTEM STATISTICS'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InfoCard(
                title: 'STUDY TIME',
                value: player.todayStudyTimeFormatted,
                unit: 'HOURS : MINUTES',
                icon: Icons.menu_book,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InfoCard(
                title: 'TOTAL XP',
                value: player.totalXp.toString(),
                unit: 'EARNED',
                icon: Icons.stars,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.cyan.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: c.cyan),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'SYSTEM MESSAGE: Your journey to become stronger starts today.',
                  style: TextStyle(
                    color: c.text.withValues(alpha: 0.85),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'SYSTEM VERSION $appVersionLabel',
            style: TextStyle(
              color: c.muted,
              fontSize: 9,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// HP VITAL CARD
// ============================================================

class _HpVitalCard extends StatelessWidget {
  final PlayerSystem player;

  const _HpVitalCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);
    final isCritical = player.isCriticalHp;
    final isLow = player.isLowHp;

    final Color hpColor = isCritical
        ? Colors.red
        : isLow
            ? Colors.orange
            : const Color(0xFFFF526D);

    final Color borderColor = isCritical
        ? Colors.red.withValues(alpha: 0.8)
        : isLow
            ? Colors.orange.withValues(alpha: 0.6)
            : hpColor.withValues(alpha: 0.35);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: borderColor,
          width: isCritical ? 2.0 : 1.0,
        ),
        boxShadow: isCritical
            ? [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, color: hpColor, size: 18),
              const SizedBox(width: 8),
              Text('HP', style: TextStyle(color: hpColor)),
              const Spacer(),
              if (isCritical)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'CRITICAL',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else if (isLow)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'LOW',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            '${player.hp} / ${player.maxHp}',
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: player.hpProgress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: c.barTrack,
              color: hpColor,
            ),
          ),
          if (isCritical) ...[
            const SizedBox(height: 8),
            Text(
              'Rest required to continue.',
              style: TextStyle(
                color: Colors.red,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// MP VITAL CARD
// ============================================================

class _MpVitalCard extends StatelessWidget {
  final PlayerSystem player;
  final int reservedMp;
  final Color color;

  const _MpVitalCard({
    required this.player,
    required this.reservedMp,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);
    final available = (player.mp - reservedMp).clamp(0, player.maxMp);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: color, size: 18),
              const SizedBox(width: 8),
              Text('MP', style: TextStyle(color: color)),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            '${player.mp} / ${player.maxMp}',
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          if (reservedMp > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Available: $available  •  Reserved: $reservedMp',
              style: TextStyle(
                color: c.muted,
                fontSize: 9,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// SHARED WIDGETS
// ============================================================

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: SystemColors.of(context).cyan,
        fontWeight: FontWeight.bold,
        fontSize: 13,
        letterSpacing: 2,
      ),
    );
  }
}

class QuestRow extends StatelessWidget {
  final String name;
  final String duration;
  final QuestState state;

  const QuestRow({
    super.key,
    required this.name,
    required this.duration,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

    IconData icon;
    Color iconColor;
    Color textColor = c.text;
    TextDecoration? decoration;
    String? badgeLabel;
    Color? badgeColor;

    switch (state) {
      case QuestState.completed:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        textColor = c.muted;
        decoration = TextDecoration.lineThrough;
        break;
      case QuestState.skipped:
        icon = Icons.remove_circle_outline;
        iconColor = c.muted;
        textColor = c.muted;
        decoration = TextDecoration.lineThrough;
        badgeLabel = 'SKIPPED';
        badgeColor = c.muted;
        break;
      case QuestState.missed:
        icon = Icons.cancel;
        iconColor = Colors.redAccent;
        textColor = c.muted;
        decoration = TextDecoration.lineThrough;
        badgeLabel = 'MISSED';
        badgeColor = Colors.redAccent;
        break;
      case QuestState.active:
        icon = Icons.play_circle;
        iconColor = c.cyan;
        break;
      case QuestState.available:
        icon = Icons.circle_outlined;
        iconColor = c.muted;
        break;
      case QuestState.upcoming:
        icon = Icons.schedule;
        iconColor = c.muted;
        break;
      case QuestState.locked:
        icon = Icons.lock;
        iconColor = c.muted;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: textColor,
                decoration: decoration,
              ),
            ),
          ),
          if (badgeLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Text(
            duration,
            style: TextStyle(color: c.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;

  const InfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.cyan, size: 20),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: c.muted, fontSize: 9)),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: c.text,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(unit, style: TextStyle(color: c.muted, fontSize: 9)),
        ],
      ),
    );
  }
}

// ============================================================
// QUEST PAGE
// ============================================================

class QuestPage extends StatelessWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;
  final StudyTimer studyTimer;
  final RestSystem restSystem;

  const QuestPage({
    super.key,
    required this.player,
    required this.questSystem,
    required this.studyTimer,
    required this.restSystem,
  });

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        questSystem,
        studyTimer,
        restSystem,
        player,
      ]),
      builder: (context, child) {
        final activeId = studyTimer.activeQuestId;
        final quests = questSystem.quests;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'STUDY QUESTS',
              style: TextStyle(
                color: c.cyan,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Completed: ${questSystem.completedCount}/${questSystem.totalCount}',
              style: TextStyle(color: c.muted),
            ),
            if (player.isCriticalHp) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'HP CRITICAL — Take a rest before starting any mission.',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (activeId != null)
              Container(
                padding: const EdgeInsets.all(18),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.cyan, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: 0.15),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timer, color: c.cyan, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'ACTIVE STUDY SESSION',
                          style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const Spacer(),
                        if (studyTimer.isFinished)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  Colors.greenAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'FINISHED',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        studyTimer.formattedTime,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        _activeSessionStatus(studyTimer),
                        style: TextStyle(
                          color: studyTimer.isFinished ? c.cyan : c.muted,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sessionMetaRow(context, studyTimer, questSystem),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (studyTimer.isRunning)
                          ElevatedButton.icon(
                            onPressed: () => studyTimer.pause(),
                            icon: const Icon(Icons.pause, size: 18),
                            label: const Text('Pause'),
                          )
                        else if (!studyTimer.isFinished)
                          ElevatedButton.icon(
                            onPressed: () => studyTimer.resume(),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Resume'),
                          ),
                        if (studyTimer.isFinished)
                          ElevatedButton.icon(
                            onPressed: () async {
                              final xp = await studyTimer.completeQuest(
                                questSystem,
                                player,
                              );
                              if (!context.mounted) return;
                              final messenger = ScaffoldMessenger.of(context);
                              messenger.clearSnackBars();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    xp != null
                                        ? 'Quest completed! +$xp XP'
                                        : 'Claim failed. Check the console.',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Claim XP'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _handleCancelSession(
                            context,
                            studyTimer,
                            player,
                          ),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (questSystem.weeklySpecialDay != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: c.cyan.withValues(alpha: 0.65),
                    width: 1.2,
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    final mission = questSystem.weeklySpecialMission;
                    final isMissionDay = questSystem.isWeeklySpecialMissionDay;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome, color: c.cyan, size: 19),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'WEEKLY SPECIAL MISSION',
                                style: TextStyle(
                                  color: c.cyan,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              questSystem.weeklySpecialDayName.toUpperCase(),
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (mission == null)
                          Text(
                            'A special mission will be revealed on '
                            '${questSystem.weeklySpecialDayName}.',
                            style: TextStyle(color: c.text, height: 1.4),
                          )
                        else ...[
                          Text(
                            mission.title,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            mission.description,
                            style: TextStyle(color: c.muted, height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                mission.category,
                                style: TextStyle(
                                  color: c.cyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.7,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '+${mission.xpReward} XP',
                                style: TextStyle(
                                  color: c.cyan,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (mission.isCompleted)
                            const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                                SizedBox(width: 7),
                                Text(
                                  'MISSION COMPLETED',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            )
                          else if (isMissionDay)
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final earned = await questSystem
                                      .completeWeeklySpecialMission(player);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        earned == null
                                            ? 'Mission could not be completed.'
                                            : 'Special Mission completed! +$earned XP',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('COMPLETE MISSION'),
                              ),
                            )
                          else
                            Text(
                              'Mission unlocks on ${questSystem.weeklySpecialDayName}.',
                              style: TextStyle(color: c.muted, fontSize: 11),
                            ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'OPTIONAL • NO PENALTY IF MISSED',
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            if (quests.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.divider),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      color: c.muted,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'NO QUESTS TODAY',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add study schedules in Timetable to create quests.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted),
                    ),
                  ],
                ),
              ),
            ...quests.map((quest) {
              final state = questSystem.getQuestState(quest.id);
              final isActive = activeId == quest.id;
              final anotherActive = activeId != null && !isActive;
              final isFixedMission = !quest.requiresTimer;

              final Color borderColor;
              switch (state) {
                case QuestState.completed:
                  borderColor = Colors.green.withValues(alpha: 0.5);
                  break;
                case QuestState.skipped:
                  borderColor = c.muted.withValues(alpha: 0.3);
                  break;
                case QuestState.missed:
                  borderColor = Colors.redAccent.withValues(alpha: 0.5);
                  break;
                case QuestState.active:
                  borderColor = c.cyan;
                  break;
                case QuestState.upcoming:
                case QuestState.available:
                case QuestState.locked:
                  borderColor = c.text.withValues(alpha: 0.10);
                  break;
              }

              return Container(
                key: ValueKey(quest.id),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: borderColor,
                    width: state == QuestState.active ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            quest.name,
                            style: TextStyle(
                              color: (state == QuestState.missed ||
                                      state == QuestState.skipped)
                                  ? c.muted
                                  : c.text,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              decoration: (state == QuestState.completed ||
                                      state == QuestState.missed ||
                                      state == QuestState.skipped)
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (quest.isOptional)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'OPTIONAL • NO XP',
                              style: TextStyle(
                                color: c.cyan,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (!isFixedMission)
                      Text(
                        '${quest.durationMinutes} min • ${quest.xpReward} XP',
                        style: TextStyle(color: c.muted),
                      )
                    else
                      Text(
                        quest.subject,
                        style: TextStyle(color: c.muted),
                      ),
                    const SizedBox(height: 12),
                    _questStateWidget(
                      context: context,
                      quest: quest,
                      state: state,
                      isActive: isActive,
                      anotherActive: anotherActive,
                      isFixedMission: isFixedMission,
                      player: player,
                      questSystem: questSystem,
                      studyTimer: studyTimer,
                      restSystem: restSystem,
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _handleCancelSession(
    BuildContext context,
    StudyTimer studyTimer,
    PlayerSystem player,
  ) async {
    final startedAt = studyTimer.startedAtTime;
    final elapsed = startedAt != null
        ? DateTime.now().difference(startedAt)
        : Duration.zero;
    final willTakeDamage =
        startedAt != null && !studyTimer.isFinished && elapsed.inMinutes >= 5;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final damage =
            willTakeDamage ? _calculateCancelDamage(player) : 0;

        return AlertDialog(
          title: const Text('Cancel Session?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your progress will not be saved and reserved MP will be released.',
              ),
              if (willTakeDamage) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You will lose $damage HP for cancelling an active session.',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('KEEP'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                willTakeDamage ? 'CANCEL & LOSE HP' : 'CANCEL SESSION',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final damage = await studyTimer.cancel(player: player);
      if (!context.mounted) return;
      if (damage > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session cancelled. -$damage HP'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  int _calculateCancelDamage(PlayerSystem player) {
    final levelMultiplier = 1.0 + ((player.level - 1) * 0.05);
    final rawDamage = player.maxHp * 0.08 * levelMultiplier;
    final capped = rawDamage.clamp(0.0, player.maxHp * 0.40);
    return capped.round();
  }

  String _activeSessionStatus(StudyTimer timer) {
    if (timer.isFinished) return 'TIMER COMPLETE — CLAIM YOUR XP';
    if (timer.isRunning) return 'FOCUS MODE ACTIVE';
    return 'PAUSED';
  }

  Widget _sessionMetaRow(
    BuildContext context,
    StudyTimer timer,
    QuestSystem questSystem,
  ) {
    final c = SystemColors.of(context);
    final questId = timer.activeQuestId;
    if (questId == null) return const SizedBox.shrink();

    final quest = questSystem.getQuestById(questId);
    if (quest == null) return const SizedBox.shrink();

    final difficulty = timer.getDifficulty(quest.durationMinutes);
    final mpCost = timer.reservedMpAmount;
    final canClaimAfterDeadline =
        questSystem.wasTimerStartedBeforeDeadline(questId) &&
            quest.deadline != null &&
            DateTime.now().isAfter(quest.deadline!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _metaChip(c, Icons.speed, difficulty, c.cyan),
            const SizedBox(width: 8),
            _metaChip(c, Icons.bolt, '$mpCost MP reserved', c.cyan),
          ],
        ),
        if (canClaimAfterDeadline) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.amber,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'Deadline passed — claim still valid (started in time).',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _metaChip(
    SystemColors c,
    IconData icon,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _questStateWidget({
    required BuildContext context,
    required StudyQuest quest,
    required QuestState state,
    required bool isActive,
    required bool anotherActive,
    required bool isFixedMission,
    required PlayerSystem player,
    required QuestSystem questSystem,
    required StudyTimer studyTimer,
    required RestSystem restSystem,
  }) {
    final c = SystemColors.of(context);

    if (state == QuestState.completed) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 6),
          Text(
            'COMPLETED',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      );
    }

    if (state == QuestState.skipped) {
      return Row(
        children: [
          Icon(Icons.remove_circle_outline, color: c.muted, size: 16),
          const SizedBox(width: 6),
          Text(
            'SKIPPED',
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    if (state == QuestState.missed) {
      return Row(
        children: [
          const Icon(Icons.cancel, color: Colors.redAccent, size: 16),
          const SizedBox(width: 6),
          Text(
            'MISSION FAILED',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      );
    }

    if (isActive) {
      return Row(
        children: [
          Icon(Icons.play_circle, color: c.cyan, size: 16),
          const SizedBox(width: 6),
          Text(
            'ACTIVE SESSION',
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      );
    }

    if (state == QuestState.upcoming) {
      final availableAt = quest.availableFrom;
      final availableLabel = availableAt == null
          ? ''
          : '${availableAt.hour % 12 == 0 ? 12 : availableAt.hour % 12}:'
              '${availableAt.minute.toString().padLeft(2, '0')} '
              '${availableAt.hour >= 12 ? 'PM' : 'AM'}';

      return Text(
        'UPCOMING • AVAILABLE AT $availableLabel',
        style: TextStyle(
          color: c.muted,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      );
    }

    if (isFixedMission) {
      final blocked = player.isCriticalHp;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: blocked
                ? null
                : () async {
                    final xp = await questSystem.completeFixedMission(
                      quest.id,
                      player,
                    );
                    if (context.mounted && xp != null) {
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.clearSnackBars();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('${quest.name} completed! +$xp XP'),
                        ),
                      );
                    }
                  },
            child: const Text('Complete'),
          ),
          if (blocked) ...[
            const SizedBox(height: 6),
            Text(
              'HP CRITICAL — Rest required.',
              style: TextStyle(color: Colors.red, fontSize: 10),
            ),
          ],
        ],
      );
    }

    final canStart = questSystem.canStartTimer(quest.id);
    final blockedReason = anotherActive
        ? 'Another session active'
        : restSystem.isShortRestActive
            ? 'Short rest active'
            : restSystem.isLongRestActive
                ? 'Long rest active'
                : !canStart.allowed
                    ? canStart.reason
                    : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: blockedReason != null
              ? null
              : () async {
                  final ok = await studyTimer.start(
                    questId: quest.id,
                    durationMinutes: quest.durationMinutes,
                    player: player,
                    questSystem: questSystem,
                  );
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Unable to start: insufficient MP, HP, or busy.'),
                      ),
                    );
                  }
                },
          child: const Text('Start Study'),
        ),
        if (blockedReason != null) ...[
          const SizedBox(height: 6),
          Text(
            blockedReason,
            style: TextStyle(
              color: blockedReason.contains('HP') ? Colors.red : c.muted,
              fontSize: 10,
              fontWeight: blockedReason.contains('HP')
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// STATUS PAGE
// ============================================================

class StatusPage extends StatelessWidget {
  final PlayerSystem player;
  final UidManager uidManager;
  final SupabaseService supabaseService;
  final SecurityController securityController;

  const StatusPage({
    super.key,
    required this.player,
    required this.uidManager,
    required this.supabaseService,
    required this.securityController,
  });

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SectionTitle(title: 'PLAYER STATUS'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.blue.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.playerName.toUpperCase(),
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${player.rank} • ${player.title}',
                style: TextStyle(color: c.cyan, fontSize: 11),
              ),
              const SizedBox(height: 16),
              _statusRow(context, 'LEVEL', '${player.level}'),
              _statusRow(context, 'XP', '${player.xp} / ${player.xpRequired}'),
              _statusRow(
                context,
                'XP PROGRESS',
                '${(player.xpProgress * 100).toStringAsFixed(0)}%',
              ),
              _statusRow(context, 'HP', '${player.hp} / ${player.maxHp}'),
              _statusRow(context, 'MP', '${player.mp} / ${player.maxMp}'),
              _statusRow(
                context,
                'TOTAL STUDY TIME',
                player.totalStudyTimeFormatted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _UidSecurityCard(
          securityController: securityController,
          supabaseService: supabaseService,
          uidManager: uidManager,
        ),
        const SizedBox(height: 22),
        const SectionTitle(title: 'ATTRIBUTES'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InfoCard(
                title: 'STRENGTH',
                value: '${player.strength}',
                unit: 'STR',
                icon: Icons.fitness_center,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InfoCard(
                title: 'INTELLECT',
                value: '${player.intellect}',
                unit: 'INT',
                icon: Icons.psychology,
              ),
            ),
          ],
        ),
        if (player.hpDamageHistory.isNotEmpty) ...[
          const SizedBox(height: 22),
          const SectionTitle(title: 'RECENT HP DAMAGE'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...player.hpDamageHistory.reversed.take(5).map(
                      (event) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.remove_circle,
                              color: Colors.redAccent,
                              size: 15,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                event.reason,
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              '-${event.damage} HP',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _statusRow(BuildContext context, String label, String value) {
    final c = SystemColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
          Text(value, style: TextStyle(color: c.text, fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================================================
// UID SECURITY CARD (inside StatusPage)
// ============================================================

class _UidSecurityCard extends StatelessWidget {
  final SecurityController securityController;
  final SupabaseService supabaseService;
  final UidManager uidManager;

  const _UidSecurityCard({
    required this.securityController,
    required this.supabaseService,
    required this.uidManager,
  });

  Future<void> _copyUid(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: uidManager.uid ?? ''),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('UID copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = uidManager.uid ?? '—';
    final isRegistered = securityController.isRegistered;
    final isOnline = securityController.isOnline;

    final Color statusColor;
    final String statusLabel;
    if (isRegistered && isOnline) {
      statusColor = Colors.greenAccent;
      statusLabel = 'ONLINE';
    } else if (isRegistered && !isOnline) {
      statusColor = Colors.orangeAccent;
      statusLabel = 'OFFLINE';
    } else {
      statusColor = Colors.redAccent;
      statusLabel = 'PENDING';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade900,
            Colors.cyan.shade900,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withValues(alpha: 0.15),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint, color: Colors.cyan, size: 18),
              const SizedBox(width: 8),
              const Text(
                'PLAYER UID',
                style: TextStyle(
                  color: Colors.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  uid,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.cyan, size: 16),
                onPressed: () => _copyUid(context),
                tooltip: 'Copy UID',
                visualDensity: VisualDensity.compact,
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
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SecurityPage(
                      controller: securityController,
                      uidManager: uidManager,
                      supabaseService: supabaseService,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.security, size: 16),
              label: const Text(
                'SECURITY & CODES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SETTINGS PAGE
// ============================================================

class SettingsPage extends StatelessWidget {
  final PlayerSystem player;
  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final String appVersionLabel;

  const SettingsPage({
    super.key,
    required this.player,
    required this.isDarkMode,
    required this.onDarkModeChanged,
    required this.appVersionLabel,
  });

  Future<void> _editPlayerName(BuildContext context) async {
    final c = SystemColors.of(context);
    final controller = TextEditingController(text: player.playerName);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: c.panel,
          title: Text(
            'CHANGE PLAYER NAME',
            style: TextStyle(color: c.cyan, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 25,
            style: TextStyle(color: c.text),
            decoration: InputDecoration(
              hintText: 'Enter your player name',
              hintStyle: TextStyle(color: c.muted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.blue),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.cyan),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL', style: TextStyle(color: c.muted)),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: Text('SAVE', style: TextStyle(color: c.cyan)),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newName == null || newName.trim().isEmpty) return;

    await player.setPlayerName(newName);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Player name updated successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SectionTitle(title: 'SYSTEM SETTINGS'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.blue.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.person_outline, color: c.cyan),
                title: Text('Player Name', style: TextStyle(color: c.text)),
                subtitle: Text(
                  player.playerName,
                  style: TextStyle(color: c.muted),
                ),
                trailing: Icon(Icons.edit, color: c.cyan),
                onTap: () => _editPlayerName(context),
              ),
              Divider(color: c.divider, height: 1),
              ListTile(
                leading: Icon(Icons.notifications_outlined, color: c.cyan),
                title: Text('Notifications', style: TextStyle(color: c.text)),
                trailing: Text(
                  'Coming Soon',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              ),
              Divider(color: c.divider, height: 1),
              ListTile(
                leading: Icon(Icons.dark_mode_outlined, color: c.cyan),
                title: Text('Dark Mode', style: TextStyle(color: c.text)),
                subtitle: Text(
                  isDarkMode ? 'Enabled' : 'Disabled',
                  style: TextStyle(color: c.muted),
                ),
                trailing: Switch(
                  value: isDarkMode,
                  onChanged: onDarkModeChanged,
                  activeThumbColor: c.cyan,
                ),
              ),
              Divider(color: c.divider, height: 1),
              ListTile(
                leading: Icon(Icons.info_outline, color: c.cyan),
                title: Text('System Version', style: TextStyle(color: c.text)),
                trailing: Text(appVersionLabel, style: TextStyle(color: c.muted)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}