import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart' show SystemColors;
import 'supabase_service.dart';

const MethodChannel _screenTimeChannel =
    MethodChannel('solo_system/app_restriction');

class ScreenTimePage extends StatefulWidget {
  final SupabaseService supabaseService;

  const ScreenTimePage({super.key, required this.supabaseService});

  @override
  State<ScreenTimePage> createState() => _ScreenTimePageState();
}

class _ScreenTimePageState extends State<ScreenTimePage>
    with WidgetsBindingObserver {
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _screenTimeChannel.invokeMapMethod<String, dynamic>(
        'getDailyUsage',
      );
      if (!mounted) return;
      setState(() {
        _summary = result ?? {};
        _loading = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? 'Could not read app usage.';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openUsageAccess() async {
    try {
      await _screenTimeChannel.invokeMethod<void>('openUsageAccessSettings');
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Usage Access: ${error.message}')),
      );
    }
  }

  String _duration(int milliseconds) {
    final minutes = (milliseconds ~/ 60000);
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '${remainder}m';
    return '${hours}h ${remainder}m';
  }

  Widget _usageCard({
    required SystemColors colors,
    required String title,
    required String used,
    required int usedMs,
    required int limitMinutes,
    required IconData icon,
  }) {
    final limitMs = limitMinutes * 60000;
    final progress = limitMs <= 0 ? 0.0 : (usedMs / limitMs).clamp(0.0, 1.0);
    final exceeded = usedMs >= limitMs;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.blue.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: exceeded ? Colors.orangeAccent : colors.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
              ),
              Text(used,
                  style: TextStyle(
                      color: exceeded ? Colors.orangeAccent : colors.cyan,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(
                exceeded ? Colors.orangeAccent : colors.cyan,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Daily limit: ${limitMinutes ~/ 60} hours'
            '${limitMinutes % 60 == 0 ? '' : ' ${limitMinutes % 60} minutes'}',
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SystemColors.of(context);
    final hasAccess = _summary['hasUsageAccess'] == true;
    final socialMs = (_summary['socialMediaMs'] as num?)?.toInt() ?? 0;
    final gamesMs = (_summary['gamesMs'] as num?)?.toInt() ?? 0;
    final socialLimit = (_summary['socialLimitMinutes'] as num?)?.toInt() ??
        widget.supabaseService.socialMediaDailyLimitMinutes;
    final gameLimit = (_summary['gameLimitMinutes'] as num?)?.toInt() ??
        widget.supabaseService.gamesDailyLimitMinutes;
    final apps = (_summary['apps'] as List<dynamic>?) ?? [];

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        foregroundColor: colors.text,
        title: const Text('SCREEN TIME'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh usage',
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.cyan))
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                if (!hasAccess) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orangeAccent),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.insights, color: Colors.orangeAccent),
                        const SizedBox(height: 8),
                        Text('USAGE ACCESS REQUIRED',
                            style: TextStyle(
                                color: colors.text,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          'Allow Shadow Learner to access app usage in Android Settings. '
                          'This permission is required to calculate daily app time.',
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _openUsageAccess,
                          child: const Text('OPEN USAGE ACCESS SETTINGS'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Text('TODAY',
                      style: TextStyle(
                          color: colors.cyan,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  _usageCard(
                    colors: colors,
                    title: 'SOCIAL MEDIA',
                    used: _duration(socialMs),
                    usedMs: socialMs,
                    limitMinutes: socialLimit,
                    icon: Icons.people_alt_outlined,
                  ),
                  const SizedBox(height: 12),
                  _usageCard(
                    colors: colors,
                    title: 'GAMES',
                    used: _duration(gamesMs),
                    usedMs: gamesMs,
                    limitMinutes: gameLimit,
                    icon: Icons.sports_esports_outlined,
                  ),
                  const SizedBox(height: 22),
                  Text('AUTOMATICALLY DETECTED APPS',
                      style: TextStyle(
                          color: colors.cyan,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 8),
                  if (apps.isEmpty)
                    Text('No apps in the tracked categories have usage today.',
                        style: TextStyle(color: colors.muted, fontSize: 12))
                  else
                    ...apps.map((item) {
                      final app = Map<String, dynamic>.from(item as Map);
                      final category = app['category']?.toString() ?? 'other';
                      final usage = (app['usageMs'] as num?)?.toInt() ?? 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          category == 'game'
                              ? Icons.sports_esports
                              : category == 'education'
                                  ? Icons.school_outlined
                                  : Icons.people_alt_outlined,
                          color: category == 'education'
                              ? Colors.greenAccent
                              : colors.cyan,
                        ),
                        title: Text(
                          app['appName']?.toString() ?? 'Unknown app',
                          style: TextStyle(color: colors.text, fontSize: 13),
                        ),
                        subtitle: Text(
                          '$category • ${app['packageName'] ?? ''}',
                          style: TextStyle(color: colors.muted, fontSize: 9),
                        ),
                        trailing: Text(_duration(usage),
                            style: TextStyle(color: colors.cyan, fontSize: 12)),
                      );
                    }),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'APP CATEGORY MANAGEMENT\n'
                    'Automatic detection selects social media, games and education apps. '
                    'To override an app manually in Supabase, edit public.whitelist.screen_time_category: '
                    'social_media, game, education or excluded. Keep category = allowed for apps '
                    'that must remain available during Study Protection. YouTube uses youtube_special.\n\n'
                    'Usage totals reset at local midnight. Limits are enforced by Android Accessibility Service.',
                    style: TextStyle(color: colors.muted, fontSize: 11, height: 1.5),
                  ),
                ),
              ],
            ),
    );
  }
}
