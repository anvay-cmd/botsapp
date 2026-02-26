import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '689199637945-mvo364h0kskt1e4v5ljqhbrn4g7qpgd0.apps.googleusercontent.com',
  );
  final ApiService _api = ApiService();

  Future<void> _syncVoipTokenIfAvailable() async {
    final prefs = await SharedPreferences.getInstance();
    final voipToken = prefs.getString('voip_token');
    if (voipToken == null || voipToken.isEmpty) return;
    try {
      await _api.post('/auth/voip-token', data: {'voip_token': voipToken});
    } catch (_) {}
  }

  Future<({AppUser user, String token})?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) return null;

      final response = await _api.post('/auth/google', data: {
        'id_token': idToken,
      });

      final token = response.data['access_token'] as String;
      final user = AppUser.fromJson(response.data['user']);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token);
      await _syncVoipTokenIfAvailable();

      return (user: user, token: token);
    } catch (e) {
      return null;
    }
  }

  Future<({AppUser user, String token})?> devLogin({
    String email = 'dev@botsapp.local',
    String displayName = 'Dev User',
  }) async {
    try {
      final response = await _api.post('/auth/dev-login', data: {
        'email': email,
        'display_name': displayName,
      });

      final token = response.data['access_token'] as String;
      final user = AppUser.fromJson(response.data['user']);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token);
      await _syncVoipTokenIfAvailable();

      return (user: user, token: token);
    } catch (e) {
      rethrow;
    }
  }

  Future<AppUser?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token == null) return null;

      final response = await _api.get('/auth/me');
      await _syncVoipTokenIfAvailable();
      return AppUser.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }

  Future<AppUser?> updateProfile({String? displayName, String? avatarUrl}) async {
    try {
      final data = <String, dynamic>{};
      if (displayName != null) data['display_name'] = displayName;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;
      final response = await _api.patch('/auth/me', data: data);
      return AppUser.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('access_token');
  }
}
