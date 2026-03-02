import 'dart:async';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GPSService {
  static final GPSService _instance = GPSService._internal();
  factory GPSService() => _instance;
  GPSService._internal();

  final Dio _dio = Dio();
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _trackingTimer;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  String? _baseUrl;
  String? _authToken;
  bool _isTracking = false;

  // Geofence state tracking
  final Map<String, bool> _geofenceStates = {}; // fence_id -> is_inside

  /// Initialize GPS service
  Future<void> initialize(String baseUrl, String authToken) async {
    print('🔧 GPS: Initializing with baseUrl: $baseUrl');
    _baseUrl = baseUrl;
    _authToken = authToken;

    // Initialize notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(initSettings);
    print('✅ GPS: Notifications initialized');

    // Check if GPS integration is enabled
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('gps_integration_enabled') ?? false;
    print('📋 GPS: Integration enabled in prefs: $isEnabled');

    if (isEnabled) {
      await startTracking();
    }
  }

  /// Check and request location permissions
  Future<bool> checkPermissions() async {
    print('🔐 GPS: Checking location permissions...');

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ GPS: Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    print('📋 GPS: Current permission: $permission');

    if (permission == LocationPermission.denied) {
      print('🙏 GPS: Requesting location permission...');
      permission = await Geolocator.requestPermission();
      print('📋 GPS: Permission after request: $permission');

      if (permission == LocationPermission.denied) {
        print('❌ GPS: Permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('❌ GPS: Permission denied forever');
      return false;
    }

    print('✅ GPS: Permissions granted');
    return true;
  }

  /// Get current location
  Future<Position?> getCurrentLocation() async {
    if (!await checkPermissions()) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// Start location tracking
  Future<void> startTracking() async {
    print('🚀 GPS: startTracking() called');

    if (_isTracking) {
      print('⚠️ GPS: Already tracking, skipping');
      return;
    }

    if (!await checkPermissions()) {
      print('❌ GPS: Cannot start tracking - no permissions');
      return;
    }

    _isTracking = true;
    print('✅ GPS: Tracking enabled');

    // Start listening to position stream
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
      timeLimit: Duration(minutes: 10),
    );

    print('📡 GPS: Starting position stream...');
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        print('📍 GPS: Position stream update received');
        _handleLocationUpdate(position);
      },
      onError: (error) {
        print('❌ GPS: Position stream error: $error');
      },
    );

    // Also send periodic updates (every 5 minutes) even if user hasn't moved much
    print('⏰ GPS: Starting periodic timer (5 min)');
    _trackingTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      print('⏰ GPS: Periodic update triggered');
      final position = await getCurrentLocation();
      if (position != null) {
        _handleLocationUpdate(position);
      } else {
        print('⚠️ GPS: Periodic update - no position available');
      }
    });

    // Get initial location immediately
    print('📍 GPS: Getting initial location...');
    final initialPosition = await getCurrentLocation();
    if (initialPosition != null) {
      _handleLocationUpdate(initialPosition);
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  /// Handle location update
  Future<void> _handleLocationUpdate(Position position) async {
    if (_baseUrl == null || _authToken == null) {
      print('🚨 GPS: Cannot send location - baseUrl or authToken is null');
      return;
    }

    try {
      print('📍 GPS: Sending location update: ${position.latitude}, ${position.longitude}');
      final response = await _dio.post(
        '$_baseUrl/gps/location',
        data: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'altitude': position.altitude,
          'speed': position.speed,
          'heading': position.heading,
          'timestamp': position.timestamp.toIso8601String(),
        },
        options: Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
      );

      print('✅ GPS: Location sent successfully');

      // Handle geofence events from response
      if (response.data['triggered_events'] != null) {
        final events = response.data['triggered_events'] as List;
        print('🔔 GPS: ${events.length} geofence events triggered');
        for (var event in events) {
          await _handleGeofenceEvent(event);
        }
      }
    } catch (e) {
      print('❌ GPS: Failed to send location: $e');
    }
  }

  /// Handle geofence event
  Future<void> _handleGeofenceEvent(Map<String, dynamic> event) async {
    final fenceId = event['fence_id'] as String;
    final fenceName = event['fence_name'] as String;
    final eventType = event['event_type'] as String;

    // Track state to avoid duplicate notifications
    if (eventType == 'enter') {
      if (_geofenceStates[fenceId] == true) return; // Already inside
      _geofenceStates[fenceId] = true;
    } else if (eventType == 'exit') {
      if (_geofenceStates[fenceId] == false) return; // Already outside
      _geofenceStates[fenceId] = false;
    }

    // Show local notification
    String notificationBody;
    switch (eventType) {
      case 'enter':
        notificationBody = 'You entered $fenceName';
        break;
      case 'exit':
        notificationBody = 'You left $fenceName';
        break;
      case 'dwell':
        notificationBody = 'You are in $fenceName';
        break;
      default:
        notificationBody = 'Geofence event: $eventType';
    }

    await _showNotification(
      title: 'Location Alert',
      body: notificationBody,
      payload: event['chat_id'],
    );
  }

  /// Show local notification
  Future<void> _showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'geofence_channel',
      'Geofence Notifications',
      channelDescription: 'Notifications for geofence events',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Enable GPS integration
  Future<void> enableIntegration() async {
    print('✅ GPS: Enabling integration in SharedPreferences');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gps_integration_enabled', true);
    await startTracking();
  }

  /// Disable GPS integration
  Future<void> disableIntegration() async {
    print('❌ GPS: Disabling integration in SharedPreferences');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gps_integration_enabled', false);
    await stopTracking();
  }

  /// Check if integration is enabled
  Future<bool> isIntegrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('gps_integration_enabled') ?? false;
  }

  /// Create geofence via API
  Future<Map<String, dynamic>?> createGeofence({
    required String name,
    required double latitude,
    required double longitude,
    required double radius,
  }) async {
    if (_baseUrl == null || _authToken == null) return null;

    try {
      final response = await _dio.post(
        '$_baseUrl/gps/fences',
        data: {
          'name': name,
          'latitude': latitude,
          'longitude': longitude,
          'radius': radius,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
      );

      return response.data;
    } catch (e) {
      return null;
    }
  }

  /// Get all geofences
  Future<List<Map<String, dynamic>>> getGeofences() async {
    if (_baseUrl == null || _authToken == null) return [];

    try {
      final response = await _dio.get(
        '$_baseUrl/gps/fences',
        options: Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
      );

      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      return [];
    }
  }

  /// Delete geofence
  Future<bool> deleteGeofence(String fenceId) async {
    if (_baseUrl == null || _authToken == null) return false;

    try {
      await _dio.delete(
        '$_baseUrl/gps/fences/$fenceId',
        options: Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _positionStreamSubscription?.cancel();
    _trackingTimer?.cancel();
  }
}
