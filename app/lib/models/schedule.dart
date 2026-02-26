class Schedule {
  final String id;
  final String chatId;
  final String botName;
  final String? botAvatar;
  final String message;
  final DateTime scheduledFor;
  final String status;
  final DateTime createdAt;

  Schedule({
    required this.id,
    required this.chatId,
    required this.botName,
    this.botAvatar,
    required this.message,
    required this.scheduledFor,
    required this.status,
    required this.createdAt,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'] as String,
      chatId: json['chat_id'] as String,
      botName: json['bot_name'] as String,
      botAvatar: json['bot_avatar'] as String?,
      message: json['message'] as String,
      scheduledFor: DateTime.parse(json['scheduled_for'] as String).toLocal(),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}
