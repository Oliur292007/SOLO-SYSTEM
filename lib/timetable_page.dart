import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'timetable_system.dart';

class TimetablePage extends StatefulWidget {
  final TimetableSystem timetableSystem;

  const TimetablePage({
    super.key,
    required this.timetableSystem,
  });

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  static const MethodChannel _appRestrictionChannel =
      MethodChannel('solo_system/app_restriction');

  int selectedDay = DateTime.now().weekday;

  static const Color cyan = Color(0xFF00E5FF);
  static const Color blue = Color(0xFF00BFFF);

  Color get textColor => Theme.of(context).colorScheme.onSurface;

  Color get mutedColor =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF8295B3)
          : const Color(0xFF5A6B85);

  Future<List<Map<String, String>>> _loadEducationApps() async {
    try {
      final rawApps = await _appRestrictionChannel
          .invokeMethod<List<dynamic>>('getEducationApps');
      return (rawApps ?? []).map((item) {
        final app = Map<String, dynamic>.from(item as Map);
        return <String, String>{
          'packageName': app['packageName']?.toString() ?? '',
          'appName': app['appName']?.toString() ?? 'Unknown app',
        };
      }).where((app) => app['packageName']!.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _showScheduleDialog({
    StudyScheduleItem? existing,
  }) async {
    // Start discovery without waiting; show the schedule form immediately.
    final educationAppsFuture = _loadEducationApps();
    if (!mounted) return;

    final subjectController = TextEditingController(
      text: existing?.subject ?? '',
    );

    int day = existing?.dayOfWeek ?? selectedDay;
    int duration = existing?.durationMinutes ?? 60;
    bool isOptional = existing?.isOptional ?? false;
    final selectedEducationApps = <String>{
      ...?existing?.allowedEducationApps,
    };
    String educationSearch = '';
    bool isSaving = false;

    TimeOfDay startTime = existing != null
        ? TimeOfDay(
            hour: int.parse(existing.startTime.split(':')[0]),
            minute: int.parse(existing.startTime.split(':')[1]),
          )
        : const TimeOfDay(hour: 9, minute: 0);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> handleSave() async {
              if (isSaving) return;

              final subject = subjectController.text.trim();

              if (subject.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Enter a subject name')),
                );
                return;
              }

              if (isOptional && day != 5) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Optional schedules are only allowed on Friday.',
                    ),
                  ),
                );
                return;
              }

              final formattedTime =
                  '${startTime.hour.toString().padLeft(2, '0')}:'
                  '${startTime.minute.toString().padLeft(2, '0')}';

              setDialogState(() => isSaving = true);

              bool success;
              String? errorMessage;

              if (existing == null) {
                success = await widget.timetableSystem.addSchedule(
                  dayOfWeek: day,
                  subject: subject,
                  startTime: formattedTime,
                  durationMinutes: duration,
                  isOptional: isOptional,
                  allowedEducationApps: selectedEducationApps.toList(),
                );
                if (!success) {
                  errorMessage =
                      'A schedule with this subject & time already exists on this day.';
                }
              } else {
                success = await widget.timetableSystem.updateSchedule(
                  existing.id,
                  dayOfWeek: day,
                  subject: subject,
                  startTime: formattedTime,
                  durationMinutes: duration,
                  isOptional: isOptional,
                  allowedEducationApps: selectedEducationApps.toList(),
                );
                if (!success) {
                  errorMessage =
                      'Cannot update. Duplicate entry or invalid data.';
                }
              }

              if (!dialogContext.mounted) return;

              setDialogState(() => isSaving = false);

              if (success) {
                // Close the dialog route before rebuilding its parent page.
                // This avoids overlapping the dialog's inherited-widget teardown
                // with a parent AnimatedBuilder rebuild after timetable notifyListeners.
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  setState(() {
                    selectedDay = day;
                  });
                }
              } else {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(errorMessage ?? 'Unable to save.'),
                  ),
                );
              }
            }

            return AlertDialog(
              title: Text(
                existing == null ? 'ADD STUDY SCHEDULE' : 'EDIT SCHEDULE',
                style: const TextStyle(
                  color: cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: subjectController,
                      maxLength: 40,
                      enabled: !isSaving,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        hintText: 'Enter subject name',
                        prefixIcon: Icon(Icons.menu_book),
                      ),
                    ),
                    const SizedBox(height: 14),

                    DropdownButtonFormField<int>(
                      value: day,
                      decoration: const InputDecoration(
                        labelText: 'Day',
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      items: List.generate(
                        7,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text(TimetableSystem.weekdays[i]),
                        ),
                      ),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setDialogState(() {
                                  day = value;
                                  // Auto-disable optional if not Friday.
                                  if (isOptional && day != 5) {
                                    isOptional = false;
                                  }
                                });
                              }
                            },
                    ),

                    const SizedBox(height: 14),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time, color: cyan),
                      title: const Text('Start Time'),
                      subtitle: Text(startTime.format(context)),
                      trailing: const Icon(Icons.edit),
                      enabled: !isSaving,
                      onTap: isSaving
                          ? null
                          : () async {
                              final picked = await showTimePicker(
                                context: dialogContext,
                                initialTime: startTime,
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  startTime = picked;
                                });
                              }
                            },
                    ),

                    const SizedBox(height: 10),

                    DropdownButtonFormField<int>(
                      value: duration,
                      decoration: const InputDecoration(
                        labelText: 'Duration',
                        prefixIcon: Icon(Icons.timer),
                      ),
                      items: const [15, 30, 45, 60, 90, 120, 180]
                          .map(
                            (minutes) => DropdownMenuItem(
                              value: minutes,
                              child: Text('$minutes minutes'),
                            ),
                          )
                          .toList(),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setDialogState(() => duration = value);
                              }
                            },
                    ),

                    const SizedBox(height: 18),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ALLOWED EDUCATION APPS',
                            style: TextStyle(
                              color: cyan,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Apps selected in your saved schedules will keep Quest Timer running.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${selectedEducationApps.length} app(s) selected',
                            style: const TextStyle(
                              color: cyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      enabled: !isSaving,
                      onChanged: (value) =>
                          setDialogState(() => educationSearch = value),
                      decoration: const InputDecoration(
                        hintText: 'Search Education apps',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FutureBuilder<List<Map<String, String>>>(
                        future: educationAppsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Loading installed Education apps...',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            );
                          }

                          final educationApps = snapshot.data ?? [];
                          final query = educationSearch.trim().toLowerCase();
                          final filteredEducationApps = educationApps.where((app) {
                            return query.isEmpty ||
                                app['appName']!.toLowerCase().contains(query) ||
                                app['packageName']!.toLowerCase().contains(query);
                          }).toList();

                          if (educationApps.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(14),
                                child: Text(
                                  'No installed apps were identified in the Education category.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            );
                          }
                          if (filteredEducationApps.isEmpty) {
                            return const Center(
                              child: Text('No matching apps found.'),
                            );
                          }

                          return ListView.builder(
                            itemCount: filteredEducationApps.length,
                            itemBuilder: (context, index) {
                              final app = filteredEducationApps[index];
                              final packageName = app['packageName']!;
                              final appName = app['appName']!;
                              final selected =
                                  selectedEducationApps.contains(packageName);
                              return CheckboxListTile(
                                dense: true,
                                value: selected,
                                title: Text(
                                  appName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  packageName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                controlAffinity: ListTileControlAffinity.leading,
                                onChanged: isSaving
                                    ? null
                                    : (value) {
                                        setDialogState(() {
                                          if (value == true) {
                                            selectedEducationApps.add(packageName);
                                          } else {
                                            selectedEducationApps.remove(packageName);
                                          }
                                        });
                                      },
                              );
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Optional Schedule'),
                      subtitle: Text(
                        day == 5
                            ? 'Not required for daily completion (Friday only)'
                            : 'Optional is only allowed on Friday',
                      ),
                      value: isOptional,
                      activeThumbColor: cyan,
                      onChanged: (isSaving || day != 5)
                          ? null
                          : (value) {
                              setDialogState(() => isOptional = value);
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : handleSave,
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );

    subjectController.dispose();
  }

  Future<void> _deleteSchedule(StudyScheduleItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Schedule?'),
        content: Text('Delete ${item.subject} from your timetable?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success =
          await widget.timetableSystem.deleteSchedule(item.id);
      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete schedule.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final system = widget.timetableSystem;

    return AnimatedBuilder(
      animation: system,
      builder: (context, child) {
        if (!system.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final schedules = system.getSchedulesForDay(selectedDay);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showScheduleDialog(),
            backgroundColor: blue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('ADD SCHEDULE'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text(
                  'STUDY TIMETABLE',
                  style: TextStyle(
                    color: cyan,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Plan your path to becoming stronger.',
                  style: TextStyle(color: mutedColor),
                ),

                const SizedBox(height: 24),

                const Text(
                  'SELECT DAY',
                  style: TextStyle(
                    color: cyan,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  height: 66,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final day = index + 1;
                      final selected = selectedDay == day;

                      return GestureDetector(
                        onTap: () {
                          setState(() => selectedDay = day);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 55,
                          decoration: BoxDecoration(
                            color: selected
                                ? blue
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? cyan : mutedColor,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                TimetableSystem.weekdays[index]
                                    .substring(0, 3),
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : mutedColor,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '$day',
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 25),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      TimetableSystem.weekdays[selectedDay - 1].toUpperCase(),
                      style: const TextStyle(
                        color: cyan,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      '${schedules.length} SESSIONS',
                      style: TextStyle(color: mutedColor, fontSize: 11),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                if (schedules.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_available,
                          color: mutedColor,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'NO STUDY SCHEDULE',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add a session to organize your study day.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: mutedColor),
                        ),
                      ],
                    ),
                  )
                else
                  ...schedules.map((item) {
                    final parts = item.startTime.split(':');
                    final hour = int.parse(parts[0]);
                    final minute = int.parse(parts[1]);

                    final time = TimeOfDay(hour: hour, minute: minute);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: blue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 5,
                            height: 65,
                            decoration: BoxDecoration(
                              color: item.isOptional ? mutedColor : cyan,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.subject,
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '${time.format(context)} • ${item.durationMinutes} minutes',
                                  style: TextStyle(
                                    color: mutedColor,
                                    fontSize: 12,
                                  ),
                                ),
                                if (item.isOptional)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 5),
                                    child: Text(
                                      'OPTIONAL',
                                      style: TextStyle(
                                        color: cyan,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: mutedColor),
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showScheduleDialog(existing: item);
                              } else if (value == 'delete') {
                                _deleteSchedule(item);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 90),
              ],
            ),
          ),
        );
      },
    );
  }
}