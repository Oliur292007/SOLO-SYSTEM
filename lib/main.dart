
import 'package:flutter/material.dart';

void main() {
  runApp(const SoloSystemApp());
}

const Color bg = Color(0xFF050B18);
const Color panel = Color(0xFF0B1930);
const Color blue = Color(0xFF00BFFF);
const Color cyan = Color(0xFF00E5FF);
const Color muted = Color(0xFF8295B3);

class SoloSystemApp extends StatelessWidget {
  const SoloSystemApp({super.key});

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
      home: const SystemHome(),
    );
  }
}

class SystemHome extends StatefulWidget {
  const SystemHome({super.key});

  @override
  State<SystemHome> createState() => _SystemHomeState();
}

class _SystemHomeState extends State<SystemHome> {
  int selectedIndex = 0;

  final List<Widget> pages = const [
    DashboardPage(),
    QuestPage(),
    StatusPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: pages[selectedIndex],
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
  }
}

// DASHBOARD

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PLAYER',
                          style: TextStyle(
                            color: muted,
                            fontSize: 10,
                            letterSpacing: 2,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'SHADOW HUNTER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'CLASS: BEGINNER',
                          style: TextStyle(
                            color: cyan,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'LV. 01',
                    style: TextStyle(
                      color: cyan,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('EXPERIENCE POINTS',
                      style: TextStyle(color: muted, fontSize: 10)),
                  Text('250 / 1000 XP',
                      style: TextStyle(color: cyan, fontSize: 11)),
                ],
              ),

              const SizedBox(height: 9),

              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const LinearProgressIndicator(
                  value: 0.25,
                  minHeight: 9,
                  backgroundColor: Color(0xFF24354C),
                  color: cyan,
                ),
              ),

              const SizedBox(height: 9),

              const Text(
                '750 XP REQUIRED FOR NEXT LEVEL',
                style: TextStyle(color: muted, fontSize: 9),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        const SectionTitle(title: 'PLAYER VITALS'),

        const SizedBox(height: 12),

        Row(
          children: const [
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
              Row(
                children: const [
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

        Row(
          children: const [
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

// OTHER PAGES - TEMPORARY

class QuestPage extends StatelessWidget {
  const QuestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'QUEST CENTER',
      subtitle: 'YOUR DAILY MISSIONS WILL APPEAR HERE.',
      icon: Icons.assignment,
    );
  }
}

class StatusPage extends StatelessWidget {
  const StatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'PLAYER STATUS',
      subtitle: 'YOUR PLAYER INFORMATION.',
      icon: Icons.person,
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'SYSTEM SETTINGS',
      subtitle: 'CONFIGURE YOUR SYSTEM.',
      icon: Icons.settings,
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const PlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: cyan, size: 65),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: cyan,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
