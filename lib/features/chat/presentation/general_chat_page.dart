import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/token_storage.dart';
import '../../../core/utils/logger.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../data/chat_repository.dart';
import 'general_chat_thread_page.dart';

class GeneralChatPage extends ConsumerStatefulWidget {
  const GeneralChatPage({super.key});

  @override
  ConsumerState<GeneralChatPage> createState() => _GeneralChatPageState();
}

class _GeneralChatPageState extends ConsumerState<GeneralChatPage> {
  bool _loading = true;
  List<ChatConversation> _conversations = const [];
  Timer? _pollTimer;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final token = await ref.read(tokenStorageProvider).readToken();
      if (token == null || token.isEmpty) return;
      final parts = token.split('.');
      if (parts.length < 2) return;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      final id = int.tryParse(claims['sub']?.toString() ?? '');
      if (!mounted) return;
      setState(() => _currentUserId = id);
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await ref.read(chatRepositoryProvider).fetchConversations();
      list.sort((a, b) {
        final at = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _loading = false;
      });
    } catch (e, st) {
      Logger.e('General conversations load failed', e, st);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openConversation(ChatConversation conversation) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeneralChatThreadPage(
          conversationId: conversation.id,
          title: conversation.displayTitle(currentUserId: _currentUserId),
        ),
      ),
    );
    await _load();
  }

  Future<void> _showStartChatSheet() async {
    final known = <int, ChatParticipant>{};
    for (final conv in _conversations) {
      for (final p in conv.participants) {
        if (_currentUserId != null && p.id == _currentUserId) continue;
        known[p.id] = p;
      }
    }
    final participants = known.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final manualController = TextEditingController();
    int? selectedId;
    String? title;

    final created = await showModalBottomSheet<ChatConversation>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.lg,
              bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start Direct Chat',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (participants.isNotEmpty) ...[
                  Text(
                    'Select User',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      itemCount: participants.length,
                      itemBuilder: (context, index) {
                        final p = participants[index];
                        final isSelected = selectedId == p.id;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.name),
                          subtitle: Text(p.role.isEmpty ? 'user' : p.role),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: AppColors.successGreen)
                              : null,
                          onTap: () {
                            setModalState(() {
                              selectedId = p.id;
                              manualController.clear();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
                TextField(
                  controller: manualController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Or enter user ID',
                    hintText: 'e.g. 12',
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Conversation title (optional)',
                  ),
                  onChanged: (value) => title = value,
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final manual = int.tryParse(manualController.text.trim());
                      final target = manual ?? selectedId;
                      if (target == null) return;
                      try {
                        final conv = await ref.read(chatRepositoryProvider).createConversation(
                              title: title,
                              participantIds: [target],
                            );
                        if (!context.mounted) return;
                        Navigator.pop(context, conv);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not start chat: $e')),
                        );
                      }
                    },
                    child: const Text('Create Chat'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    manualController.dispose();

    if (created == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeneralChatThreadPage(
          conversationId: created.id,
          title: created.displayTitle(currentUserId: _currentUserId),
        ),
      ),
    );
    await _load();
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '—';
    final t = time.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            onPressed: _showStartChatSheet,
            icon: const Icon(Icons.add_comment_outlined),
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
          else if (_conversations.isEmpty)
            RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: const [
                  SizedBox(height: 220),
                  Center(child: Text('No conversations yet. Tap + to start one.')),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final c = _conversations[index];
                  final unread = c.unreadCount;
                  return ListTile(
                    onTap: () => _openConversation(c),
                    leading: CircleAvatar(
                      backgroundColor: unread > 0
                          ? AppColors.primaryBlue
                          : AppColors.neutral300,
                      child: Icon(
                        Icons.chat_bubble_outline,
                        color: unread > 0 ? Colors.white : AppColors.neutral700,
                      ),
                    ),
                    title: Text(
                      c.displayTitle(currentUserId: _currentUserId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      c.lastMessageBody?.trim().isNotEmpty == true
                          ? c.lastMessageBody!
                          : '${c.participants.length} participant(s)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _timeLabel(c.lastMessageAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        if (unread > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.errorRed,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showStartChatSheet,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New Chat'),
      ),
    );
  }
}
