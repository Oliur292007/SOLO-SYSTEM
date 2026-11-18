import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player_system.dart';
import 'quest_system.dart';
import 'study_timer.dart';
import 'timetable_system.dart';
import 'timetable_page.dart';

void main() {
  final player = PlayerSystem();
  final timetableSystem = TimetableSystem();
  final questSystem = QuestSystem(
    timetableSystem: timetableSystem,
  );
final studyTimer = StudyTimer();
  final timetableSystem = TimetableSystem();

  runApp(
    SoloSystemApp(
      player: player,
      questSystem: questSystem,
      studyTimer: studyTimer,
      timetableSystem: timetableSystem, // ✅ now passed
    ),
  );
}

// ============================================================
// THEME TOKENS (theme-aware — replaces hardcoded constants)
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
  final TimetableSystem timetableSystem; // ✅ added

  const SoloSystemApp({
    super.key,
    required this.player,
    required this.questSystem,
    required this.studyTimer,
    required this.timetableSystem, // ✅ added
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
        timetableSystem: widget.timetableSystem, // ✅ now in scope
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
  final TimetableSystem timetableSystem; // ✅ added

  const SystemHome({
    super.key,
    required this.player,
    required this.questSystem,
    required this.isDarkMode,
    required this.onDarkModeChanged,
    required this.studyTimer,
    required this.timetableSystem, // ✅ added
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
    widget.studyTimer.loadTimer();
    widget.timetableSystem.loadTimetable(); // ✅ still works (now in scope)
  }

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.player,
        widget.questSystem,
        widget.studyTimer, // ✅ added — timer state refreshes UI
      ]),
      builder: (context, child) {
        final pages = [
          DashboardPage(
            player: widget.player,
            questSystem: widget.questSystem,
            timetableSystem: widget.timetableSystem, 
          ),
          QuestPage(
            player: widget.player,
            questSystem: widget.questSystem,
            studyTimer: widget.studyTimer,
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
            child: widget.player.isLoaded && widget.questSystem.isLoaded && widget.timetableSystem.isLoaded
                ? pages[selectedIndex]
                : Center(
                    child: CircularProgressIndicator(color: c.cyan),
                  ),
          ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: c.panel,            // ✅ theme-aware
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

class DashboardPage extends StatelessWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;
  final TimetableSystem timetableSystem; 

  const DashboardPage({
    super.key,
    required this.player,
    required this.questSystem,
    required this.timetableSystem,
  });

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

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
                  'WELCOME BACK, PLAYER.',
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
              child: Icon(
                Icons.notifications_active_outlined,
                color: c.cyan,
              ),
            ),
          ],
        ),

        const SizedBox(height: 25),

        // PLAYER PROFILE
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
                color: Color(0xFF00E5FF),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        
        AnimatedBuilder(
          animation: timetableSystem,
          builder: (context, child) {
            final todaySchedules = timetableSystem.getSchedulesForDay(
              DateTime.now().weekday,
            );

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
                    Text(
                      "No study schedule for today.",
                      style: TextStyle(color: c.muted),
                    )
                  else
                    ...todaySchedules.take(3).map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 17,
                              color: c.cyan,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.subject,
                                style: TextStyle(color: c.text),
                              ),
                            ),
                            Text(
                              item.startTime,
                              style: TextStyle(color: c.muted),
                            ),
                          ],
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
            'SYSTEM VERSION 1.0.0',
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
    final c = SystemColors.of(context);

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
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: color)),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            value,
            style: TextStyle(
              color: c.text,
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
    final c = SystemColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.circle_outlined,
            color: completed ? Colors.green : c.muted,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: completed ? c.muted : c.text,
                decoration: completed ? TextDecoration.lineThrough : null,
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

class QuestPage extends StatelessWidget {
  final PlayerSystem player;
  final QuestSystem questSystem;
  final StudyTimer studyTimer;

  const QuestPage({
    super.key,
    required this.player,
    required this.questSystem,
    required this.studyTimer,
  });

  @override
  Widget build(BuildContext context) {
    final c = SystemColors.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([questSystem, studyTimer]),
      builder: (context, child) {
        final activeId = studyTimer.activeQuestId;

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
            const SizedBox(height: 20),

            if (activeId != null)
              Container(
                padding: const EdgeInsets.all(18),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.cyan),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACTIVE STUDY SESSION',
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      studyTimer.formattedTime,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (studyTimer.isFinished)
                      Text(
                        'Timer completed! Claim your XP.',
                        style: TextStyle(color: c.cyan),
                      )
                    else
                      Text(
                        studyTimer.isRunning ? 'Timer Running' : 'Timer Paused',
                        style: TextStyle(color: c.muted),
                      ),

                    const SizedBox(height: 14),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (studyTimer.isRunning)
                          ElevatedButton(
                            onPressed: () => studyTimer.pause(),
                            child: const Text('Pause'),
                          )
                        else if (!studyTimer.isFinished)
                          ElevatedButton(
                            onPressed: () => studyTimer.resume(),
                            child: const Text('Resume'),
                          ),

                        if (studyTimer.isFinished)
                          ElevatedButton(
                            onPressed: () async {
                              final xp = await studyTimer.completeQuest(
                                questSystem,
                                player,
                              );

                              if (context.mounted && xp != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Quest completed! +$xp XP'),
                                  ),
                                );
                              }
                            },
                            child: const Text('Claim XP'),
                          ),

                        OutlinedButton(
                          onPressed: () => studyTimer.cancel(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            ...questSystem.quests.map((quest) {
              final completed = questSystem.isCompleted(quest.id);
              final isActive = activeId == quest.id;
              final anotherActive = activeId != null && !isActive;

              return Container(
                key: ValueKey(quest.id),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isActive
                        ? c.cyan
                        : c.text.withValues(alpha: 0.10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quest.name,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${quest.durationMinutes} minutes • ${quest.xpReward} XP',
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 12),

                    if (completed)
                      Text(
                        'COMPLETED',
                        style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else if (isActive)
                      Text(
                        'ACTIVE SESSION',
                        style: TextStyle(color: c.cyan),
                      )
                    else
                      ElevatedButton(
                        onPressed: anotherActive
                            ? null
                            : () => studyTimer.start(
                                  questId: quest.id,
                                  durationMinutes: quest.durationMinutes,
                                ),
                        child: const Text('Start Study'),
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
}

class StatusPage extends StatelessWidget {
  final PlayerSystem player;

  const StatusPage({super.key, required this.player});

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
                  activeThumbColor: c.cyan,   // ✅ fixed deprecation
                ),
              ),

              Divider(color: c.divider, height: 1),

              ListTile(
                leading: Icon(Icons.info_outline, color: c.cyan),
                title: Text('System Version', style: TextStyle(color: c.text)),
                trailing: Text('1.0.0', style: TextStyle(color: c.muted)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }
}

