import 'package:flutter/material.dart';
import 'player_system.dart';

void main() {
  final player = PlayerSystem();
  runApp(SoloSystemApp(player: player));
}

const Color bg = Color(0xFF050B18);
const Color panel = Color(0xFF0B1930);
const Color blue = Color(0xFF00BFFF);
const Color cyan = Color(0xFF00E5FF);
const Color muted = Color(0xFF8295B3);

class SoloSystemApp extends StatelessWidget {
  final PlayerSystem player;

  const SoloSystemApp({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SOLO SYSTEM',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: blue,
          secondary: cyan,
          surface: panel,
        ),
        useMaterial3: true,
      ),
      home: SystemHome(player: player),
    );
  }
}

class SystemHome extends StatefulWidget {
  final PlayerSystem player;

  const SystemHome({super.key, required this.player});

  @override
  State<SystemHome> createState() => _SystemHomeState();
}

class _SystemHomeState extends State<SystemHome> {
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.player.loadPlayer();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, child) {
        final pages = [
          DashboardPage(player: widget.player),
          QuestPage(player: widget.player),
          StatusPage(player: widget.player),
          SettingsPage(player: widget.player),
        ];

        return Scaffold(
          body: SafeArea(
            child: widget.player.isLoaded
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

// DASHBOARD

class DashboardPage extends StatelessWidget {
  final PlayerSystem player;

  const DashboardPage({super.key, required this.player});

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
                  value: player.xpProgress,
                  minHeight: 9,
                  backgroundColor: const Color(0xFF24354C),
                  color: cyan,
                ),
              ),

              const SizedBox(height: 9),

              Text(
                '${player.xpRequired - player.xp} XP REQUIRED FOR NEXT LEVEL',
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
                    'TODAY\'S OBJECTIVES',
                    style: TextStyle(
                      color: cyan,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Quest Completion',
                      style: TextStyle(color: muted, fontSize: 12)),
                  Text('2 / 5',
                      style: TextStyle(color: cyan, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: const LinearProgressIndicator(
                  value: 0.4,
                  minHeight: 7,
                  backgroundColor: Color(0xFF24354C),
                  color: blue,
                ),
              ),
              const SizedBox(height: 15),
              const QuestRow(
                name: 'Mathematics',
                duration: '1 Hour',
                completed: true,
              ),
              const QuestRow(
                name: 'Physics',
                duration: '1 Hour',
                completed: true,
              ),
              const QuestRow(
                name: 'Chemistry',
                duration: '1 Hour',
                completed: false,
              ),
              const QuestRow(
                name: 'English',
                duration: '30 Min',
                completed: false,
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

// REUSABLE WIDGETS

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
                decoration:
                    completed ? TextDecoration.lineThrough : null,
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
          Text(title,
              style: const TextStyle(color: muted, fontSize: 9)),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(unit,
              style: const TextStyle(color: muted, fontSize: 9)),
        ],
      ),
    );
  }
}

// OTHER PAGES

class QuestPage extends StatelessWidget {
  final PlayerSystem player;

  const QuestPage({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'QUEST CENTER\n${player.playerName.toUpperCase()}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: cyan, letterSpacing: 2),
      ),
    );
  }
}

class StatusPage extends StatelessWidget {
  final PlayerSystem player;

  const StatusPage({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(title: 'PLAYER STATUS'),
        const SizedBox(height: 20),
        VitalCard(
          title: 'PLAYER LEVEL',
          value: 'LV. ${player.level}',
          icon: Icons.military_tech,
          color: cyan,
        ),
        const SizedBox(height: 14),
        VitalCard(
          title: 'CURRENT RANK',
          value: player.rank,
          icon: Icons.shield,
          color: blue,
        ),
        const SizedBox(height: 14),
        VitalCard(
          title: 'PLAYER TITLE',
          value: player.title,
          icon: Icons.workspace_premium,
          color: Colors.amber,
        ),
        const SizedBox(height: 14),
        VitalCard(
          title: 'TOTAL XP EARNED',
          value: '${player.totalXp} XP',
          icon: Icons.bolt,
          color: cyan,
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  final PlayerSystem player;

  const SettingsPage({super.key, required this.player});

  Future<void> editPlayerName(BuildContext context) async {
    final controller = TextEditingController(
      text: player.playerName == 'Player' ? '' : player.playerName,
    );

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text(
            'PLAYER IDENTITY',
            style: TextStyle(color: cyan),
          ),
          content: TextField(
            controller: controller,
            maxLength: 30,
            decoration: const InputDecoration(
              hintText: 'Enter your name',
              labelText: 'Player Name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();

                if (name.isEmpty) return;

                await player.setPlayerName(name);

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Player name saved successfully!'),
                    ),
                  );
                }
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(title: 'SETTINGS'),
        const SizedBox(height: 20),
        ListTile(
          tileColor: panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: blue.withValues(alpha: 0.35)),
          ),
          leading: const Icon(Icons.badge_outlined, color: cyan),
          title: const Text(
            'Player Name',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            player.playerName,
            style: const TextStyle(color: muted),
          ),
          trailing: const Icon(Icons.edit, color: cyan),
          onTap: () => editPlayerName(context),
        ),
      ],
    );
  }
}