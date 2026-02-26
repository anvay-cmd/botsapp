class Message {
  final String id;
  final String chatId;
  final String role;
  String content;
  final String contentType;
  final String? attachmentUrl;
  final DateTime createdAt;
  bool isStreaming;

  Message({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.contentType = 'text',
    this.attachmentUrl,
    required this.createdAt,
    this.isStreaming = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] ?? json['message_id'] ?? '',
        chatId: json['chat_id'],
        role: json['role'],
        content: json['content'] ?? '',
        contentType: json['content_type'] ?? 'text',
        attachmentUrl: json['attachment_url'],
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
      );
}
