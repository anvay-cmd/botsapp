import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/constants.dart';
import 'services/callkit_bridge_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Debug: Print the API URL being used
  debugPrint('🌐 API URL: ${AppConstants.apiUrl}');
  debugPrint('🔌 WebSocket URL: ${AppConstants.wsUrl}');

  await CallKitBridgeService.instance.initialize();
  runApp(const ProviderScope(child: BotsApp()));
}
