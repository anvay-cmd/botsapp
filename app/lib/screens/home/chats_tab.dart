import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../providers/bot_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/chat_tile.dart';

class ChatsTab extends ConsumerStatefulWidget {
  const ChatsTab({super.key});

  @override
  ConsumerState<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<ChatsTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(chatListProvider.notifier).loadChats());
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top action row
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 26),
                  onPressed: () {},
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined, size: 24),
                  onPressed: () {},
                ),
                const SizedBox(width: 2),
                _NewChatButton(
                  onTap: () => context.push('/create-bot'),
                ),
              ],
            ),
          ),

          // "Chats" title
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: Text(
              'Chats',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () {},
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 20,
                      color: isDark ? Colors.grey : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Search bots or messages',
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.grey : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Chat list
          Expanded(
            child: _buildChatList(chatState, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(ChatListState chatState, bool isDark) {
    if (chatState.isLoading && chatState.chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (chatState.chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No chats yet',
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.grey.shade600 : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create a new bot',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade700 : Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(chatListProvider.notifier).loadChats(),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: chatState.chats.length,
        itemBuilder: (context, index) {
          final chat = chatState.chats[index];
          return ChatTile(
            chat: chat,
            onTap: () => context.push(
              '/chat/${chat.id}',
              extra: {
                'botName': chat.botName ?? 'Chat',
                'botAvatar': chat.botAvatar,
                'botId': chat.botId,
              },
            ),
            onMute: () => ref
                .read(chatListProvider.notifier)
                .muteChat(chat.id, !chat.isMuted),
            onDelete: () async {
              await ref
                  .read(botListProvider.notifier)
                  .deleteBot(chat.botId);
              ref.read(chatListProvider.notifier).loadChats();
            },
          );
        },
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NewChatButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: AppTheme.lightGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 22),
      ),
    );
  }
}

