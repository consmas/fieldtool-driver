import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../chat/presentation/general_chat_page.dart';
import '../../chat/presentation/general_chat_thread_page.dart';
import '../../chat/presentation/trip_chat_page.dart';
import '../../maintenance/presentation/maintenance_page.dart';
import '../../offline/presentation/offline_sync_queue_page.dart';
import '../../trips/presentation/trip_detail_page.dart';
import '../data/notifications_repository.dart';
import 'notification_preferences_page.dart';

class NotificationsInboxPage extends ConsumerStatefulWidget {
  const NotificationsInboxPage({super.key});

  @override
  ConsumerState<NotificationsInboxPage> createState() =>
      _NotificationsInboxPageState();
}

class _NotificationsInboxPageState
    extends ConsumerState<NotificationsInboxPage> {
  bool _loading = true;
  String? _error;
  bool _groupByDay = true;
  Timer? _pollTimer;
  List<DriverNotification> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await ref
          .read(notificationsRepositoryProvider)
          .fetchNotifications();
      if (!mounted) return;
      setState(() {
        _items = list.where((n) => !n.archived).toList();
        _loading = false;
      });
      ref.invalidate(notificationsUnreadCountProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _dateKey(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  String _timeLabel(DateTime t) {
    final d = t.toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _markRead(DriverNotification n) async {
    if (n.read) return;
    try {
      await ref.read(notificationsRepositoryProvider).markAsRead(n.id);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((e) => e.id == n.id ? e.copyWith(read: true) : e)
            .toList();
      });
      ref.invalidate(notificationsUnreadCountProvider);
    } catch (_) {}
  }

  Future<void> _archive(DriverNotification n) async {
    try {
      await ref.read(notificationsRepositoryProvider).archive(n.id);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != n.id).toList());
      ref.invalidate(notificationsUnreadCountProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Archive failed: $e')));
    }
  }

  Future<void> _delete(DriverNotification n) async {
    try {
      await ref.read(notificationsRepositoryProvider).delete(n.id);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != n.id).toList());
      ref.invalidate(notificationsUnreadCountProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  int? _extractTripId(DriverNotification n) {
    final tripId = n.data['trip_id'] ?? n.data['tripId'] ?? n.data['id'];
    if (tripId is int) return tripId;
    if (tripId is num) return tripId.toInt();
    if (tripId is String) return int.tryParse(tripId);
    final url = n.actionUrl ?? '';
    final m = RegExp(r'/trips/(\d+)').firstMatch(url);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  int? _extractConversationId(DriverNotification n) {
    final id = n.data['conversation_id'] ?? n.data['conversationId'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    if (id is String) return int.tryParse(id);
    return null;
  }

  Future<void> _handleTap(DriverNotification n) async {
    await _markRead(n);
    if (!mounted) return;
    final action = (n.actionType ?? '').toLowerCase();
    final url = (n.actionUrl ?? '').trim();
    final tripId = _extractTripId(n);
    final convId = _extractConversationId(n);

    if (tripId != null &&
        (action.contains('trip') || url.contains('/trips/$tripId'))) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TripDetailPage(tripId: tripId)),
      );
      return;
    }

    if (tripId != null &&
        (action.contains('dispatch') || action.contains('chat'))) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TripChatPage(
            tripId: tripId,
            tripReference: '#$tripId',
            tripStatus: '',
          ),
        ),
      );
      return;
    }

    if (action.contains('conversation') && convId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GeneralChatThreadPage(
            conversationId: convId,
            title: 'Conversation #$convId',
          ),
        ),
      );
      return;
    }

    if (action == 'chat' || action == 'general_chat') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GeneralChatPage()),
      );
      return;
    }

    if (action.contains('sync')) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OfflineSyncQueuePage()),
      );
      return;
    }

    if (action.contains('maintenance')) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MaintenancePage()),
      );
      return;
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<DriverNotification>>{};
    for (final item in _items) {
      final key = _groupByDay ? _dateKey(item.createdAt) : 'All';
      groups.putIfAbsent(key, () => <DriverNotification>[]).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'group') {
                setState(() => _groupByDay = !_groupByDay);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'group',
                child: Text(_groupByDay ? 'Ungroup' : 'Group by day'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationPreferencesPage(),
                ),
              );
              if (!mounted) return;
              _load(silent: true);
            },
          ),
        ],
      ),
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
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AlertBanner(type: AlertType.error, message: _error!),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_items.isEmpty)
            RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: const [
                  SizedBox(height: 220),
                  Center(child: Text('No notifications yet.')),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: groups.entries.map((entry) {
                  final key = entry.key;
                  final list = entry.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_groupByDay) ...[
                        Text(
                          key,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      ...list.map((n) {
                        return Dismissible(
                          key: ValueKey('notif_${n.id}'),
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.accentOrangeLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.archive_outlined,
                              color: AppColors.accentOrangeDark,
                            ),
                          ),
                          secondaryBackground: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.errorRedLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: AppColors.errorRed,
                            ),
                          ),
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.startToEnd) {
                              await _archive(n);
                            } else {
                              await _delete(n);
                            }
                            return true;
                          },
                          child: Container(
                            margin: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: SectionCard(
                              title: n.notificationType ?? 'Notification',
                              accentColor: n.read
                                  ? AppColors.neutral300
                                  : AppColors.primaryBlue,
                              onTap: () => _handleTap(n),
                              children: [
                                Text(
                                  n.title,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(n.body),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      _timeLabel(n.createdAt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.textMuted,
                                          ),
                                    ),
                                    const Spacer(),
                                    if (!n.read)
                                      TextButton(
                                        onPressed: () => _markRead(n),
                                        child: const Text('Mark read'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
