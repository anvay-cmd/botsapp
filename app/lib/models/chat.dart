class Chat {
  final String id;
  final String userId;
  final String botId;
  final bool isMuted;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final String? botName;
  final String? botAvatar;
  final String? lastMessage;
  final int unreadCount;

  Chat({
    required this.id,
    required this.userId,
    required this.botId,
    required this.isMuted,
    this.lastMessageAt,
    required this.createdAt,
    this.botName,
    this.botAvatar,
    this.lastMessage,
    this.unreadCount = 0,
  });

  factory Chat.fromJson(Map<String, dynamic> json) => Chat(
        id: json['id'],
        userId: json['user_id'],
        botId: json['bot_id'],
        isMuted: json['is_muted'] ?? false,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.parse(json['last_message_at'])
            : null,
        createdAt: DateTime.parse(json['created_at']),
        botName: json['bot_name'],
        botAvatar: json['bot_avatar'],
        lastMessage: json['last_message'],
        unreadCount: json['unread_count'] ?? 0,
      );

  Chat copyWith({
    bool? isMuted,
    DateTime? lastMessageAt,
    String? lastMessage,
    int? unreadCount,
  }) =>
      Chat(
        id: id,
        userId: userId,
        botId: botId,
        isMuted: isMuted ?? this.isMuted,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        createdAt: createdAt,
        botName: botName,
        botAvatar: botAvatar,
        lastMessage: lastMessage ?? this.lastMessage,
        unreadCount: unreadCount ?? this.unreadCount,
      );
}
