import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

// Location model
class LocationPoint {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;

  LocationPoint({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    required this.timestamp,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: json['accuracy'] != null ? (json['accuracy'] as num).toDouble() : null,
      altitude: json['altitude'] != null ? (json['altitude'] as num).toDouble() : null,
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      heading: json['heading'] != null ? (json['heading'] as num).toDouble() : null,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

// State
class LocationHistoryState {
  final List<LocationPoint> locations;
  final bool isLoading;
  final String? error;

  LocationHistoryState({
    this.locations = const [],
    this.isLoading = false,
    this.error,
  });

  LocationHistoryState copyWith({
    List<LocationPoint>? locations,
    bool? isLoading,
    String? error,
  }) {
    return LocationHistoryState(
      locations: locations ?? this.locations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Notifier
class LocationHistoryNotifier extends StateNotifier<LocationHistoryState> {
  final ApiService _api = ApiService();

  LocationHistoryNotifier() : super(LocationHistoryState());

  Future<void> loadHistory({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final dateFormat = DateFormat('yyyy-MM-dd');
      final response = await _api.get(
        '/gps/location/history',
        queryParameters: {
          'start_date': dateFormat.format(startDate),
          'end_date': dateFormat.format(endDate),
        },
      );

      final locationsList = response.data['locations'] as List;
      final locations = locationsList
          .map((json) => LocationPoint.fromJson(json as Map<String, dynamic>))
          .toList();

      state = LocationHistoryState(
        locations: locations,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load location history: ${e.toString()}',
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider
final locationHistoryProvider =
    StateNotifierProvider<LocationHistoryNotifier, LocationHistoryState>(
  (ref) => LocationHistoryNotifier(),
);
