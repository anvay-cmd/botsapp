import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bot.dart';
import '../services/api_service.dart';

class BotListState {
  final List<Bot> bots;
  final bool isLoading;

  const BotListState({this.bots = const [], this.isLoading = false});
}

class BotListNotifier extends StateNotifier<BotListState> {
  final ApiService _api = ApiService();

  BotListNotifier() : super(const BotListState());

  Future<Bot?> getBot(String botId) async {
    final cached = state.bots.where((b) => b.id == botId);
    if (cached.isNotEmpty) return cached.first;
    await loadBots();
    final found = state.bots.where((b) => b.id == botId);
    return found.isNotEmpty ? found.first : null;
  }

  Future<void> loadBots() async {
    state = BotListState(bots: state.bots, isLoading: true);
    try {
      final response = await _api.get('/bots');
      final bots =
          (response.data as List).map((j) => Bot.fromJson(j)).toList();
      state = BotListState(bots: bots);
    } catch (e) {
      state = BotListState(bots: state.bots);
    }
  }

  Future<Bot?> createBot({
    required String name,
    required String systemPrompt,
    String voiceName = 'Kore',
    int? proactiveMinutes = 0,
    Map<String, dynamic>? integrationsConfig,
  }) async {
    try {
      final response = await _api.post('/bots', data: {
        'name': name,
        'system_prompt': systemPrompt,
        'voice_name': voiceName,
        'proactive_minutes': proactiveMinutes,
        'integrations_config': integrationsConfig,
      });
      final bot = Bot.fromJson(response.data);
      state = BotListState(bots: [...state.bots, bot]);
      return bot;
    } catch (e) {
      return null;
    }
  }

  Future<Bot?> updateBot({
    required String botId,
    String? name,
    String? systemPrompt,
    String? voiceName,
    int? proactiveMinutes,
    String? avatarUrl,
    Map<String, dynamic>? integrationsConfig,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (systemPrompt != null) data['system_prompt'] = systemPrompt;
      if (voiceName != null) data['voice_name'] = voiceName;
      if (proactiveMinutes != null) data['proactive_minutes'] = proactiveMinutes;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;
      if (integrationsConfig != null) {
        data['integrations_config'] = integrationsConfig;
      }
      final response = await _api.patch('/bots/$botId', data: data);
      final updatedBot = Bot.fromJson(response.data);
      state = BotListState(
        bots: state.bots.map((b) => b.id == botId ? updatedBot : b).toList(),
      );
      return updatedBot;
    } catch (e) {
      return null;
    }
  }

  Future<Bot?> generateImage(String botId, String prompt) async {
    try {
      final response = await _api.post(
        '/bots/$botId/generate-image',
        data: {'prompt': prompt},
      );
      final updatedBot = Bot.fromJson(response.data);
      state = BotListState(
        bots: state.bots.map((b) => b.id == botId ? updatedBot : b).toList(),
      );
      return updatedBot;
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteBot(String botId) async {
    try {
      await _api.delete('/bots/$botId');
      state = BotListState(
        bots: state.bots.where((b) => b.id != botId).toList(),
      );
    } catch (_) {}
  }
}

final botListProvider =
    StateNotifierProvider<BotListNotifier, BotListState>((ref) {
  return BotListNotifier();
});
