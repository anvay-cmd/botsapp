import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryGreen = Color(0xFF075E54);
  static const Color darkGreen = Color(0xFF054D44);
  static const Color lightGreen = Color(0xFF25D366);
  static const Color tealGreen = Color(0xFF128C7E);
  static const Color chatBubbleUser = Color(0xFFDCF8C6);
  static const Color chatBubbleBot = Colors.white;
  static const Color chatBackground = Color(0xFFECE5DD);
  static const Color darkBackground = Color(0xFF050505);
  static const Color darkSurface = Color(0xFF1F2C34);
  static const Color darkChatBubbleUser = Color(0xFF005C4B);
  static const Color darkChatBubbleBot = Color(0xFF202C33);
  static const Color darkChatBackground = Color(0xFF0B141A);

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: primaryGreen,
          secondary: tealGreen,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: lightGreen,
          foregroundColor: Colors.white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: tealGreen.withValues(alpha: 0.12),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: primaryGreen, size: 24);
            }
            return IconThemeData(color: Colors.grey.shade600, size: 24);
          }),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: tealGreen,
          secondary: lightGreen,
          surface: darkSurface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
        ),
        scaffoldBackgroundColor: darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkSurface,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: lightGreen,
          foregroundColor: Colors.white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: darkBackground,
          indicatorColor: tealGreen.withValues(alpha: 0.2),
          labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: lightGreen, size: 24);
            }
            return const IconThemeData(color: Colors.grey, size: 24);
          }),
        ),
      );
}
