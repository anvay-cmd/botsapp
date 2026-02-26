import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';

const int _inputSampleRate = 16000;
const int _outputSampleRate = 24000;
// Mic PCM arriving from iOS during active call can be very low-amplitude.
// Keep thresholds low and apply software mic gain before VAD/send decisions.
const double _silenceThreshold = 0.02;
const double _sendNoiseFloor = 0.008;
const double _micInputGain = 6.0;
const double _micGainDuringBotSpeech = 2.4;
const double _bargeInThreshold = 0.14;
const int _bargeInConsecutiveFrames = 5;
const Duration _silenceTimeout = Duration(milliseconds: 800);
const double _playbackGain = 3.2;
const int _playbackFrameBytes = 1920; // ~40ms at 24kHz, 16-bit mono

enum VoiceActivity { idle, userSpeaking, waiting, botSpeaking }

class VoiceTranscriptLine {
  final String role; // "user" | "assistant"
  final String text;

  const VoiceTranscriptLine({required this.role, required this.text});
}

void _log(String msg) {
  debugPrint('[VoiceService] $msg');
}

const MethodChannel _callkitChannel = MethodChannel('botsapp/callkit');

class WebRTCService {
  WebSocketChannel? _channel;
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  StreamSubscription? _wsSubscription;
  StreamController<Uint8List>? _recordingStream;
  bool _isInCall = false;
  bool _isMuted = false;
  bool _isEndingCall = false;

  final _audioLevelController = StreamController<double>.broadcast();
  final _voiceActivityController =
      StreamController<VoiceActivity>.broadcast();
  final _transcriptController = StreamController<VoiceTranscriptLine>.broadcast();
  final List<VoiceTranscriptLine> _transcriptLines = [];

  Stream<double> get audioLevelStream => _audioLevelController.stream;
  Stream<VoiceActivity> get voiceActivityStream =>
      _voiceActivityController.stream;
  Stream<VoiceTranscriptLine> get transcriptStream => _transcriptController.stream;
  List<VoiceTranscriptLine> get transcriptLines => List.unmodifiable(_transcriptLines);

  bool get isInCall => _isInCall;
  bool get isMuted => _isMuted;

  VoiceActivity _currentActivity = VoiceActivity.idle;
  Timer? _silenceTimer;
  Timer? _turnCompleteTimer;
  bool _botIsSpeaking = false;
  bool _userTurnActive = false;
  int _bargeInFrames = 0;
  DateTime _lastBotAudioAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _playbackQueue = Future.value();
  DateTime _lastSpeakerRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _speakerOn = true;

  void _setActivity(VoiceActivity activity) {
    if (_currentActivity == activity) return;
    _currentActivity = activity;
    if (!_voiceActivityController.isClosed) {
      _voiceActivityController.add(activity);
    }
  }

  double _computeLevel(Uint8List pcmData) {
    if (pcmData.length < 2) return 0.0;
    final samples = pcmData.buffer.asInt16List(
        pcmData.offsetInBytes, pcmData.lengthInBytes ~/ 2);
    double sumSquares = 0;
    for (final s in samples) {
      sumSquares += s * s;
    }
    final rms = sqrt(sumSquares / samples.length) / 32768.0;
    return rms.clamp(0.0, 1.0);
  }

