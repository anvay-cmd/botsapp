import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/webrtc_service.dart';

class CallState {
  final bool isInCall;
  final bool isMuted;
  final bool isSpeakerOn;
  final VoiceActivity voiceActivity;
  final double audioLevel;
  final List<double> waveformLevels;
  final List<VoiceTranscriptLine> transcriptLines;

  const CallState({
    this.isInCall = false,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.voiceActivity = VoiceActivity.idle,
    this.audioLevel = 0.0,
    this.waveformLevels = const [],
    this.transcriptLines = const [],
  });

  CallState copyWith({
    bool? isInCall,
    bool? isMuted,
    bool? isSpeakerOn,
    VoiceActivity? voiceActivity,
    double? audioLevel,
    List<double>? waveformLevels,
    List<VoiceTranscriptLine>? transcriptLines,
  }) =>
      CallState(
        isInCall: isInCall ?? this.isInCall,
        isMuted: isMuted ?? this.isMuted,
        isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
        voiceActivity: voiceActivity ?? this.voiceActivity,
        audioLevel: audioLevel ?? this.audioLevel,
        waveformLevels: waveformLevels ?? this.waveformLevels,
        transcriptLines: transcriptLines ?? this.transcriptLines,
      );
}

class CallNotifier extends StateNotifier<CallState> {
  final WebRTCService _webrtc = WebRTCService();
  StreamSubscription? _levelSub;
  StreamSubscription? _activitySub;
  StreamSubscription? _transcriptSub;

  static const int _maxWaveformBars = 30;

  CallNotifier() : super(const CallState());

  Future<void> startCall(String chatId, {String? callId}) async {
    debugPrint('[CallProvider] startCall: $chatId');
    _levelSub = _webrtc.audioLevelStream.listen((level) {
      final levels = [...state.waveformLevels, level];
      if (levels.length > _maxWaveformBars) {
        levels.removeRange(0, levels.length - _maxWaveformBars);
      }
      state = state.copyWith(audioLevel: level, waveformLevels: levels);
    });

    _activitySub = _webrtc.voiceActivityStream.listen((activity) {
      debugPrint('[CallProvider] voiceActivity: $activity');
      if (activity == VoiceActivity.waiting ||
          activity == VoiceActivity.idle) {
        state = state.copyWith(
            voiceActivity: activity, waveformLevels: const []);
      } else {
        state = state.copyWith(voiceActivity: activity);
      }
    });

    _transcriptSub = _webrtc.transcriptStream.listen((line) {
      final merged = _mergeTranscriptLines(state.transcriptLines, line);
      state = state.copyWith(
        transcriptLines: merged,
      );
    });

    await _webrtc.startCall(chatId, callId: callId);
    debugPrint('[CallProvider] startCall complete, isInCall: ${_webrtc.isInCall}');
    state = state.copyWith(isInCall: _webrtc.isInCall);
  }

  Future<void> endCall() async {
    await _levelSub?.cancel();
    await _activitySub?.cancel();
    await _transcriptSub?.cancel();
    await _webrtc.endCall();
    state = const CallState();
  }

  void toggleMute() {
    _webrtc.toggleMute();
    state = state.copyWith(isMuted: _webrtc.isMuted);
  }

  Future<void> toggleSpeaker() async {
    final enabled = !state.isSpeakerOn;
    await _webrtc.setSpeaker(enabled);
    state = state.copyWith(isSpeakerOn: enabled);
  }

  @override
  void dispose() {
    _levelSub?.cancel();
    _activitySub?.cancel();
    _transcriptSub?.cancel();
    _webrtc.dispose();
    super.dispose();
  }

  List<VoiceTranscriptLine> _mergeTranscriptLines(
    List<VoiceTranscriptLine> existing,
    VoiceTranscriptLine incoming,
  ) {
    final text = _normalizeText(incoming.text);
    if (text.isEmpty) return existing;
    final cleanedIncoming = VoiceTranscriptLine(role: incoming.role, text: text);

    if (existing.isEmpty) return [cleanedIncoming];

    final out = [...existing];
    final last = out.last;

    // Most live transcripts arrive as incremental chunks from same speaker.
    if (last.role == cleanedIncoming.role) {
      final merged = _mergeTexts(last.text, cleanedIncoming.text);
      if (merged == last.text) return out;
      out[out.length - 1] = VoiceTranscriptLine(role: last.role, text: merged);
      return out;
    }

    // Drop exact duplicates even if role-switch noise appears.
    if (last.text == cleanedIncoming.text) return out;

    out.add(cleanedIncoming);
    return out;
  }

  String _mergeTexts(String previous, String incoming) {
    final prev = _normalizeText(previous);
    final next = _normalizeText(incoming);
    if (next.isEmpty) return prev;
    if (prev.isEmpty) return next;
    if (next == prev) return prev;
    if (next.startsWith(prev)) return next; // progressive full-string updates
    if (prev.startsWith(next)) return prev; // ignore regressive shorter partial
    if (next.contains(prev) && next.length > prev.length) return next;

    // Token-level chunking: append gracefully.
    final separator = _needsSpace(prev, next) ? ' ' : '';
    return '$prev$separator$next';
  }

  String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _needsSpace(String left, String right) {
    if (left.isEmpty || right.isEmpty) return false;
    final last = left[left.length - 1];
    final first = right[0];
    const punctuation = '.,!?;:)]}';
    if (punctuation.contains(first)) return false;
    if (last == '(' || last == '[' || last == '{' || last == '-') return false;
    return true;
  }
}

final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  return CallNotifier();
});
