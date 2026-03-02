import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/bot_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/lifecycle_provider.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/message_input.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String botName;
  final String? botAvatar;
  final String? botId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.botName,
    this.botAvatar,
    this.botId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  bool _didClearActiveChat = false;
  bool _isHeartbeatMode = false;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(activeChatIdProvider.notifier).state = widget.chatId;
      unawaited(ref.read(chatListProvider.notifier).markChatRead(widget.chatId));
    });
  }

  void _clearActiveChatIfNeeded() {
    if (_didClearActiveChat || !mounted) return;
    _didClearActiveChat = true;
    if (ref.read(activeChatIdProvider) == widget.chatId) {
      ref.read(activeChatIdProvider.notifier).state = null;
      unawaited(ref.read(chatListProvider.notifier).markChatRead(widget.chatId));
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _toggleHeartbeatMode() {
    setState(() {
      _isHeartbeatMode = !_isHeartbeatMode;
    });

    if (_isHeartbeatMode) {
      // Load lifecycle messages initially
      ref.read(lifecycleMessagesProvider(widget.chatId).notifier).loadMessages();
      // Start polling every 3 seconds
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) {
          ref.read(lifecycleMessagesProvider(widget.chatId).notifier).loadMessages();
        }
      });
    } else {
      // Stop polling
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatMessagesProvider(widget.chatId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(chatMessagesProvider(widget.chatId), (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          prev?.streamingBubbles.length != next.streamingBubbles.length) {
        _scrollToBottom();
      }
    });

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _clearActiveChatIfNeeded();
      },
      child: Scaffold(
      appBar: AppBar(
        leadingWidth: 30,
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: isDark
                  ? AppTheme.darkSurface.withValues(alpha: 0.7)
                  : AppTheme.primaryGreen.withValues(alpha: 0.85),
            ),
          ),
        ),
        title: GestureDetector(
          onTap: _openEditBot,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
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
                            color: Colors.white, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.botName,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (chatState.isBotTyping)
                      const Text(
                        'typing...',
                        style:
                            TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => context.push(
              '/call/${widget.chatId}',
              extra: {
                'botName': widget.botName,
                'botAvatar': widget.botAvatar,
              },
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.monitor_heart,
              color: _isHeartbeatMode ? AppTheme.tealGreen : null,
            ),
            onPressed: _toggleHeartbeatMode,
            tooltip: 'Proactive Messages',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete_bot') _confirmDeleteBot();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'search', child: Text('Search')),
              const PopupMenuItem(value: 'mute', child: Text('Mute')),
              const PopupMenuItem(
                value: 'delete_bot',
                child: Text('Delete Bot',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color:
              isDark ? AppTheme.darkChatBackground : AppTheme.chatBackground,
        ),
        child: Column(
          children: [
            Expanded(
              child: _isHeartbeatMode
                ? _buildProactiveView()
                : chatState.isLoading && chatState.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      itemCount: chatState.messages.length +
                          (chatState.isBotTyping
                              ? chatState.streamingBubbles.length
                              : 0),
                      itemBuilder: (context, index) {
                        // Handle streaming bubbles
                        if (index >= chatState.messages.length) {
                          final bubbleIndex = index - chatState.messages.length;
                          final bubble = chatState.streamingBubbles[bubbleIndex];
                          return ChatBubble(
                            content: bubble.content,
                            isUser: false,
                            timestamp: DateTime.now(),
                            isStreaming: true,
                            contentType: bubble.type == 'tool_call' ? 'tool_call' : 'text',
                          );
                        }
                        final message = chatState.messages[index];
                        return ChatBubble(
                          content: message.content,
                          isUser: message.role == 'user',
                          timestamp: message.createdAt,
                          contentType: message.contentType,
                          attachmentUrl: message.attachmentUrl,
                        );
                      },
                    ),
            ),
            if (!_isHeartbeatMode)
              MessageInput(
                onSend: (content, {String? contentType, String? attachmentUrl}) {
                  ref
                      .read(chatMessagesProvider(widget.chatId).notifier)
                      .sendMessage(
                        content,
                        contentType: contentType ?? 'text',
                        attachmentUrl: attachmentUrl,
                      );
                  ref
                      .read(chatListProvider.notifier)
                      .updateLastMessage(widget.chatId, content);
                },
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildProactiveView() {
    final lifecycleState = ref.watch(lifecycleMessagesProvider(widget.chatId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lifecycleState.isLoading && lifecycleState.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (lifecycleState.messages.isEmpty) {
      return const Center(
        child: Text('No proactive conversations yet'),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: lifecycleState.messages.length,
      itemBuilder: (context, index) {
        final message = lifecycleState.messages[index];

        // Display user prompts as system prompts
        final isSystemMessage = message.role == 'user' ||
                                message.role == 'system' ||
                                message.contentType == 'system_prompt';

        if (isSystemMessage) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.blue.withValues(alpha: 0.2)
                  : Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'System Prompt',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Session ${message.sessionId}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  message.content,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          );
        }

        // Tool result - format JSON nicely
        if (message.contentType == 'tool_result') {
          return _buildToolResultBubble(message, isDark);
        }

        // Tool call or regular assistant message
        return ChatBubble(
          content: message.content,
          isUser: false,
          timestamp: message.createdAt,
          contentType: message.contentType,
        );
      },
    );
  }

  Widget _buildToolResultBubble(dynamic message, bool isDark) {
    String displayText = message.content;

    try {
      final parsed = json.decode(message.content);
      if (parsed is Map) {
        // Format JSON nicely
        final buffer = StringBuffer();
        parsed.forEach((key, value) {
          if (key == 'success' || key == 'error') return;

          if (value is List) {
            buffer.writeln('$key:');
            for (var item in value) {
              if (item is Map) {
                item.forEach((k, v) {
                  buffer.writeln('  • $k: $v');
                });
              } else {
                buffer.writeln('  • $item');
              }
            }
          } else if (value is Map) {
            buffer.writeln('$key:');
            value.forEach((k, v) {
              buffer.writeln('  • $k: $v');
            });
          } else {
            buffer.writeln('$key: $value');
          }
        });

        if (buffer.isNotEmpty) {
          displayText = buffer.toString().trim();
        } else if (parsed['success'] == true) {
          displayText = '✓ Success';
        } else if (parsed['error'] != null) {
          displayText = '✗ Error: ${parsed['error']}';
        }
      }
    } catch (e) {
      // If parsing fails, use original content
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 48, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.arrow_forward,
            size: 14,
            color: isDark ? Colors.green.shade400 : Colors.green.shade600,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditBot() async {
    final botId = widget.botId;
    if (botId == null) return;

    final bot = await ref.read(botListProvider.notifier).getBot(botId);
    if (bot != null && mounted) {
      context.push('/edit-bot', extra: bot);
    }
  }

  void _confirmDeleteBot() {
    final botId = widget.botId;
    if (botId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bot'),
        content: Text(
            'Delete "${widget.botName}" and all its chats?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(botListProvider.notifier).deleteBot(botId);
              if (mounted) {
                ref.read(chatListProvider.notifier).loadChats();
                context.go('/');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