  Uint8List _boostMic(Uint8List pcm, {double gain = _micInputGain}) {
    final samples =
        pcm.buffer.asInt16List(pcm.offsetInBytes, pcm.lengthInBytes ~/ 2);
    final out = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      out[i] = (samples[i] * gain).round().clamp(-32768, 32767);
    }
    return Uint8List.view(out.buffer);
  }

  Future<void> startCall(String chatId, {String? callId}) async {
    _log('=== START CALL chatId=$chatId callId=$callId ===');
    _transcriptLines.clear();
    try {
      // 1. Mic permission
      _log('Step 1: requesting mic permission');
      final micStatus = await Permission.microphone.request();
      _log('Mic status: $micStatus');
      if (!micStatus.isGranted) {
        _log('ERROR: mic permission denied');
        return;
      }

      // 2. Auth token
      _log('Step 2: getting auth token');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token == null) {
        _log('ERROR: no auth token');
        return;
      }
      _log('Token found (${token.length} chars)');

      // 3. WebSocket connect
      final callParam =
          (callId != null && callId.isNotEmpty) ? '&call_id=$callId' : '';
      final wsUrl = '${AppConstants.wsVoiceUrl}/$chatId?token=$token$callParam';
      _log('Step 3: connecting WS to $wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;
      _log('WS connected successfully');

      // 4. Wait for server ready
      _log('Step 4: waiting for server ready signal');
      final readyCompleter = Completer<void>();
      _wsSubscription = _channel!.stream.listen(
        (data) {
          if (data is String) {
            _log('WS text received: $data');
            final msg = jsonDecode(data);
            if (msg['type'] == 'ready' && !readyCompleter.isCompleted) {
              readyCompleter.complete();
            } else if (msg['type'] == 'voice') {
              final role = (msg['role'] ?? '').toString();
              final text = (msg['text'] ?? '').toString().trim();
              if (text.isNotEmpty &&
                  (role == 'user' || role == 'assistant')) {
                final line = VoiceTranscriptLine(role: role, text: text);
                _transcriptLines.add(line);
                if (!_transcriptController.isClosed) {
                  _transcriptController.add(line);
                }
              }
            } else if (msg['type'] == 'turn_complete') {
              // Gemini can emit turn_complete early; debounce so we only
              // finalize when no bot audio has arrived for a short window.
              _turnCompleteTimer?.cancel();
              _turnCompleteTimer = Timer(const Duration(milliseconds: 220), () {
                final sinceAudio = DateTime.now().difference(_lastBotAudioAt);
                if (sinceAudio.inMilliseconds >= 180) {
                  _log('Bot turn complete');
                  _botIsSpeaking = false;
                  if (_currentActivity == VoiceActivity.botSpeaking) {
                    _setActivity(VoiceActivity.idle);
                  }
                }
              });
            }
          } else if (data is List<int>) {
            _log('WS binary received: ${data.length} bytes');
            _lastBotAudioAt = DateTime.now();
            _turnCompleteTimer?.cancel();
            _botIsSpeaking = true;
            _silenceTimer?.cancel();
            _setActivity(VoiceActivity.botSpeaking);
            _playAudio(Uint8List.fromList(data));
          }
        },
        onError: (e) {
          _log('WS error: $e');
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(e);
          }
        },
        onDone: () {
          _log('WS connection closed');
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError('Connection closed before ready');
          }
        },
      );

      await readyCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _log('ERROR: timed out waiting for server ready');
          throw TimeoutException('Server ready timeout');
        },
      );
      _log('Server is ready');
      _isInCall = true;

      await _configureNativeCallAudio();

      // 5. Start player
      _log('Step 5: opening audio player');
      await _startPlayer();
      _log('Player started');

      // 6. Start recorder
      _log('Step 6: opening audio recorder');
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _log('Recorder opened');

      int chunkCount = 0;
      _recordingStream = StreamController<Uint8List>();
      _recordingStream!.stream.listen((data) {
        chunkCount++;
        final micFrame = _boostMic(
          data,
          gain: _botIsSpeaking ? _micGainDuringBotSpeech : _micInputGain,
        );
        final level = _computeLevel(micFrame);

        if (chunkCount <= 3 || chunkCount % 100 == 0) {
          _log('Audio chunk #$chunkCount: ${data.length} bytes, level=$level');
        }

        if (!_audioLevelController.isClosed) {
          _audioLevelController.add(level);
        }

        if (_botIsSpeaking) {
          // Strong echo suppression + high-threshold barge-in.
          // User must speak loudly for several consecutive frames.
          if (level > _bargeInThreshold) {
            _bargeInFrames++;
          } else {
            _bargeInFrames = 0;
          }
          final allowBargeIn = _bargeInFrames >= _bargeInConsecutiveFrames;
          if (allowBargeIn) {
            _userTurnActive = true;
            _silenceTimer?.cancel();
            if (_currentActivity != VoiceActivity.userSpeaking) {
              _setActivity(VoiceActivity.userSpeaking);
            }
          } else {
            _userTurnActive = false;
            _silenceTimer?.cancel();
          }
        } else {
          _bargeInFrames = 0;
          if (level > _silenceThreshold) {
            _userTurnActive = true;
            _silenceTimer?.cancel();
            if (_currentActivity != VoiceActivity.userSpeaking) {
              _setActivity(VoiceActivity.userSpeaking);
            }
          } else if (_currentActivity == VoiceActivity.userSpeaking) {
            _silenceTimer?.cancel();
            _silenceTimer = Timer(_silenceTimeout, () {
              _userTurnActive = false;
              _signalUserTurnEnd();
              _setActivity(VoiceActivity.waiting);
            });
          }
        }

        if (!_isMuted) {
          final shouldSend = _botIsSpeaking
              ? (_bargeInFrames >= _bargeInConsecutiveFrames &&
                  level > _bargeInThreshold)
              : (_userTurnActive || level > _sendNoiseFloor);
          if (!shouldSend) return;
          try {
            _channel?.sink.add(micFrame);
          } catch (e) {
            _log('Error sending audio: $e');
          }
        }
      });

      await _recorder!.startRecorder(
        toStream: _recordingStream!.sink,
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: _inputSampleRate,
      );
      // flutter_sound may reconfigure AVAudioSession; force speaker route again.
      await _configureNativeCallAudio();
      await _setSpeakerEnabled(_speakerOn);
      _log('Recorder started - CALL IS ACTIVE');
      _setActivity(VoiceActivity.idle);
    } catch (e, st) {
      _log('ERROR in startCall: $e');
      _log('Stack: $st');
      unawaited(endCall());
    }
  }

  Uint8List _amplify(Uint8List pcm) {
    final samples =
        pcm.buffer.asInt16List(pcm.offsetInBytes, pcm.lengthInBytes ~/ 2);
    final out = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      out[i] = (samples[i] * _playbackGain).round().clamp(-32768, 32767);
    }
    return Uint8List.view(out.buffer);
  }

  void _playAudio(Uint8List data) {
    if (_player != null && _isInCall) {
      _maybeReassertSpeakerRoute();
      final amplified = _amplify(data);
      _playbackQueue = _playbackQueue.then((_) async {
        if (_player == null || !_isInCall) return;
        // Feed in smaller frames to match player pull cadence and avoid choppy output.
        for (int i = 0; i < amplified.length; i += _playbackFrameBytes) {
          if (_player == null || !_isInCall) return;
          final end = (i + _playbackFrameBytes < amplified.length)
              ? i + _playbackFrameBytes
              : amplified.length;
          final frame = Uint8List.fromList(amplified.sublist(i, end));
          try {
            await _player!.feedFromStream(frame);
          } catch (e) {
            _log('feedFromStream failed, attempting recovery: $e');
            await _recoverPlayer();
            if (_player != null && _isInCall) {
              await _player!.feedFromStream(frame);
            }
          }
        }
      }).catchError((e) {
        _log('Playback error: $e');
      });
    }
  }

  void _signalUserTurnEnd() {
    try {
      _channel?.sink.add(jsonEncode({'type': 'user_turn_end'}));
    } catch (_) {}
  }

  Future<void> endCall() async {
    if (_isEndingCall) return;
    if (!_isInCall && _channel == null) return;
    _isEndingCall = true;
    _log('=== END CALL ===');
    _isInCall = false;
    _isMuted = false;
    _botIsSpeaking = false;
    _userTurnActive = false;
    _silenceTimer?.cancel();
    _turnCompleteTimer?.cancel();
    _setActivity(VoiceActivity.idle);

    try {
      _channel?.sink.add(jsonEncode({'type': 'end_call'}));
    } catch (_) {}

    try {
      await _recorder?.stopRecorder();
    } catch (_) {}
    try {
      await _recorder?.closeRecorder();
    } catch (_) {}
    _recorder = null;

    await _recordingStream?.close();
    _recordingStream = null;

    try {
      await _player?.stopPlayer();
    } catch (_) {}
    try {
      await _player?.closePlayer();
    } catch (_) {}
    _player = null;

    await _wsSubscription?.cancel();
    _wsSubscription = null;

    await _channel?.sink.close();
    _channel = null;

    await _resetNativeCallAudio();
    _isEndingCall = false;
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _log('Mute toggled: $_isMuted');
  }

  Future<void> setSpeaker(bool enabled) async {
    _speakerOn = enabled;
    await _setSpeakerEnabled(enabled);
    if (enabled) {
      await _configureNativeCallAudio();
    }
  }

  void dispose() {
    unawaited(endCall());
    _audioLevelController.close();
    _voiceActivityController.close();
    _transcriptController.close();
  }

  Future<void> _configureNativeCallAudio() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _callkitChannel.invokeMethod('configureCallAudio');
      _log('Requested native call audio config (speaker route)');
    } catch (e) {
      _log('Native call audio config failed: $e');
    }
  }

  Future<void> _resetNativeCallAudio() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _callkitChannel.invokeMethod('resetCallAudio');
    } catch (_) {}
  }

  Future<void> _setSpeakerEnabled(bool enabled) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _callkitChannel
          .invokeMethod('setSpeakerEnabled', {'enabled': enabled});
    } catch (e) {
      _log('setSpeakerEnabled failed: $e');
    }
  }

  Future<void> _startPlayer() async {
    _player ??= FlutterSoundPlayer();
    if (!_player!.isOpen()) {
      await _player!.openPlayer();
    }
    await _player!.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: _outputSampleRate,
      bufferSize: 32768,
      interleaved: false,
    );
    await _player!.setVolume(1.0);
  }

  Future<void> _recoverPlayer() async {
    if (!_isInCall) return;
    try {
      await _player?.stopPlayer();
    } catch (_) {}
    try {
      await _player?.closePlayer();
    } catch (_) {}
    _player = FlutterSoundPlayer();
    await _startPlayer();
    await _configureNativeCallAudio();
    await _setSpeakerEnabled(_speakerOn);
    _log('Player recovered and audio route reasserted');
  }

  void _maybeReassertSpeakerRoute() {
    final now = DateTime.now();
    if (now.difference(_lastSpeakerRefreshAt).inSeconds < 2) return;
    _lastSpeakerRefreshAt = now;
    unawaited(_setSpeakerEnabled(_speakerOn));
  }
}
