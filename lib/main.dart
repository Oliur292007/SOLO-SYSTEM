import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player_system.dart';
import 'quest_system.dart';

void main() {
  final player = PlayerSystem();
  final questSystem = QuestSystem();

  runApp(
    SoloSystemApp(
      player: player,
      questSystem: questSystem,
    ),
  );
}

const Color bg = Color(0xFF050B18);
const Color panel = Color(0xFF0B1930);
const Color blue = Color(0xFF00BFFF);
const Color cyan = Color(0xFF00E5FF);
const Color muted = Color(0xFF8295B3);

// ============================================================
// APP ROOT (now stateful for theme persistence)
// ============================================================

class SoloSystemApp extends StatefulWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;

  const SoloSystemApp({
    super.key,
    required this.player,
    required this.questSystem,
  });

  @override
  State<SoloSystemApp> createState() => _SoloSystemAppState();
}

class _SoloSystemAppState extends State<SoloSystemApp> {
  bool isDarkMode = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
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
        scaffoldBackgroundColor: const Color(0xFFF1F5FA),
        colorScheme: const ColorScheme.light(
          primary: blue,
          secondary: cyan,
          surface: Colors.white,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: blue,
          secondary: cyan,
          surface: panel,
        ),
        useMaterial3: true,
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: SystemHome(
        player: widget.player,
        questSystem: widget.questSystem,
        isDarkMode: isDarkMode,
        onDarkModeChanged: _changeTheme,
      ),
    );
  }
}

// ============================================================
// HOME SHELL
// ============================================================

class SystemHome extends StatefulWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;
  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;

  const SystemHome({
    super.key,
    required this.player,
    required this.questSystem,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  @override
  State<SystemHome> createState() => _SystemHomeState();
}

class _SystemHomeState extends State<SystemHome> {
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.player.loadPlayer();
    widget.questSystem.loadQuests();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.player,
        widget.questSystem,
      ]),
      builder: (context, child) {
        final pages = [
          DashboardPage(
            player: widget.player,
            questSystem: widget.questSystem,
          ),
          QuestPage(
            player: widget.player,
            questSystem: widget.questSystem,
          ),
          StatusPage(player: widget.player),
          SettingsPage(
            player: widget.player,
            isDarkMode: widget.isDarkMode,
            onDarkModeChanged: widget.onDarkModeChanged,
          ),
        ];

        return Scaffold(
          body: SafeArea(
            child: widget.player.isLoaded && widget.questSystem.isLoaded
                ? pages[selectedIndex]
                : const Center(
                    child: CircularProgressIndicator(color: cyan),
                  ),
          ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: panel,
            indicatorColor: blue.withValues(alpha: 0.18),
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              setState(() => selectedIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: cyan),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment, color: cyan),
                label: 'Quests',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person, color: cyan),
                label: 'Status',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: cyan),
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
// DASHBOARD
// ============================================================

