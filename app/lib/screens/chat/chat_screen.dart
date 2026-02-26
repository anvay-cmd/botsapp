import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/bot_provider.dart';
import '../../providers/chat_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatMessagesProvider(widget.chatId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(chatMessagesProvider(widget.chatId), (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          prev?.streamingContent != next.streamingContent) {
        _scrollToBottom();
      }
    });

    return PopScope(
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
              child: chatState.isLoading && chatState.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      itemCount: chatState.messages.length +
                          (chatState.isBotTyping &&
                                  chatState.streamingContent.isNotEmpty
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        if (index == chatState.messages.length) {
                          return ChatBubble(
                            content: chatState.streamingContent,
                            isUser: false,
                            timestamp: DateTime.now(),
                            isStreaming: true,
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
    super.dispose();
  }
}
