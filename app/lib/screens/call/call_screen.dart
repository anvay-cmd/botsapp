import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/call_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/callkit_bridge_service.dart';
import '../../services/webrtc_service.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String botName;
  final String? botAvatar;
  final String? callId;

  const CallScreen({
    super.key,
    required this.chatId,
    required this.botName,
    this.botAvatar,
    this.callId,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with TickerProviderStateMixin {
  Timer? _durationTimer;
  Duration _duration = Duration.zero;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _startCall();
  }

  Future<void> _startCall() async {
    await ref.read(callProvider.notifier).startCall(
          widget.chatId,
          callId: widget.callId,
        );
    if (!mounted) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _duration += const Duration(seconds: 1));
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) return '${twoDigits(d.inHours)}:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkGreen,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),

            // Avatar
            CircleAvatar(
              radius: 60,
              backgroundColor: AppTheme.tealGreen,
              backgroundImage: widget.botAvatar != null &&
                      widget.botAvatar!.isNotEmpty
                  ? NetworkImage(
                      widget.botAvatar!.startsWith('http')
                          ? widget.botAvatar!
                          : '${AppConstants.baseUrl}${widget.botAvatar}',
                    )
                  : null,
              child: widget.botAvatar == null || widget.botAvatar!.isEmpty
                  ? Text(
                      widget.botName[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 48,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 24),

            // Name
            Text(
              widget.botName,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),

            // Status + duration
            Text(
              callState.isInCall
                  ? _formatDuration(_duration)
                  : 'Connecting...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),

            // Voice activity label
            _ActivityLabel(activity: callState.voiceActivity),

            const Spacer(),

            // Waveform / Loading / Bot speaking indicator
            SizedBox(
              height: 80,
              child: _VoiceVisualizer(
                activity: callState.voiceActivity,
                waveformLevels: callState.waveformLevels,
                audioLevel: callState.audioLevel,
                pulseAnimation: _pulseController,
              ),
            ),

            const Spacer(),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallButton(
                  icon: callState.isMuted ? Icons.mic_off : Icons.mic,
                  label: callState.isMuted ? 'Unmute' : 'Mute',
                  onTap: () => ref.read(callProvider.notifier).toggleMute(),
                  isActive: callState.isMuted,
                ),
                _CallButton(
                  icon: Icons.volume_up,
                  label: 'Speaker',
                  onTap: () =>
                      ref.read(callProvider.notifier).toggleSpeaker(),
                  isActive: callState.isSpeakerOn,
                ),
              ],
            ),
            const SizedBox(height: 40),

            // End call
            GestureDetector(
              onTap: () async {
                final dur = _formatDuration(_duration);
                final transcript = callState.transcriptLines
                    .map((l) => {
                          'role': l.role,
                          'text': l.text,
                        })
                    .toList();
                String? firstUserLine;
                for (final line in callState.transcriptLines) {
                  if (line.role == 'user' && line.text.trim().isNotEmpty) {
                    firstUserLine = line.text;
                    break;
                  }
                }
                final preview =
                    firstUserLine ??
                    (transcript.isNotEmpty ? (transcript.first['text'] ?? '') : '');
                final voiceCallPayload = jsonEncode({
                  'duration': dur,
                  'duration_seconds': _duration.inSeconds,
                  'preview': preview,
                  'transcript': transcript,
                });
                await ref.read(callProvider.notifier).endCall();
                CallKitBridgeService.instance.finishCall(widget.callId);
                ref
                    .read(chatMessagesProvider(widget.chatId).notifier)
                    .sendMessage(
                      voiceCallPayload,
                      contentType: 'voice_call',
                    );
                ref
                    .read(chatListProvider.notifier)
                    .updateLastMessage(widget.chatId, 'Voice call');
                if (context.mounted) context.pop();
              },
              child: Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }
}

class _ActivityLabel extends StatelessWidget {
  final VoiceActivity activity;
  const _ActivityLabel({required this.activity});

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (activity) {
      VoiceActivity.userSpeaking => ('Listening...', AppTheme.lightGreen),
      VoiceActivity.waiting => ('Thinking...', Colors.amber),
      VoiceActivity.botSpeaking => ('Speaking...', AppTheme.tealGreen),
      VoiceActivity.idle => ('', Colors.transparent),
    };

    if (text.isEmpty) return const SizedBox(height: 20);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        text,
        key: ValueKey(activity),
        style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _VoiceVisualizer extends StatelessWidget {
  final VoiceActivity activity;
  final List<double> waveformLevels;
  final double audioLevel;
  final AnimationController pulseAnimation;

  const _VoiceVisualizer({
    required this.activity,
    required this.waveformLevels,
    required this.audioLevel,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (activity) {
        VoiceActivity.userSpeaking => _Waveform(
            key: const ValueKey('waveform'),
            levels: waveformLevels,
          ),
        VoiceActivity.waiting => _PulsingDots(
            key: const ValueKey('dots'),
            animation: pulseAnimation,
          ),
        VoiceActivity.botSpeaking => _BotSpeakingWave(
            key: const ValueKey('bot'),
            animation: pulseAnimation,
          ),
        VoiceActivity.idle => const SizedBox(
            key: ValueKey('idle'),
            height: 80,
          ),
      },
    );
  }
}

class _Waveform extends StatelessWidget {
  final List<double> levels;
  const _Waveform({super.key, required this.levels});

  @override
  Widget build(BuildContext context) {
    const barCount = 30;
    final displayLevels = levels.length >= barCount
        ? levels.sublist(levels.length - barCount)
        : [
            ...List.filled(barCount - levels.length, 0.0),
            ...levels,
          ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(barCount, (i) {
        final level = displayLevels[i];
        final height = max(4.0, level * 60.0);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 3,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: AppTheme.lightGreen,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

class _PulsingDots extends StatelessWidget {
  final AnimationController animation;
  const _PulsingDots({super.key, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final delay = i * 0.3;
            final t = (animation.value + delay) % 1.0;
            final scale = 0.5 + 0.5 * sin(t * pi);
            return Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withValues(alpha: 0.4 + 0.6 * scale),
              ),
            );
          }),
        );
      },
    );
  }
}

class _BotSpeakingWave extends StatelessWidget {
  final AnimationController animation;
  const _BotSpeakingWave({super.key, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(12, (i) {
            final phase = (animation.value * 2 * pi) + (i * 0.5);
            final height = 10.0 + 25.0 * ((sin(phase) + 1) / 2);
            return Container(
              width: 4,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: AppTheme.tealGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
