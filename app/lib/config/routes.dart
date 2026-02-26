import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/profile_setup_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/call/call_screen.dart';
import '../models/bot.dart';
import '../screens/bot/create_bot_screen.dart';
import '../screens/bot/edit_bot_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.isLoggedIn;
      final isOnLogin = state.matchedLocation == '/login';
      final isOnProfileSetup = state.matchedLocation == '/profile-setup';

      if (!isLoggedIn && !isOnLogin) return '/login';
      if (isLoggedIn && isOnLogin) return '/';
      if (isLoggedIn && authState.needsProfileSetup && !isOnProfileSetup) {
        return '/profile-setup';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/chat/:chatId',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ChatScreen(
            chatId: chatId,
            botName: extra['botName'] ?? 'Chat',
            botAvatar: extra['botAvatar'],
            botId: extra['botId'],
          );
        },
      ),
      GoRoute(
        path: '/call/:chatId',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return CallScreen(
            chatId: chatId,
            botName: extra['botName'] ?? 'Bot',
            botAvatar: extra['botAvatar'],
            callId: extra['callId'],
          );
        },
      ),
      GoRoute(
        path: '/create-bot',
        builder: (context, state) => const CreateBotScreen(),
      ),
      GoRoute(
        path: '/edit-bot',
        builder: (context, state) {
          final bot = state.extra as Bot;
          return EditBotScreen(bot: bot);
        },
      ),
    ],
  );
});
