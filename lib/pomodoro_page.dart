import 'package:flutter/material.dart';

import 'pomodoro_system.dart';

class PomodoroPage extends StatelessWidget {
  final PomodoroSystem pomodoro;

  const PomodoroPage({super.key, required this.pomodoro});

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  Future<void> _showSettings(BuildContext context) async {
    if (pomodoro.isRunning) return;
    final focus = TextEditingController(text: '${pomodoro.focusMinutes}');
    final shortBreak =
        TextEditingController(text: '${pomodoro.shortBreakMinutes}');
    final longBreak =
        TextEditingController(text: '${pomodoro.longBreakMinutes}');
    final interval =
        TextEditingController(text: '${pomodoro.longBreakEvery}');

    final values = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('POMODORO SETTINGS'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _durationField(focus, 'Focus minutes (1–180)'),
              _durationField(shortBreak, 'Short break (1–60)'),
              _durationField(longBreak, 'Long break (1–120)'),
              _durationField(interval, 'Long break after sessions (2–12)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = [
                int.tryParse(focus.text),
                int.tryParse(shortBreak.text),
                int.tryParse(longBreak.text),
                int.tryParse(interval.text),
              ];
              if (parsed.any((value) => value == null)) return;
              Navigator.pop(dialogContext, parsed.cast<int>());
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    focus.dispose();
    shortBreak.dispose();
    longBreak.dispose();
    interval.dispose();

    if (values == null) return;
    final saved = await pomodoro.setDurations(
      focus: values[0],
      shortBreak: values[1],
      longBreak: values[2],
      longBreakAfter: values[3],
    );
    if (!saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid settings or timer is running.')),
      );
    }
  }

  Widget _durationField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: pomodoro,
      builder: (context, _) {
        final totalSeconds = pomodoro.currentPhaseMinutes * 60;
        final progress = totalSeconds <= 0
            ? 0.0
            : (1 - pomodoro.remainingSeconds / totalSeconds)
                .clamp(0.0, 1.0);
        final timeColor = theme.colorScheme.secondary;

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'POMODORO',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: timeColor,
                  ),
                ),
                IconButton(
                  tooltip: pomodoro.isRunning
                      ? 'Pause the timer to edit settings'
                      : 'Pomodoro settings',
                  onPressed: pomodoro.isRunning
                      ? null
                      : () => _showSettings(context),
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 26,
                ),
                child: Column(
                  children: [
                    Text(
                      pomodoro.phaseLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: timeColor,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 230,
                      height: 230,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 9,
                              backgroundColor:
                                  theme.colorScheme.onSurface.withValues(
                                alpha: 0.10,
                              ),
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatTime(pomodoro.remainingSeconds),
                                style: theme.textTheme.displayMedium?.copyWith(
                                  fontWeight: FontWeight.w300,
                                  fontSize: 48,
                                ),
                              ),
                              Text(
                                pomodoro.isRunning ? 'IN PROGRESS' : 'READY',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  letterSpacing: 2,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: pomodoro.isRunning
                              ? pomodoro.pause
                              : pomodoro.start,
                          icon: Icon(pomodoro.isRunning
                              ? Icons.pause
                              : Icons.play_arrow),
                          label: Text(pomodoro.isRunning ? 'PAUSE' : 'START'),
                        ),
                        OutlinedButton.icon(
                          onPressed: pomodoro.stop,
                          icon: const Icon(Icons.stop),
                          label: const Text('STOP'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SESSION PROGRESS',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Completed focus sessions: '
                      '${pomodoro.completedFocusSessions}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Next phase: ${pomodoro.nextPhaseLabel}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${pomodoro.focusMinutes} min focus • '
                      '${pomodoro.shortBreakMinutes} min short break • '
                      '${pomodoro.longBreakMinutes} min long break',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Pomodoro is separate from Quest Timer and Rest. It adds completed '
              'focus minutes to study time only; it does not change XP, HP, MP, '
              'quests, penalties, or recovery.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }
}
