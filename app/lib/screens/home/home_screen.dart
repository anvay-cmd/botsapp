import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../services/callkit_bridge_service.dart';
import '../../services/gps_service.dart';
import '../../services/api_service.dart';
import 'chats_tab.dart';
import 'integrations_tab.dart';
import 'activities_tab.dart';
import 'settings_tab.dart';

final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CallKitBridgeService.instance.tryConsumePendingIncomingCall();
      unawaited(CallKitBridgeService.instance.syncPushTokens());
      unawaited(_initializeGPSIfEnabled());
    });
  }

  Future<void> _initializeGPSIfEnabled() async {
    try {
      // Check if GPS integration is enabled
      final api = ApiService();
      final response = await api.get('/integrations');
      final integrations = response.data as List;

      final gpsIntegration = integrations.firstWhere(
        (i) => i['provider'] == 'gps',
        orElse: () => null,
      );

      if (gpsIntegration != null && gpsIntegration['is_connected'] == true) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('access_token');

        if (token != null) {
          // Initialize GPS service (this will auto-start if enabled in prefs)
          await GPSService().initialize(AppConstants.apiUrl, token);
        }
      }
    } catch (e) {
      // Silently fail - GPS is optional
      debugPrint('Failed to initialize GPS: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tabs = [
      const ChatsTab(),
      const IntegrationsTab(),
      const ActivitiesTab(),
      const SettingsTab(),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: tabs[currentIndex],
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade200,
                width: 0.5,
              ),
            ),
          ),
          child: NavigationBar(
            height: 80,
            selectedIndex: currentIndex,
            onDestinationSelected: (i) =>
                ref.read(bottomNavIndexProvider.notifier).state = i,
            backgroundColor:
                isDark ? AppTheme.darkBackground : Colors.white,
            indicatorColor: isDark
                ? AppTheme.tealGreen.withValues(alpha: 0.2)
                : AppTheme.tealGreen.withValues(alpha: 0.12),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: Icon(Icons.extension_outlined),
                selectedIcon: Icon(Icons.extension),
                label: 'Integrations',
              ),
              NavigationDestination(
                icon: Icon(Icons.notifications_outlined),
                selectedIcon: Icon(Icons.notifications),
                label: 'Activities',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
