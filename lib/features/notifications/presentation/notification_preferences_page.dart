import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../data/notifications_repository.dart';

class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  NotificationPreferences _prefs = NotificationPreferences(typeEnabled: {});

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await ref
          .read(notificationsRepositoryProvider)
          .fetchPreferences();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _prefs.quietHoursStart : _prefs.quietHoursEnd;
    TimeOfDay initial = const TimeOfDay(hour: 22, minute: 0);
    if (current != null && current.contains(':')) {
      final parts = current.split(':');
      final h = int.tryParse(parts[0]) ?? 22;
      final m = int.tryParse(parts[1]) ?? 0;
      initial = TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _prefs = NotificationPreferences(
        typeEnabled: _prefs.typeEnabled,
        quietHoursStart: start ? value : _prefs.quietHoursStart,
        quietHoursEnd: start ? _prefs.quietHoursEnd : value,
      );
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(notificationsRepositoryProvider).updatePreferences(_prefs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences updated.')),
      );
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  String _labelForType(String type) {
    return type
        .split(RegExp(r'[_\.\-]+'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF2F7FF), Color(0xFFFFFFFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (_error != null) ...[
                  AlertBanner(type: AlertType.error, message: _error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                SectionCard(
                  title: 'Per-Type Preferences',
                  children: [
                    if (_prefs.typeEnabled.isEmpty)
                      const Text('No specific notification type settings.')
                    else
                      ..._prefs.typeEnabled.entries.map((entry) {
                        return SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_labelForType(entry.key)),
                          subtitle: Text(entry.key),
                          value: entry.value,
                          onChanged: (value) {
                            setState(() {
                              final next = Map<String, bool>.from(
                                _prefs.typeEnabled,
                              );
                              next[entry.key] = value;
                              _prefs = NotificationPreferences(
                                typeEnabled: next,
                                quietHoursStart: _prefs.quietHoursStart,
                                quietHoursEnd: _prefs.quietHoursEnd,
                              );
                            });
                          },
                        );
                      }),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  title: 'Quiet Hours',
                  children: [
                    InfoRow(
                      label: 'Start',
                      value: _prefs.quietHoursStart ?? 'Not set',
                    ),
                    InfoRow(
                      label: 'End',
                      value: _prefs.quietHoursEnd ?? 'Not set',
                      showDivider: false,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickTime(start: true),
                            child: const Text('Set Start'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickTime(start: false),
                            child: const Text('Set End'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save Preferences'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
