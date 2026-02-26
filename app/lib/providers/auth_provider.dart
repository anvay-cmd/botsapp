import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../services/auth_service.dart';

class AuthState {
  final AppUser? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isLoggedIn => user != null;
  bool get needsProfileSetup => false;

  AuthState copyWith({AppUser? user, bool? isLoading, String? error}) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService = AuthService();

  AuthNotifier() : super(const AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    state = state.copyWith(isLoading: true);
    final user = await _authService.getCurrentUser();
    state = AuthState(user: user, isLoading: false);
  }

  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _authService.signInWithGoogle();
      if (result != null) {
        state = AuthState(user: result.user);
        return true;
      }
      state = state.copyWith(isLoading: false, error: 'Sign in cancelled');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> devLogin() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _authService.devLogin();
      if (result != null) {
        state = AuthState(user: result.user);
        return true;
      }
      state = state.copyWith(isLoading: false, error: 'Dev login failed');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> updateProfile({String? displayName, String? avatarUrl}) async {
    final updated = await _authService.updateProfile(
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
    if (updated != null) {
      state = AuthState(user: updated);
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
