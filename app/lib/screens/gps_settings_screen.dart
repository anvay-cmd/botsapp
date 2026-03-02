import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/gps_service.dart';

class GPSSettingsScreen extends StatefulWidget {
  const GPSSettingsScreen({super.key});

  @override
  State<GPSSettingsScreen> createState() => _GPSSettingsScreenState();
}

class _GPSSettingsScreenState extends State<GPSSettingsScreen> {
  final GPSService _gpsService = GPSService();
  bool _isEnabled = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _geofences = [];
  Position? _currentLocation;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final enabled = await _gpsService.isIntegrationEnabled();
    final fences = await _gpsService.getGeofences();
    final location = await _gpsService.getCurrentLocation();

    setState(() {
      _isEnabled = enabled;
      _geofences = fences;
      _currentLocation = location;
      _isLoading = false;
    });
  }

  Future<void> _toggleGPS(bool value) async {
    if (value) {
      // Check permissions first
      final hasPermission = await _gpsService.checkPermissions();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await _gpsService.enableIntegration();
    } else {
      await _gpsService.disableIntegration();
    }

    await _loadSettings();
  }

  Future<void> _createGeofence() async {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting current location...')),
      );

      final location = await _gpsService.getCurrentLocation();
      if (location == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get current location'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _currentLocation = location);
    }

    // Show dialog to create geofence
    final nameController = TextEditingController();
    final radiusController = TextEditingController(text: '100');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Geofence'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Home, Office, Gym...',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: radiusController,
              decoration: const InputDecoration(
                labelText: 'Radius (meters)',
                hintText: '100',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            Text(
              'Location: ${_currentLocation!.latitude.toStringAsFixed(6)}, '
              '${_currentLocation!.longitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name')),
                );
                return;
              }

              final radius = double.tryParse(radiusController.text) ?? 100;

              final fence = await _gpsService.createGeofence(
                name: nameController.text,
                latitude: _currentLocation!.latitude,
                longitude: _currentLocation!.longitude,
                radius: radius,
              );

              if (fence != null) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geofence created successfully')),
      );
      await _loadSettings();
    }
  }

  Future<void> _deleteGeofence(String fenceId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Geofence'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _gpsService.deleteGeofence(fenceId);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geofence deleted')),
        );
        await _loadSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS & Location'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Enable GPS Tracking'),
                  subtitle: const Text(
                    'Allow bots to access your location and track movement',
                  ),
                  value: _isEnabled,
                  onChanged: _toggleGPS,
                ),
                const Divider(),
                if (_currentLocation != null) ...[
                  ListTile(
                    leading: const Icon(Icons.my_location),
                    title: const Text('Current Location'),
                    subtitle: Text(
                      '${_currentLocation!.latitude.toStringAsFixed(6)}, '
                      '${_currentLocation!.longitude.toStringAsFixed(6)}\n'
                      'Accuracy: ±${_currentLocation!.accuracy.toStringAsFixed(0)}m',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        final location = await _gpsService.getCurrentLocation();
                        if (location != null) {
                          setState(() => _currentLocation = location);
                        }
                      },
                    ),
                  ),
                  const Divider(),
                ],
                ListTile(
                  leading: const Icon(Icons.fence),
                  title: const Text('Geofences'),
                  subtitle: Text('${_geofences.length} active'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _isEnabled ? _createGeofence : null,
                  ),
                ),
                if (_geofences.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No geofences. Create one to get location-based notifications.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ..._geofences.map((fence) {
                    return ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(fence['name']),
                      subtitle: Text(
                        '${fence['latitude'].toStringAsFixed(6)}, '
                        '${fence['longitude'].toStringAsFixed(6)}\n'
                        'Radius: ${fence['radius'].toStringAsFixed(0)}m',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteGeofence(
                          fence['id'],
                          fence['name'],
                        ),
                      ),
                    );
                  }).toList(),
              ],
            ),
    );
  }
}
