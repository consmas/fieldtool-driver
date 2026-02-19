import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/token_storage.dart';
import '../../../core/utils/logger.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../data/chat_repository.dart';

class GeneralChatThreadPage extends ConsumerStatefulWidget {
  const GeneralChatThreadPage({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final int conversationId;
  final String title;

  @override
  ConsumerState<GeneralChatThreadPage> createState() =>
      _GeneralChatThreadPageState();
}

class _GeneralChatThreadPageState extends ConsumerState<GeneralChatThreadPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_UiMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  int? _currentUserId;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
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
      if (!mounted) return;
      setState(() => _currentUserId = int.tryParse(claims['sub']?.toString() ?? ''));
    } catch (_) {}
  }

  bool _isMine(ChatMessage m) {
    if (_currentUserId != null && m.senderId == _currentUserId) return true;
    return m.senderRole.contains('driver');
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final thread = await ref
          .read(chatRepositoryProvider)
          .fetchConversationThread(widget.conversationId);
      final failedLocals = _messages.where((m) => m.localId != null && m.failed).toList();
      _messages
        ..clear()
        ..addAll(thread.messages.map((m) => _UiMessage.fromRemote(m, mine: _isMine(m))))
        ..addAll(failedLocals)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      await ref.read(chatRepositoryProvider).markConversationRead(widget.conversationId);

      if (!mounted) return;
      setState(() => _loading = false);
      _scrollBottom();
    } catch (e, st) {
      Logger.e('Conversation thread load failed', e, st);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final local = _UiMessage.localOutgoing(text);
    setState(() {
      _messages.add(local);
      _sending = true;
      _input.clear();
    });
    _scrollBottom();

    try {
      final sent = await ref.read(chatRepositoryProvider).sendConversationMessage(
            conversationId: widget.conversationId,
            body: text,
          );
      final idx = _messages.indexWhere((m) => m.localId == local.localId);
      if (idx != -1) {
        _messages[idx] = _UiMessage.fromRemote(sent, mine: true);
      }
      if (!mounted) return;
      setState(() => _sending = false);
      _scrollBottom();
      await _load(silent: true);
    } catch (e, st) {
      Logger.e('Conversation send failed', e, st);
      final idx = _messages.indexWhere((m) => m.localId == local.localId);
      if (idx != -1) {
        _messages[idx].failed = true;
        _messages[idx].sending = false;
      }
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  Future<void> _retry(_UiMessage msg) async {
    if (!msg.failed) return;
    setState(() {
      msg.failed = false;
      msg.sending = true;
    });
    try {
      final sent = await ref.read(chatRepositoryProvider).sendConversationMessage(
            conversationId: widget.conversationId,
            body: msg.body,
          );
      final idx = _messages.indexWhere((m) => m.localId == msg.localId);
      if (idx != -1) _messages[idx] = _UiMessage.fromRemote(sent, mine: true);
      if (!mounted) return;
      setState(() {});
      await _load(silent: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        msg.failed = true;
        msg.sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
          Column(
            children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: _messages.length,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemBuilder: (context, index) => _Bubble(
                            message: _messages[index],
                            onRetry: () => _retry(_messages[index]),
                          ),
                        ),
                      ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppColors.neutral200)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          maxLines: 4,
                          minLines: 1,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        onPressed: _input.text.trim().isEmpty ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onRetry});

  final _UiMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final bg = mine ? AppColors.primaryBlue : Colors.white;
    final fg = mine ? Colors.white : AppColors.textPrimary;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: mine ? null : Border.all(color: AppColors.neutral200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.body, style: TextStyle(color: fg)),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: mine ? Colors.white70 : AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                if (message.sending) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: mine ? Colors.white70 : AppColors.primaryBlue,
                    ),
                  ),
                ],
              ],
            ),
            if (message.failed) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onRetry,
                child: Text(
                  'Failed to send. Tap to retry.',
                  style: TextStyle(
                    color: mine ? Colors.white : AppColors.errorRed,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UiMessage {
  _UiMessage({
    required this.id,
    required this.localId,
    required this.body,
    required this.createdAt,
    required this.mine,
    required this.sending,
    required this.failed,
  });

  final int? id;
  final String? localId;
  final String body;
  final DateTime createdAt;
  final bool mine;
  bool sending;
  bool failed;

  factory _UiMessage.fromRemote(ChatMessage m, {required bool mine}) {
    return _UiMessage(
      id: m.id,
      localId: null,
      body: m.body,
      createdAt: m.createdAt,
      mine: mine,
      sending: false,
      failed: false,
    );
  }

  factory _UiMessage.localOutgoing(String body) {
    return _UiMessage(
      id: null,
      localId: 'local-${DateTime.now().millisecondsSinceEpoch}',
      body: body,
      createdAt: DateTime.now(),
      mine: true,
      sending: true,
      failed: false,
    );
  }
}
