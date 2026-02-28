import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../config/theme.dart';

class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String contentType;
  final String? attachmentUrl;
  final bool isStreaming;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.contentType = 'text',
    this.attachmentUrl,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (contentType == 'voice_call') {
      return _VoiceCallBubble(
        content: content,
        isUser: isUser,
        timestamp: timestamp,
        isDark: isDark,
      );
    }

    if (contentType == 'tool_call') {
      return _ToolCallBubble(
        content: content,
        timestamp: timestamp,
        isDark: isDark,
        isStreaming: isStreaming,
      );
    }

    final bgColor = isUser
        ? (isDark ? AppTheme.darkChatBubbleUser : AppTheme.chatBubbleUser)
        : (isDark ? AppTheme.darkChatBubbleBot : AppTheme.chatBubbleBot);

    final timeStr = DateFormat('h:mm a').format(timestamp);

    final timeWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 10,
            color: isUser
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.55)
                    : Colors.black.withValues(alpha: 0.45))
                : (isDark ? Colors.grey.shade500 : Colors.grey.shade500),
          ),
        ),
        if (isUser) ...[
          const SizedBox(width: 3),
          Icon(Icons.done_all, size: 13, color: AppTheme.tealGreen),
        ],
        if (isStreaming) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 9,
            height: 9,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppTheme.tealGreen,
            ),
          ),
        ],
      ],
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 6,
          right: isUser ? 6 : 48,
          top: 1.5,
          bottom: 1.5,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(10),
            topRight: const Radius.circular(10),
            bottomLeft: isUser ? const Radius.circular(10) : const Radius.circular(3),
            bottomRight: isUser ? const Radius.circular(3) : const Radius.circular(10),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (contentType == 'image' && attachmentUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    attachmentUrl!.startsWith('http')
                        ? attachmentUrl!
                        : '${AppConstants.baseUrl}$attachmentUrl',
                    width: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image, size: 48),
                  ),
                ),
                if (content.isNotEmpty) const SizedBox(height: 4),
              ],
              if (content.isNotEmpty)
                Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: isUser
                          ? RichText(
                              text: TextSpan(
                                text: content,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  height: 1.25,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.92)
                                      : Colors.black.withValues(alpha: 0.87),
                                ),
                                children: [
                                  WidgetSpan(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Opacity(
                                        opacity: 0,
                                        child: timeWidget,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MarkdownBody(
                                  data: content,
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet(
                                    p: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.25,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.92)
                                          : Colors.black.withValues(alpha: 0.87),
                                    ),
                                    code: TextStyle(
                                      fontSize: 13,
                                      backgroundColor: isDark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : Colors.black.withValues(alpha: 0.05),
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.95)
                                          : Colors.black.withValues(alpha: 0.9),
                                    ),
                                    codeblockDecoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black.withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    blockquote: TextStyle(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.7)
                                          : Colors.black.withValues(alpha: 0.7),
                                      fontStyle: FontStyle.italic,
                                    ),
                                    a: TextStyle(
                                      color: AppTheme.tealGreen,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                  onTapLink: (text, href, title) {
                                    if (href != null) {
                                      launchUrl(Uri.parse(href),
                                          mode: LaunchMode.externalApplication);
                                    }
                                  },
                                ),
                                const SizedBox(height: 2),
                                Opacity(opacity: 0, child: timeWidget),
                              ],
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: timeWidget,
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: timeWidget,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceCallBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isDark;

  const _VoiceCallBubble({
    required this.content,
    required this.isUser,
    required this.timestamp,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = _ParsedVoiceCall.fromContent(content);
    final bgColor = isUser
        ? (isDark ? AppTheme.darkChatBubbleUser : AppTheme.chatBubbleUser)
        : (isDark ? AppTheme.darkChatBubbleBot : AppTheme.chatBubbleBot);
    final timeStr = DateFormat('h:mm a').format(timestamp);

    final isOutgoing = isUser;
    final iconColor = isOutgoing ? Colors.green : Colors.red;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: parsed.transcript.isEmpty
            ? null
            : () => _showTranscriptModal(context, parsed),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          margin: EdgeInsets.only(
            left: isUser ? 48 : 6,
            right: isUser ? 6 : 48,
            top: 1.5,
            bottom: 1.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft:
                  isUser ? const Radius.circular(10) : const Radius.circular(3),
              bottomRight:
                  isUser ? const Radius.circular(3) : const Radius.circular(10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.call,
                  size: 18,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice call • ${parsed.durationLabel}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parsed.previewLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    if (parsed.transcript.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Tap to view transcript',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.tealGreen.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 3),
                Icon(Icons.done_all, size: 14, color: AppTheme.tealGreen),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showTranscriptModal(BuildContext context, _ParsedVoiceCall parsed) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Voice call transcript',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Duration: ${parsed.durationLabel}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: ListView.separated(
                    itemCount: parsed.transcript.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final line = parsed.transcript[index];
                      final isUserLine = line.role == 'user';
                      return Text(
                        line.text,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.34,
                          fontWeight:
                              isUserLine ? FontWeight.w600 : FontWeight.w400,
                          color: isDark
                              ? Colors.white.withValues(
                                  alpha: isUserLine ? 0.94 : 0.64)
                              : Colors.black.withValues(
                                  alpha: isUserLine ? 0.9 : 0.58),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TranscriptLine {
  final String role;
  final String text;

  const _TranscriptLine({required this.role, required this.text});
}

class _ParsedVoiceCall {
  final String durationLabel;
  final String previewLabel;
  final List<_TranscriptLine> transcript;

  const _ParsedVoiceCall({
    required this.durationLabel,
    required this.previewLabel,
    required this.transcript,
  });

  factory _ParsedVoiceCall.fromContent(String raw) {
    if (raw.trim().isEmpty) {
      return const _ParsedVoiceCall(
        durationLabel: 'No answer',
        previewLabel: 'No transcript',
        transcript: [],
      );
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not voice call json');
      }
      final duration = (decoded['duration'] ?? '').toString().trim();
      final preview = (decoded['preview'] ?? '').toString().trim();
      final rawTranscript = (decoded['transcript'] as List<dynamic>? ?? []);
      final transcript = rawTranscript
          .whereType<Map>()
          .map(
            (e) => _TranscriptLine(
              role: (e['role'] ?? 'assistant').toString(),
              text: (e['text'] ?? '').toString(),
            ),
          )
          .toList();
      final cleanedTranscript = _cleanTranscript(transcript);

      return _ParsedVoiceCall(
        durationLabel: duration.isNotEmpty ? duration : 'No answer',
        previewLabel: preview.isNotEmpty
            ? preview
            : (cleanedTranscript.isNotEmpty
                ? cleanedTranscript.first.text
                : 'No transcript'),
        transcript: cleanedTranscript,
      );
    } catch (_) {
      // Backward compatibility with old plain-text voice_call messages.
      return _ParsedVoiceCall(
        durationLabel: raw,
        previewLabel: raw,
        transcript: const [],
      );
    }
  }
}

List<_TranscriptLine> _cleanTranscript(List<_TranscriptLine> raw) {
  final out = <_TranscriptLine>[];
  for (final line in raw) {
    final role = line.role.trim().toLowerCase() == 'user' ? 'user' : 'assistant';
    final text = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    if (out.isEmpty) {
      out.add(_TranscriptLine(role: role, text: text));
      continue;
    }
    final last = out.last;
    if (last.role == role) {
      final merged = _mergeTranscriptText(last.text, text);
      out[out.length - 1] = _TranscriptLine(role: role, text: merged);
    } else if (last.text != text) {
      out.add(_TranscriptLine(role: role, text: text));
    }
  }
  return out;
}

String _mergeTranscriptText(String previous, String incoming) {
  if (incoming == previous) return previous;
  if (incoming.startsWith(previous)) return incoming;
  if (previous.startsWith(incoming)) return previous;
  if (incoming.contains(previous) && incoming.length > previous.length) return incoming;
  final sep = _needsSpace(previous, incoming) ? ' ' : '';
  return '$previous$sep$incoming';
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

class _ToolCallBubble extends StatelessWidget {
  final String content;
  final DateTime timestamp;
  final bool isDark;
  final bool isStreaming;

  const _ToolCallBubble({
    required this.content,
    required this.timestamp,
    required this.isDark,
    required this.isStreaming,
  });

  String _formatToolCall(String content) {
    try {
      final data = jsonDecode(content);
      final name = data['name'] ?? 'unknown';
      final args = data['args'] ?? {};

      switch (name) {
        case 'web_search':
          final query = args['query'] ?? '';
          return 'Searching the web for "$query"';

        case 'gmail_list_emails':
          final count = args['max_results'] ?? 10;
          return 'Checking inbox ($count emails)';

        case 'gmail_search_emails':
          final query = args['query'] ?? '';
          return 'Searching emails for "$query"';

        case 'gmail_send_email':
          final to = args['to'] ?? '';
          final subject = args['subject'] ?? '';
          return 'Sending email to $to${subject.isNotEmpty ? ' - "$subject"' : ''}';

        case 'schedule_call':
          final time = args['scheduled_time'] ?? '';
          return 'Scheduling call${time.isNotEmpty ? ' for $time' : ''}';

        case 'call_now':
          final message = args['message'] ?? '';
          return 'Calling now${message.isNotEmpty ? ' - $message' : ''}';

        case 'cancel_schedule':
          final keyword = args['keyword'] ?? '';
          return 'Canceling scheduled call${keyword.isNotEmpty ? ' ($keyword)' : ''}';

        default:
          // Format any args
          if (args.isEmpty) {
            return name.replaceAll('_', ' ');
          }
          final argsList = args.entries
              .map((e) => '${e.key}: ${e.value}')
              .join(', ');
          return '${name.replaceAll('_', ' ')} ($argsList)';
      }
    } catch (e) {
      // Fallback for non-JSON content
      return content;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(timestamp);
    final formattedContent = _formatToolCall(content);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 6, right: 48, top: 1, bottom: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 4,
              color: isDark
                  ? Colors.grey.shade600
                  : Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                formattedContent,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isDark
                      ? Colors.grey.shade500
                      : Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? Colors.grey.shade700
                    : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
