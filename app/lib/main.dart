import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/callkit_bridge_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CallKitBridgeService.instance.initialize();
  runApp(const ProviderScope(child: BotsApp()));
}
