import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/routes.dart';
import 'api_service.dart';

class CallKitBridgeService {
  CallKitBridgeService._();
  static final CallKitBridgeService instance = CallKitBridgeService._();

  static const MethodChannel _channel = MethodChannel('botsapp/callkit');
  final ApiService _api = ApiService();
  bool _initialized = false;
  Map<String, dynamic>? _pendingIncomingCall;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    await syncPushTokens();
    await _drainPendingIncomingCall();
  }

  Future<void> syncPushTokens() async {
    await _syncCachedVoipToken();
    await _syncCachedApnsToken();
  }

  Future<void> _syncCachedVoipToken() async {
    try {
      final token = await _channel.invokeMethod<String>('getCachedVoipToken');
      if (token == null || token.isEmpty) return;
      await _persistAndUploadVoipToken(token);
    } catch (e) {
      debugPrint('[CallKitBridge] getCachedVoipToken failed: $e');
    }
  }

  Future<void> _syncCachedApnsToken() async {
    String? token;
    try {
      token = await _channel.invokeMethod<String>('getCachedApnsToken');
    } catch (e) {
      debugPrint('[CallKitBridge] getCachedApnsToken failed: $e');
    }

    if (token == null || token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('apns_token');
    }
    if (token == null || token.isEmpty) return;
    try {
      await _api.post('/auth/apns-token', data: {'apns_token': token});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('apns_token', token);
    } catch (e) {
      debugPrint('[CallKitBridge] upload apns token failed: $e');
    }
  }

  Future<void> _drainPendingIncomingCall() async {
    try {
      final pending =
          await _channel.invokeMapMethod<String, dynamic>('drainPendingIncomingCall');
      if (pending == null) return;
      _handleIncomingCallAccepted(Map<String, dynamic>.from(pending));
    } catch (_) {}
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'voipToken':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final token = (args['token'] as String?) ?? '';
        if (token.isNotEmpty) {
          await _persistAndUploadVoipToken(token);
        }
        return null;
      case 'apnsToken':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final token = (args['token'] as String?) ?? '';
        if (token.isNotEmpty) {
          await _persistAndUploadApnsToken(token);
        }
        return null;
      case 'incomingCallAccepted':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _handleIncomingCallAccepted(args);
        return null;
      case 'incomingCallEnded':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final callId = args['call_id'] as String?;
        if (callId != null && callId.isNotEmpty) {
          try {
            await _api.patch(
              '/calls/$callId/status',
              data: {'status': 'missed', 'end_reason': 'declined_or_missed'},
            );
          } catch (_) {}
        }
        return null;
      default:
        return null;
    }
  }

  Future<void> _persistAndUploadVoipToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voip_token', token);
    try {
      await _api.post('/auth/voip-token', data: {'voip_token': token});
    } catch (e) {
      debugPrint('[CallKitBridge] upload voip token failed: $e');
      // Token sync can be retried later on next app launch.
    }
  }

  Future<void> _persistAndUploadApnsToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apns_token', token);
    try {
      await _api.post('/auth/apns-token', data: {'apns_token': token});
    } catch (e) {
      debugPrint('[CallKitBridge] persist/upload apns token failed: $e');
      // Token sync can be retried later on next app launch.
    }
  }

  void _handleIncomingCallAccepted(Map<String, dynamic> payload) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      _pendingIncomingCall = payload;
      return;
    }

    final chatId = payload['chat_id'] as String?;
    if (chatId == null || chatId.isEmpty) return;

    final callId = payload['call_id'] as String?;
    if (callId != null && callId.isNotEmpty) {
      _markCallAccepted(callId);
    }

    GoRouter.of(context).push(
      '/call/$chatId',
      extra: {
        'botName': payload['bot_name'] ?? 'AI Assistant',
        'botAvatar': payload['bot_avatar'],
        'callId': callId,
      },
    );
  }

  Future<void> _markCallAccepted(String callId) async {
    try {
      await _api.patch('/calls/$callId/status', data: {'status': 'accepted'});
    } catch (_) {}
  }

  void tryConsumePendingIncomingCall() {
    if (_pendingIncomingCall == null) return;
    final payload = _pendingIncomingCall!;
    _pendingIncomingCall = null;
    _handleIncomingCallAccepted(payload);
  }

  Future<void> finishCall(String? callId) async {
    if (callId != null && callId.isNotEmpty) {
      try {
        await _api.patch('/calls/$callId/status', data: {'status': 'completed'});
      } catch (_) {}
      try {
        await _channel.invokeMethod('endNativeCall', {'call_id': callId});
      } catch (_) {}
    }
  }
}

