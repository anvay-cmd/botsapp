class AppConstants {
  static const String appName = 'BotsApp';

  /// Pass --dart-define=ENV=dev for local, omit or use prod for api.trybotsapp.com
  static const String _env = String.fromEnvironment('ENV', defaultValue: 'prod');
  static const String _devBase = 'http://192.168.1.8:8000';
  static const String _prodBase = 'https://api.trybotsapp.com';

  static String get baseUrl => _env == 'dev' ? _devBase : _prodBase;
  static String get apiUrl => '$baseUrl/api';
  static String get wsUrl =>
      '${baseUrl.startsWith('https') ? 'wss' : 'ws'}://${baseUrl.split('://').last}/ws';
  static String get wsVoiceUrl =>
      '${baseUrl.startsWith('https') ? 'wss' : 'ws'}://${baseUrl.split('://').last}/ws/voice';

  static const String baseSystemPrompt =
      'Act like you are a real person, dont write big essays, just small talkative replies.';
}
