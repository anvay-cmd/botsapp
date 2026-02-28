import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class ChatListState {
  final List<Chat> chats;
  final bool isLoading;

  const ChatListState({this.chats = const [], this.isLoading = false});
}

class ChatListNotifier extends StateNotifier<ChatListState> {
  final ApiService _api = ApiService();
  final WebSocketService _ws;
  final Ref _ref;
  StreamSubscription? _wsSubscription;

  ChatListNotifier(this._ws, this._ref) : super(const ChatListState()) {
    _listenToWebSocket();
  }

  Future<void> loadChats() async {
    state = ChatListState(chats: state.chats, isLoading: true);
    try {
      final response = await _api.get('/chats');
      final chats = (response.data as List).map((j) => Chat.fromJson(j)).toList();
      state = ChatListState(chats: chats);
    } catch (e) {
      state = ChatListState(chats: state.chats);
    }
  }

  Future<void> muteChat(String chatId, bool muted) async {
    try {
      await _api.patch('/chats/$chatId/mute', data: {'is_muted': muted});
      state = ChatListState(
        chats: state.chats.map((c) {
          if (c.id == chatId) return c.copyWith(isMuted: muted);
          return c;
        }).toList(),
      );
    } catch (_) {}
  }

  void updateLastMessage(String chatId, String content) {
    state = ChatListState(
      chats: state.chats.map((c) {
        if (c.id == chatId) {
          return c.copyWith(
            lastMessage: content,
            lastMessageAt: DateTime.now(),
            unreadCount: 0,
          );
        }
        return c;
      }).toList(),
    );
  }

  Future<void> markChatRead(String chatId) async {
    state = ChatListState(
      chats: state.chats.map((c) {
        if (c.id == chatId) return c.copyWith(unreadCount: 0);
        return c;
      }).toList(),
    );
    try {
      await _api.post('/chats/$chatId/read');
    } catch (_) {}
  }

  void _listenToWebSocket() {
    _wsSubscription = _ws.messageStream.listen((msg) {
      if (msg['type'] != 'message_complete') return;
      final msgChatId = msg['chat_id']?.toString();
      if (msgChatId == null || msgChatId.isEmpty) return;
      final content = (msg['content'] ?? '').toString();
      final activeChatId = _ref.read(activeChatIdProvider);

      final updated = state.chats.map((c) {
        if (c.id != msgChatId) return c;
        final unread = (activeChatId == msgChatId) ? 0 : (c.unreadCount + 1);
        return c.copyWith(
          lastMessage: content,
          lastMessageAt: DateTime.now(),
          unreadCount: unread,
        );
      }).toList()
        ..sort((a, b) {
          final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });

      state = ChatListState(chats: updated, isLoading: state.isLoading);
      if (activeChatId == msgChatId) {
        _api.post('/chats/$msgChatId/read');
      }
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }
}

final chatListProvider =
    StateNotifierProvider<ChatListNotifier, ChatListState>((ref) {
  final ws = ref.watch(webSocketProvider);
  return ChatListNotifier(ws, ref);
});

final activeChatIdProvider = StateProvider<String?>((ref) => null);

class ChatMessagesState {
  final List<Message> messages;
  final bool isLoading;
  final bool isBotTyping;
  final List<MessageBubble> streamingBubbles;

  const ChatMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.isBotTyping = false,
    this.streamingBubbles = const [],
  });
}

class MessageBubble {
  final String type; // 'text', 'tool_call'
  final String content;

  const MessageBubble({
    required this.type,
    required this.content,
  });
}

class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  final String chatId;
  final ApiService _api = ApiService();
  final WebSocketService _ws;
  StreamSubscription? _wsSubscription;

  ChatMessagesNotifier(this.chatId, this._ws)
      : super(const ChatMessagesState()) {
    _loadMessages();
    _listenToWebSocket();
  }

  Future<void> _loadMessages() async {
    state = ChatMessagesState(
        messages: state.messages, isLoading: true);
    try {
      final response = await _api.get('/chats/$chatId/messages');
      final messages =
          (response.data as List).map((j) => Message.fromJson(j)).toList();
      state = ChatMessagesState(messages: messages);
    } catch (e) {
      state = ChatMessagesState(messages: state.messages);
    }
  }

  void _listenToWebSocket() {
    _wsSubscription = _ws.messageStream.listen((msg) {
      final msgChatId = msg['chat_id'];
      if (msgChatId != chatId) return;

      switch (msg['type']) {
        case 'message':
          final messageId = msg['message_id'] ?? '';

          // Check if message already exists (prevent duplicates)
          final exists = state.messages.any((m) => m.id == messageId);
          if (exists) {
            print('Skipping duplicate message: $messageId');
            return;
          }

          final message = Message(
            id: messageId,
            chatId: chatId,
            role: msg['role'] ?? 'user',
            content: msg['content'] ?? '',
            contentType: msg['content_type'] ?? 'text',
            attachmentUrl: msg['attachment_url'],
            createdAt: DateTime.now(),
          );
          state = ChatMessagesState(
            messages: [...state.messages, message],
            isBotTyping: state.isBotTyping,
            streamingBubbles: state.streamingBubbles,
          );
          break;

        case 'typing':
          state = ChatMessagesState(
            messages: state.messages,
            isBotTyping: true,
            streamingBubbles: [],
          );
          break;

        case 'paragraph':
          final content = msg['content'] ?? '';
          state = ChatMessagesState(
            messages: state.messages,
            isBotTyping: true,
            streamingBubbles: [
              ...state.streamingBubbles,
              MessageBubble(type: 'text', content: content),
            ],
          );
          break;

        case 'stream':
          // Legacy streaming support - will be removed
          break;

        case 'message_complete':
          final content = msg['content'] ?? '';
          final messageId = msg['message_id'] ?? '';

          // Only add message if there's content and it doesn't already exist
          if (content.isNotEmpty && messageId.isNotEmpty) {
            final exists = state.messages.any((m) => m.id == messageId);
            if (exists) {
              // Message already added, just clear typing state
              state = ChatMessagesState(
                messages: state.messages,
                isBotTyping: false,
                streamingBubbles: [],
              );
            } else {
              final message = Message(
                id: messageId,
                chatId: chatId,
                role: 'assistant',
                content: content,
                contentType: msg['content_type'] ?? 'text',
                createdAt: DateTime.now(),
              );
              state = ChatMessagesState(
                messages: [...state.messages, message],
                isBotTyping: false,
                streamingBubbles: [],
              );
            }
          } else {
            // Just clear typing state
            state = ChatMessagesState(
              messages: state.messages,
              isBotTyping: false,
              streamingBubbles: [],
            );
          }
          break;
      }
    });
  }

  Future<void> sendMessage(String content,
      {String contentType = 'text', String? attachmentUrl}) async {
    String? serverUrl = attachmentUrl;
    if (contentType == 'image' && attachmentUrl != null) {
      try {
        serverUrl = await _api.uploadImage(attachmentUrl);
      } catch (_) {
        return;
      }
    }
    _ws.sendMessage(
      chatId: chatId,
      content: content,
      contentType: contentType,
      attachmentUrl: serverUrl,
    );
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }
}

final chatMessagesProvider = StateNotifierProvider.autoDispose
    .family<ChatMessagesNotifier, ChatMessagesState, String>((ref, chatId) {
  final ws = ref.watch(webSocketProvider);
  return ChatMessagesNotifier(chatId, ws);
});

final webSocketProvider = Provider<WebSocketService>((ref) {
  final ws = WebSocketService();
  ws.connect();
  ref.onDispose(() => ws.dispose());
  return ws;
});
