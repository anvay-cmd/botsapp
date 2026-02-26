class Bot {
  final String id;
  final String creatorId;
  final String name;
  final String? avatarUrl;
  final String systemPrompt;
  final String voiceName;
  final Map<String, dynamic>? integrationsConfig;
  final int? proactiveMinutes;
  final bool isDefault;
  final DateTime createdAt;

  Bot({
    required this.id,
    required this.creatorId,
    required this.name,
    this.avatarUrl,
    required this.systemPrompt,
    this.voiceName = 'Kore',
    this.integrationsConfig,
    this.proactiveMinutes = 0,
    required this.isDefault,
    required this.createdAt,
  });

  factory Bot.fromJson(Map<String, dynamic> json) => Bot(
        id: json['id'],
        creatorId: json['creator_id'],
        name: json['name'],
        avatarUrl: json['avatar_url'],
        systemPrompt: json['system_prompt'],
        voiceName: json['voice_name'] ?? 'Kore',
        integrationsConfig: json['integrations_config'],
        proactiveMinutes: json['proactive_minutes'] == null
            ? null
            : (json['proactive_minutes'] is int
                ? json['proactive_minutes']
                : int.tryParse('${json['proactive_minutes']}')),
        isDefault: json['is_default'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );
}
