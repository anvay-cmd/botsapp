import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lifecycle_message.dart';
import '../services/api_service.dart';

class LifecycleMessagesState {
  final List<LifecycleMessage> messages;
  final bool isLoading;

  const LifecycleMessagesState({
    this.messages = const [],
    this.isLoading = false,
  });
}

class LifecycleMessagesNotifier extends StateNotifier<LifecycleMessagesState> {
  final String chatId;
  final ApiService _api = ApiService();

  LifecycleMessagesNotifier(this.chatId)
      : super(const LifecycleMessagesState()) {
    loadMessages();
  }

  Future<void> loadMessages() async {
    state = LifecycleMessagesState(
        messages: state.messages, isLoading: true);
    try {
      final response = await _api.get('/lifecycle/chats/$chatId/messages');
      final messages = (response.data as List)
          .map((j) => LifecycleMessage.fromJson(j))
          .toList();
      state = LifecycleMessagesState(messages: messages);
    } catch (e) {
      state = LifecycleMessagesState(messages: state.messages);
    }
  }
}

final lifecycleMessagesProvider = StateNotifierProvider.autoDispose
    .family<LifecycleMessagesNotifier, LifecycleMessagesState, String>(
        (ref, chatId) {
  return LifecycleMessagesNotifier(chatId);
});
