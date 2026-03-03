import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../models/message.dart';
import '../../providers/bot_provider.dart';
import '../../providers/chat_provider.dart' show ChatListProvider, chatListProvider, activeChatIdProvider, ChatMessagesProvider, chatMessagesProvider, ChatMessagesState, MessageBubble;
import '../../providers/lifecycle_provider.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/heartbeat_icon.dart';
import '../../widgets/message_input.dart';

class _ToolCallGroup {
  final dynamic firstCall; // null if we don't show first
  final List<dynamic> middleCalls;
  final dynamic lastCall;
  final int groupId;

  _ToolCallGroup({
    this.firstCall,
    required this.middleCalls,
    required this.lastCall,
    required this.groupId,
  });
}

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
  final Set<int> _expandedToolCallGroups = {};

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
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
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
            icon: HeartbeatIcon(
              size: 22,
              color: _isHeartbeatMode ? AppTheme.tealGreen : Colors.white,
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
                  : _buildChatView(chatState),
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

  Widget _buildChatView(ChatMessagesState chatState) {
    // Group tool calls
    final displayItems = _groupToolCalls(chatState);

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final reversedIndex = displayItems.length - 1 - index;
        final item = displayItems[reversedIndex];

        if (item is _ToolCallGroup) {
          return _buildToolCallGroup(item);
        } else if (item is Message) {
          return ChatBubble(
            content: item.content,
            isUser: item.role == 'user',
            timestamp: item.createdAt,
            contentType: item.contentType,
            attachmentUrl: item.attachmentUrl,
          );
        } else if (item is MessageBubble) {
          return ChatBubble(
            content: item.content,
            isUser: false,
            timestamp: DateTime.now(),
            isStreaming: true,
            contentType: item.type == 'tool_call' ? 'tool_call' : 'text',
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  List<dynamic> _groupToolCalls(ChatMessagesState chatState) {
    final items = <dynamic>[];

    // Add all messages first
    items.addAll(chatState.messages);

    // Add streaming bubbles
    if (chatState.isBotTyping) {
      items.addAll(chatState.streamingBubbles);
    }

    // Now group consecutive tool calls
    final result = <dynamic>[];
    var i = 0;

    while (i < items.length) {
      final item = items[i];

      // Check if this is a tool call
      final isToolCall = (item is Message && item.contentType == 'tool_call') ||
                        (item is MessageBubble && item.type == 'tool_call');

      if (!isToolCall) {
        result.add(item);
        i++;
        continue;
      }

      // Find consecutive tool calls
      final toolCallStart = i;
      while (i < items.length) {
        final current = items[i];
        final isCurrentToolCall = (current is Message && current.contentType == 'tool_call') ||
                                  (current is MessageBubble && current.type == 'tool_call');
        if (!isCurrentToolCall) break;
        i++;
      }

      final toolCallCount = i - toolCallStart;

      // If more than 2 tool calls, create a group
      if (toolCallCount > 2) {
        final toolCalls = items.sublist(toolCallStart, i);
        result.add(_ToolCallGroup(
          firstCall: null,
          middleCalls: toolCalls.sublist(0, toolCalls.length - 1),
          lastCall: toolCalls.last,
          groupId: toolCallStart,
        ));
      } else {
        // Add them individually
        result.addAll(items.sublist(toolCallStart, i));
      }
    }

    return result;
  }

  Widget _buildToolCallGroup(_ToolCallGroup group) {
    final isExpanded = _expandedToolCallGroups.contains(group.groupId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // First tool call (only if not null)
        if (group.firstCall != null)
          _buildToolCallItem(group.firstCall),

        // Middle calls (collapsed or expanded)
        if (isExpanded)
          ...group.middleCalls.map((call) => _buildToolCallItem(call))
        else
          GestureDetector(
            onTap: () {
              setState(() {
                _expandedToolCallGroups.add(group.groupId);
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 48, top: 2, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.expand_more,
                    size: 14,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${group.middleCalls.length} tool call${group.middleCalls.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Last tool call
        _buildToolCallItem(group.lastCall),
      ],
    );
  }

  Widget _buildToolCallItem(dynamic item) {
    if (item is Message) {
      return ChatBubble(
        content: item.content,
        isUser: false,
        timestamp: item.createdAt,
        contentType: item.contentType,
      );
    } else if (item is MessageBubble) {
      return ChatBubble(
        content: item.content,
        isUser: false,
        timestamp: DateTime.now(),
        isStreaming: true,
        contentType: 'tool_call',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildProactiveView() {
    final lifecycleState = ref.watch(lifecycleMessagesProvider(widget.chatId));

    if (lifecycleState.isLoading && lifecycleState.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (lifecycleState.messages.isEmpty) {
      return const Center(
        child: Text('No proactive conversations yet'),
      );
    }

    // Filter to only show user-type messages (proactivity prompts, not main system prompt)
    final filteredMessages = lifecycleState.messages.where((msg) {
      // Only show user messages (proactivity prompts)
      if (msg.role == 'user') return true;
      // Show assistant text responses
      if (msg.role == 'assistant' && msg.contentType == 'text') return true;
      // Show tool calls and tool results
      if (msg.contentType == 'tool_call' || msg.contentType == 'tool_result') return true;
      return false;
    }).toList();

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: filteredMessages.length,
      itemBuilder: (context, index) {
        final reversedIndex = filteredMessages.length - 1 - index;
        final message = filteredMessages[reversedIndex];

        // User messages are system prompts - show as blue bubble on left
        if (message.role == 'user') {
          return ChatBubble(
            content: message.content,
            isUser: true,
            timestamp: message.createdAt,
            contentType: 'text',
          );
        }

        // Assistant messages and tool calls/results
        return ChatBubble(
          content: message.content,
          isUser: false,
          timestamp: message.createdAt,
          contentType: message.contentType,
        );
      },
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
