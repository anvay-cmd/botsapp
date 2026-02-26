class AppUser {
  final String id;
  final String googleId;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.googleId,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    required this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'],
        googleId: json['google_id'],
        email: json['email'],
        displayName: json['display_name'],
        avatarUrl: json['avatar_url'],
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'google_id': googleId,
        'email': email,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'created_at': createdAt.toIso8601String(),
      };
}
