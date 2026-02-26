class IntegrationInfo {
  final String provider;
  final String name;
  final String description;
  final String icon;
  final bool requiresOauth;
  final bool isConnected;
  final String? integrationId;

  IntegrationInfo({
    required this.provider,
    required this.name,
    required this.description,
    required this.icon,
    required this.requiresOauth,
    required this.isConnected,
    this.integrationId,
  });

  factory IntegrationInfo.fromJson(Map<String, dynamic> json) =>
      IntegrationInfo(
        provider: json['provider'],
        name: json['name'],
        description: json['description'],
        icon: json['icon'],
        requiresOauth: json['requires_oauth'] ?? false,
        isConnected: json['is_connected'] ?? false,
        integrationId: json['integration_id'],
      );
}
