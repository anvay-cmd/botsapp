import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isConnected = false;
  Timer? _reconnectTimer;
  bool _shouldReconnect = true;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    _shouldReconnect = true;
    if (_isConnected) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token == null) return;

      final uri = Uri.parse('${AppConstants.wsUrl}?token=$token');
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          try {
            final message = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(message);
          } catch (_) {}
        },
        onDone: () {
          _isConnected = false;
          if (_shouldReconnect) _scheduleReconnect();
        },
        onError: (_) {
          _isConnected = false;
          if (_shouldReconnect) _scheduleReconnect();
        },
      );
    } catch (e) {
      _isConnected = false;
      if (_shouldReconnect) _scheduleReconnect();
    }
  }

  void sendMessage({
    required String chatId,
    required String content,
    String contentType = 'text',
    String? attachmentUrl,
  }) {
    if (!_isConnected || _channel == null) return;

    _channel!.sink.add(jsonEncode({
      'type': 'message',
      'chat_id': chatId,
      'content': content,
      'content_type': contentType,
      'attachment_url': attachmentUrl,
    }));
  }

  void sendTyping(String chatId) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'typing',
      'chat_id': chatId,
    }));
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      connect();
    });
  }

  void disconnect({bool allowReconnect = false}) {
    _shouldReconnect = allowReconnect;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  void pauseForBackground() {
    disconnect(allowReconnect: false);
  }

  Future<void> resumeFromBackground() async {
    if (_isConnected) return;
    await connect();
  }

  void dispose() {
    disconnect(allowReconnect: false);
    _messageController.close();
  }
}