class DashboardPage extends StatelessWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;

  const DashboardPage({
    super.key,
    required this.player,
    required this.questSystem,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOLO SYSTEM',
                  style: TextStyle(
                    color: cyan,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'WELCOME BACK, PLAYER.',
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: blue.withValues(alpha: 0.4)),
              ),
              child: const Icon(
                Icons.notifications_active_outlined,
                color: cyan,
              ),
            ),
          ],
        ),

        const SizedBox(height: 25),

        // PLAYER PROFILE
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF102B50),
                Color(0xFF091426),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: blue.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: blue.withValues(alpha: 0.08),
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
                      color: blue.withValues(alpha: 0.15),
                      border: Border.all(color: cyan),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: cyan,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PLAYER',
                          style: TextStyle(
                            color: muted,
                            fontSize: 10,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          player.playerName.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${player.rank} • ${player.title}',
                          style: const TextStyle(
                            color: cyan,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'LV. ${player.level.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: cyan,
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
                  const Text(
                    'EXPERIENCE POINTS',
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                  Text(
                    '${player.xp} / ${player.xpRequired} XP',
                    style: const TextStyle(color: cyan, fontSize: 11),
                  ),
                ],
              ),

              const SizedBox(height: 9),

              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: player.xpProgress.clamp(0.0, 1.0),
                  minHeight: 9,
                  backgroundColor: const Color(0xFF24354C),
                  color: cyan,
                ),
              ),

              const SizedBox(height: 9),

              Text(
                '${(player.xpRequired - player.xp).clamp(0, 999999)} XP REQUIRED FOR NEXT LEVEL',
                style: const TextStyle(color: muted, fontSize: 9),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        const SectionTitle(title: 'PLAYER VITALS'),

        const SizedBox(height: 12),

        const Row(
          children: [
            Expanded(
              child: VitalCard(
                title: 'HP',
                value: '100 / 100',
                icon: Icons.favorite,
                color: Color(0xFFFF526D),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: VitalCard(
                title: 'MP',
                value: '85 / 100',
                icon: Icons.bolt,
                color: cyan,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        const SectionTitle(title: 'DAILY QUEST'),

        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: blue.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.assignment, color: cyan),
                  SizedBox(width: 10),
                  Text(
                    "TODAY'S OBJECTIVES",
                    style: TextStyle(
                      color: cyan,
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
                  const Text(
                    'Quest Completion',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  Text(
                    '${questSystem.completedCount} / ${questSystem.totalCount}',
                    style: const TextStyle(color: cyan, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: questSystem.progress.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: const Color(0xFF24354C),
                  color: blue,
                ),
              ),
              const SizedBox(height: 15),
              ...questSystem.quests.map(
                (quest) => QuestRow(
                  name: quest.name,
                  duration: '${quest.durationMinutes} Min',
                  completed: questSystem.isCompleted(quest.id),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        const SectionTitle(title: 'SYSTEM STATISTICS'),

        const SizedBox(height: 12),

        const Row(
          children: [
            Expanded(
              child: InfoCard(
                title: 'STUDY TIME',
                value: '02:00',
                unit: 'HOURS',
                icon: Icons.menu_book,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: InfoCard(
                title: 'SCREEN TIME',
                value: '01:25',
                unit: 'HOURS',
                icon: Icons.phone_android,
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10233D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cyan.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: cyan),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'SYSTEM MESSAGE: Your journey to become stronger starts today.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Center(
          child: Text(
            'SYSTEM VERSION 1.0.0',
            style: TextStyle(
              color: muted,
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
// REUSABLE WIDGETS
// ============================================================

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: cyan,
        fontWeight: FontWeight.bold,
        fontSize: 13,
        letterSpacing: 2,
      ),
    );
  }
}

class VitalCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const VitalCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: color)),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}

class QuestRow extends StatelessWidget {
  final String name;
  final String duration;
  final bool completed;

  const QuestRow({
    super.key,
    required this.name,
    required this.duration,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.circle_outlined,
            color: completed ? Colors.greenAccent : muted,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: completed ? muted : Colors.white,
                decoration: completed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(
            duration,
            style: const TextStyle(color: muted, fontSize: 11),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cyan, size: 20),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: muted, fontSize: 9)),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(unit, style: const TextStyle(color: muted, fontSize: 9)),
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

  const QuestPage({
    super.key,
    required this.player,
    required this.questSystem,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SectionTitle(title: 'QUEST CENTER'),
        const SizedBox(height: 8),
        const Text(
          'COMPLETE MISSIONS. EARN EXPERIENCE.',
          style: TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: blue.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DAILY PROGRESS',
                style: TextStyle(color: cyan, letterSpacing: 1),
              ),
              const SizedBox(height: 12),
              Text(
                '${questSystem.completedCount} / ${questSystem.totalCount} QUESTS COMPLETED',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: questSystem.progress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: const Color(0xFF24354C),
                  color: cyan,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        ...questSystem.quests.map((quest) {
          final completed = questSystem.isCompleted(quest.id);

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: completed
                    ? Colors.greenAccent.withValues(alpha: 0.5)
                    : blue.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  completed ? Icons.check_circle : Icons.circle_outlined,
                  color: completed ? Colors.greenAccent : muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quest.name,
                        style: TextStyle(
                          color: completed ? muted : Colors.white,
                          fontWeight: FontWeight.w600,
                          decoration:
                              completed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${quest.durationMinutes} MIN',
                        style: const TextStyle(color: muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                if (!completed)
                  TextButton(
                    onPressed: () => questSystem.complete(quest.id),
                    child: const Text(
                      'COMPLETE',
                      style: TextStyle(color: cyan, fontSize: 11),
                    ),
                  ),
              ],
            ),
          );
        }),

        const SizedBox(height: 20),
      ],
    );
  }
}

// ============================================================
// STATUS PAGE
// ============================================================

class StatusPage extends StatelessWidget {
  final PlayerSystem player;

  const StatusPage({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SectionTitle(title: 'PLAYER STATUS'),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: blue.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.playerName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${player.rank} • ${player.title}',
                style: const TextStyle(color: cyan, fontSize: 11),
              ),
              const SizedBox(height: 16),
              _statusRow('LEVEL', '${player.level}'),
              _statusRow('XP', '${player.xp} / ${player.xpRequired}'),
              _statusRow('XP PROGRESS',
                  '${(player.xpProgress * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),

        const SizedBox(height: 22),

        const SectionTitle(title: 'ATTRIBUTES'),
        const SizedBox(height: 12),

        const Row(
          children: [
            Expanded(
              child: InfoCard(
                title: 'STRENGTH',
                value: '10',
                unit: 'STR',
                icon: Icons.fitness_center,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: InfoCard(
                title: 'INTELLECT',
                value: '10',
                unit: 'INT',
                icon: Icons.psychology,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 11)),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================================================
// SETTINGS PAGE (fully rewritten)
// ============================================================

class SettingsPage extends StatelessWidget {
  final PlayerSystem player;
  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;

  const SettingsPage({
    super.key,
    required this.player,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  Future<void> _editPlayerName(BuildContext context) async {
    final controller = TextEditingController(
      text: player.playerName,
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text(
            'CHANGE PLAYER NAME',
            style: TextStyle(color: cyan, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 25,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter your player name',
              hintStyle: TextStyle(color: muted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: blue),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: cyan),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'CANCEL',
                style: TextStyle(color: muted),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  controller.text.trim(),
                );
              },
              child: const Text(
                'SAVE',
                style: TextStyle(color: cyan),
              ),
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
      const SnackBar(
        content: Text('Player name updated successfully!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SectionTitle(title: 'SYSTEM SETTINGS'),
        const SizedBox(height: 12),

        Container(
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: blue.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.person_outline,
                  color: cyan,
                ),
                title: const Text(
                  'Player Name',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  player.playerName,
                  style: const TextStyle(color: muted),
                ),
                trailing: const Icon(
                  Icons.edit,
                  color: cyan,
                ),
                onTap: () => _editPlayerName(context),
              ),

              const Divider(
                color: Color(0xFF24354C),
                height: 1,
              ),

              ListTile(
                leading: const Icon(
                  Icons.notifications_outlined,
                  color: cyan,
                ),
                title: const Text(
                  'Notifications',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: const Text(
                  'Coming Soon',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),

              const Divider(
                color: Color(0xFF24354C),
                height: 1,
              ),

              ListTile(
                leading: const Icon(
                  Icons.dark_mode_outlined,
                  color: cyan,
                ),
                title: const Text(
                  'Dark Mode',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  isDarkMode ? 'Enabled' : 'Disabled',
                  style: const TextStyle(color: muted),
                ),
                trailing: Switch(
                  value: isDarkMode,
                  onChanged: onDarkModeChanged,
                  activeColor: cyan,
                ),
              ),

              const Divider(
                color: Color(0xFF24354C),
                height: 1,
              ),

              const ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: cyan,
                ),
                title: Text(
                  'System Version',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: Text(
                  '1.0.0',
                  style: TextStyle(color: muted),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }
}