import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/token_storage.dart';
import '../../../core/utils/logger.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../data/chat_repository.dart';

class TripChatPage extends ConsumerStatefulWidget {
  const TripChatPage({
    super.key,
    required this.tripId,
    required this.tripReference,
    required this.tripStatus,
  });

  final int tripId;
  final String tripReference;
  final String tripStatus;

  @override
  ConsumerState<TripChatPage> createState() => _TripChatPageState();
}

class _TripChatPageState extends ConsumerState<TripChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_UiChatMessage> _messages = [];
  Timer? _pollTimer;
  bool _loading = true;
  bool _sending = false;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final token = await ref.read(tokenStorageProvider).readToken();
      if (token == null || token.isEmpty) return;
      final parts = token.split('.');
      if (parts.length < 2) return;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final sub = json['sub']?.toString();
      if (sub == null) return;
      final parsed = int.tryParse(sub);
      if (parsed == null) return;
      if (!mounted) return;
      setState(() => _currentUserId = parsed);
    } catch (_) {}
  }

  bool _isMine(ChatMessage message) {
    if (_currentUserId != null && message.senderId == _currentUserId) {
      return true;
    }
    if (message.senderRole.contains('driver')) {
      return true;
    }
    return false;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      final remote = await repo.fetchTripChat(widget.tripId);
      final failedLocals = _messages
          .where((m) => m.localId != null && m.failed)
          .toList();
      _messages
        ..clear()
        ..addAll(remote.map((m) => _UiChatMessage.fromRemote(message: m, mine: _isMine(m))))
        ..addAll(failedLocals)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final unreadIncoming = _messages
          .where((m) => !m.mine && !m.read && m.id != null)
          .toList();
      for (final msg in unreadIncoming) {
        try {
          await repo.markMessageRead(tripId: widget.tripId, messageId: msg.id!);
          msg.read = true;
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    } catch (e, st) {
      Logger.e('Trip chat load failed', e, st);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final local = _UiChatMessage.localOutgoing(body: text);
    setState(() {
      _messages.add(local);
      _sending = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final sent = await ref
          .read(chatRepositoryProvider)
          .sendTripMessage(tripId: widget.tripId, body: text);
      final idx = _messages.indexWhere((m) => m.localId == local.localId);
      if (idx != -1) {
        _messages[idx] = _UiChatMessage.fromRemote(message: sent, mine: true);
      }
      if (!mounted) return;
      setState(() => _sending = false);
      _scrollToBottom();
      await _load(silent: true);
    } catch (e, st) {
      Logger.e('Trip chat send failed', e, st);
      final idx = _messages.indexWhere((m) => m.localId == local.localId);
      if (idx != -1) {
        _messages[idx].failed = true;
        _messages[idx].sending = false;
      }
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  Future<void> _retry(_UiChatMessage message) async {
    if (!message.failed || message.body.trim().isEmpty) return;
    setState(() {
      message.failed = false;
      message.sending = true;
    });
    try {
      final sent = await ref
          .read(chatRepositoryProvider)
          .sendTripMessage(tripId: widget.tripId, body: message.body);
      final idx = _messages.indexWhere((m) => m.localId == message.localId);
      if (idx != -1) {
        _messages[idx] = _UiChatMessage.fromRemote(message: sent, mine: true);
      }
      if (!mounted) return;
      setState(() {});
      await _load(silent: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        message.failed = true;
        message.sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Dispatcher'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.tripReference} • ${widget.tripStatus}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
            ),
          ),
        ),
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
          Column(
            children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return _ChatBubble(
                              message: message,
                              onRetry: () => _retry(message),
                            );
                          },
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
                    border: Border(
                      top: BorderSide(color: AppColors.neutral200),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          minLines: 1,
                          maxLines: 4,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Message dispatcher...',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        onPressed: _controller.text.trim().isEmpty ? null : _send,
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.onRetry,
  });

  final _UiChatMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bg = message.mine ? AppColors.primaryBlue : Colors.white;
    final fg = message.mine ? Colors.white : AppColors.textPrimary;
    final align = message.mine ? Alignment.centerRight : Alignment.centerLeft;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: message.mine
              ? null
              : Border.all(color: AppColors.neutral200),
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
                    color: message.mine ? Colors.white70 : AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                if (message.mine) ...[
                  const SizedBox(width: 8),
                  Icon(
                    message.failed
                        ? Icons.error_outline
                        : (message.read ? Icons.done_all : Icons.done),
                    size: 14,
                    color: message.failed
                        ? AppColors.errorRed
                        : Colors.white70,
                  ),
                ],
                if (message.sending) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: message.mine ? Colors.white70 : AppColors.primaryBlue,
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
                    color: message.mine ? Colors.white : AppColors.errorRed,
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

class _UiChatMessage {
  _UiChatMessage({
    required this.id,
    required this.localId,
    required this.body,
    required this.createdAt,
    required this.mine,
    required this.read,
    required this.sending,
    required this.failed,
  });

  final int? id;
  final String? localId;
  final String body;
  final DateTime createdAt;
  final bool mine;
  bool read;
  bool sending;
  bool failed;

  factory _UiChatMessage.fromRemote({
    required ChatMessage message,
    required bool mine,
  }) {
    return _UiChatMessage(
      id: message.id,
      localId: null,
      body: message.body,
      createdAt: message.createdAt,
      mine: mine,
      read: message.isRead || mine,
      sending: false,
      failed: false,
    );
  }

  factory _UiChatMessage.localOutgoing({required String body}) {
    return _UiChatMessage(
      id: null,
      localId: 'local-${DateTime.now().millisecondsSinceEpoch}',
      body: body,
      createdAt: DateTime.now(),
      mine: true,
      read: false,
      sending: true,
      failed: false,
    );
  }
}
