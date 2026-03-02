class LifecycleMessage {
  final String id;
  final String chatId;
  final String botId;
  final int sessionId;
  final String role; // "system", "user", "assistant", or "tool"
  final String content;
  final String contentType; // "text", "tool_call", "tool_result", "system_prompt"
  final DateTime createdAt;

  const LifecycleMessage({
    required this.id,
    required this.chatId,
    required this.botId,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.contentType,
    required this.createdAt,
  });

  factory LifecycleMessage.fromJson(Map<String, dynamic> json) {
    return LifecycleMessage(
      id: json['id'] as String,
      chatId: json['chat_id'] as String,
      botId: json['bot_id'] as String,
      sessionId: json['session_id'] as int,
      role: json['role'] as String,
      content: json['content'] as String,
      contentType: json['content_type'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
