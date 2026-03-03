import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../providers/location_provider.dart';

class LocationTracksScreen extends ConsumerStatefulWidget {
  const LocationTracksScreen({super.key});

  @override
  ConsumerState<LocationTracksScreen> createState() => _LocationTracksScreenState();
}

class _LocationTracksScreenState extends ConsumerState<LocationTracksScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocationHistory();
    });
  }

  Future<void> _loadLocationHistory() async {
    await ref.read(locationHistoryProvider.notifier).loadHistory(
      startDate: _selectedDate,
      endDate: _selectedDate,
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadLocationHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationHistoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Tracks'),
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primaryGreen,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Select Date',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date display
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? AppTheme.darkSurface : AppTheme.primaryGreen.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.date_range,
                  color: isDark ? AppTheme.lightGreen : AppTheme.primaryGreen,
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),

          // Location count
          if (!locationState.isLoading && locationState.locations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '${locationState.locations.length} location points',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
            ),

          // Map
          Expanded(
            child: locationState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : locationState.error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              locationState.error!,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadLocationHistory,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : locationState.locations.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.location_off,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No location data for this day',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _buildMap(locationState),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(LocationHistoryState locationState) {
    final locations = locationState.locations;

    // Calculate center point (average of all locations)
    double centerLat = locations.map((l) => l.latitude).reduce((a, b) => a + b) / locations.length;
    double centerLon = locations.map((l) => l.longitude).reduce((a, b) => a + b) / locations.length;

    // Get current location (last one)
    final currentLocation = locations.isNotEmpty ? locations.last : null;

    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(centerLat, centerLon),
        initialZoom: 14.0,
        minZoom: 3.0,
        maxZoom: 18.0,
      ),
      children: [
        // OSM Tile Layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.botsapp.app',
        ),

        // Polyline connecting all points
        if (locations.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: locations.map((loc) => LatLng(loc.latitude, loc.longitude)).toList(),
                color: Colors.blue,
                strokeWidth: 3.0,
              ),
            ],
          ),

        // Location points as red dots
        MarkerLayer(
          markers: [
            // Historical points (red dots)
            ...locations.take(locations.length - 1).map(
              (loc) => Marker(
                point: LatLng(loc.latitude, loc.longitude),
                width: 12,
                height: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Current location (larger, pulsing)
            if (currentLocation != null)
              Marker(
                point: LatLng(currentLocation.latitude, currentLocation.longitude),
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.navigation,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
