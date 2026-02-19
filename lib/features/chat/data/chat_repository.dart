import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.senderId,
    required this.senderRole,
    required this.readAt,
  });

  final int id;
  final String body;
  final DateTime createdAt;
  final int? senderId;
  final String senderRole;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    DateTime? toDate(dynamic value) {
      if (value == null) return null;
      if (value is String) return DateTime.tryParse(value)?.toLocal();
      return null;
    }

    return ChatMessage(
      id: toInt(json['id']) ?? DateTime.now().millisecondsSinceEpoch,
      body: (json['body'] ?? json['message'] ?? '').toString(),
      createdAt:
          toDate(json['created_at']) ??
          toDate(json['sent_at']) ??
          toDate(json['timestamp']) ??
          DateTime.now(),
      senderId: toInt(
        json['sender_id'] ?? json['from_user_id'] ?? json['created_by_id'],
      ),
      senderRole: (json['sender_role'] ?? json['sender_type'] ?? '')
          .toString()
          .toLowerCase(),
      readAt:
          toDate(json['read_at']) ??
          toDate(json['seen_at']) ??
          toDate(json['opened_at']),
    );
  }
}

class ChatThreadInboxItem {
  ChatThreadInboxItem({
    required this.tripId,
    required this.unreadCount,
  });

  final int? tripId;
  final int unreadCount;

  factory ChatThreadInboxItem.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return ChatThreadInboxItem(
      tripId: toInt(json['trip_id'] ?? json['tripId'] ?? json['trip']?['id']),
      unreadCount: toInt(json['unread_count'] ?? json['unread']) ?? 0,
    );
  }
}

class ChatRepository {
  ChatRepository(this._dio);

  final Dio _dio;

  List<dynamic> _pickList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      final candidates = [
        data['data'],
        data['messages'],
        data['items'],
        data['inbox'],
        data['threads'],
      ];
      for (final item in candidates) {
        if (item is List) return item;
      }
    }
    return const [];
  }

  Map<String, dynamic> _pickMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<List<ChatThreadInboxItem>> fetchInbox() async {
    final response = await _dio.get(Endpoints.chatInbox);
    return _pickList(response.data)
        .whereType<Map>()
        .map((e) => ChatThreadInboxItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<int> fetchTripUnreadCount(int tripId) async {
    final inbox = await fetchInbox();
    final match = inbox.where((item) => item.tripId == tripId);
    return match.fold<int>(0, (sum, item) => sum + item.unreadCount);
  }

  Future<List<ChatMessage>> fetchTripChat(int tripId) async {
    final response = await _dio.get(Endpoints.tripChat(tripId));
    final list = _pickList(response.data);
    final messages = list
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  Future<ChatMessage> sendTripMessage({
    required int tripId,
    required String body,
  }) async {
    final response = await _dio.post(
      Endpoints.tripChatMessages(tripId),
      data: {
        'message': {'body': body},
      },
    );
    final data = response.data;
    final map = _pickMap(data['message'] ?? data['data'] ?? data);
    if (map.isNotEmpty) {
      return ChatMessage.fromJson(map);
    }
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch,
      body: body,
      createdAt: DateTime.now(),
      senderId: null,
      senderRole: 'driver',
      readAt: null,
    );
  }

  Future<void> markMessageRead({
    required int tripId,
    required int messageId,
  }) async {
    await _dio.patch(Endpoints.tripChatMessage(tripId, messageId));
  }

  Future<List<ChatConversation>> fetchConversations() async {
    final response = await _dio.get(Endpoints.chatConversations);
    return _pickList(response.data)
        .whereType<Map>()
        .map((e) => ChatConversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ChatConversationThread> fetchConversationThread(int conversationId) async {
    final response = await _dio.get(Endpoints.chatConversation(conversationId));
    final data = response.data;
    final root = _pickMap(data);
    final convMap = _pickMap(root['conversation'] ?? root['data'] ?? root);
    final conversation = ChatConversation.fromJson(convMap);
    final rawMessages = _pickList(
      root['messages'] ?? root['data']?['messages'] ?? root,
    );
    final messages = rawMessages
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ChatConversationThread(conversation: conversation, messages: messages);
  }

  Future<ChatConversation> createConversation({
    String? title,
    required List<int> participantIds,
  }) async {
    final response = await _dio.post(
      Endpoints.chatConversations,
      data: {
        'conversation': {
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          'participant_ids': participantIds,
        },
      },
    );
    final map = _pickMap(
      response.data['conversation'] ?? response.data['data'] ?? response.data,
    );
    return ChatConversation.fromJson(map);
  }

  Future<ChatMessage> sendConversationMessage({
    required int conversationId,
    required String body,
  }) async {
    final response = await _dio.post(
      Endpoints.chatConversationMessages(conversationId),
      data: {
        'message': {'body': body},
      },
    );
    final map = _pickMap(
      response.data['message'] ?? response.data['data'] ?? response.data,
    );
    if (map.isNotEmpty) return ChatMessage.fromJson(map);
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch,
      body: body,
      createdAt: DateTime.now(),
      senderId: null,
      senderRole: 'driver',
      readAt: null,
    );
  }

  Future<void> markConversationRead(int conversationId) async {
    await _dio.patch(Endpoints.chatConversationRead(conversationId));
  }
}

class ChatConversationThread {
  ChatConversationThread({
    required this.conversation,
    required this.messages,
  });

  final ChatConversation conversation;
  final List<ChatMessage> messages;
}

class ChatParticipant {
  ChatParticipant({
    required this.id,
    required this.name,
    required this.role,
  });

  final int id;
  final String name;
  final String role;

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    return ChatParticipant(
      id: toInt(json['id']),
      name: (json['name'] ?? json['full_name'] ?? 'User ${json['id']}').toString(),
      role: (json['role'] ?? json['type'] ?? '').toString(),
    );
  }
}

class ChatConversation {
  ChatConversation({
    required this.id,
    required this.title,
    required this.participants,
    required this.unreadCount,
    required this.lastMessageAt,
    required this.lastMessageBody,
  });

  final int id;
  final String? title;
  final List<ChatParticipant> participants;
  final int unreadCount;
  final DateTime? lastMessageAt;
  final String? lastMessageBody;

  String displayTitle({int? currentUserId}) {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    final others = participants.where((p) => p.id != currentUserId).toList();
    if (others.isNotEmpty) {
      return others.map((e) => e.name).join(', ');
    }
    if (participants.isNotEmpty) {
      return participants.map((e) => e.name).join(', ');
    }
    return 'Conversation #$id';
  }

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    DateTime? toDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value)?.toLocal();
      return null;
    }

    final participantsRaw = json['participants'];
    final participants = <ChatParticipant>[];
    if (participantsRaw is List) {
      for (final item in participantsRaw) {
        if (item is Map) {
          participants.add(ChatParticipant.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final lastMessageRaw = json['last_message'];
    final lastMap = lastMessageRaw is Map
        ? Map<String, dynamic>.from(lastMessageRaw)
        : <String, dynamic>{};

    return ChatConversation(
      id: toInt(json['id']),
      title: json['title']?.toString(),
      participants: participants,
      unreadCount: toInt(json['unread_count'] ?? json['unread']),
      lastMessageAt: toDate(
        json['last_message_at'] ?? lastMap['created_at'] ?? json['updated_at'],
      ),
      lastMessageBody: (lastMap['body'] ?? json['last_message_body'])?.toString(),
    );
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final dio = ref.read(dioProvider);
  return ChatRepository(dio);
});
