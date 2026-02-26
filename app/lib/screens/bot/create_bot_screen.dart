import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/bot_provider.dart';
import '../../providers/chat_provider.dart';

class CreateBotScreen extends ConsumerStatefulWidget {
  const CreateBotScreen({super.key});

  @override
  ConsumerState<CreateBotScreen> createState() => _CreateBotScreenState();
}

class _CreateBotScreenState extends ConsumerState<CreateBotScreen> {
  final _nameController = TextEditingController();
  final _personaController = TextEditingController();
  final _systemPromptController = TextEditingController();
  bool _showAdvanced = false;
  bool _isCreating = false;
  String _voiceName = 'Kore';

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  String _buildSystemPrompt() {
    final base = AppConstants.baseSystemPrompt;
    if (_systemPromptController.text.trim().isNotEmpty) {
      return '$base\n\n${_systemPromptController.text.trim()}';
    }
    final persona = _personaController.text.trim();
    if (persona.isNotEmpty) {
      return '$base\n\nYou have the following persona: $persona. '
          'Stay in character and be helpful, engaging, and conversational.';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.grey.shade50;
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white;
    final subtleText = isDark ? Colors.grey.shade500 : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : surfaceColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primaryGreen,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [AppTheme.darkSurface, AppTheme.darkBackground]
                        : [AppTheme.primaryGreen, AppTheme.tealGreen],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          child: const Icon(
                            Icons.smart_toy,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'New Bot',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionCard(
                    isDark: isDark,
                    cardColor: cardColor,
                    children: [
                      _FieldRow(
                        icon: Icons.smart_toy_outlined,
                        label: 'Name',
                        isDark: isDark,
                        child: TextField(
                          controller: _nameController,
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'e.g., CodeHelper, ChefBot',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _SectionCard(
                    isDark: isDark,
                    cardColor: cardColor,
                    children: [
                      _FieldRow(
                        icon: Icons.psychology_outlined,
                        label: 'Persona',
                        isDark: isDark,
                        child: TextField(
                          controller: _personaController,
                          maxLines: 3,
                          minLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: "Describe the bot's personality and expertise...",
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _SectionCard(
                    isDark: isDark,
                    cardColor: cardColor,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.record_voice_over_outlined,
                                size: 20, color: AppTheme.tealGreen),
                            const SizedBox(width: 14),
                            Text(
                              'Voice',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: _VoiceOption(
                                label: 'Female',
                                icon: Icons.female,
                                selected: _voiceName == 'Kore',
                                isDark: isDark,
                                onTap: () => setState(() => _voiceName = 'Kore'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _VoiceOption(
                                label: 'Male',
                                icon: Icons.male,
                                selected: _voiceName == 'Fenrir' || _voiceName == 'Puck',
                                isDark: isDark,
                                onTap: () => setState(() => _voiceName = 'Fenrir'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _showAdvanced
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: AppTheme.tealGreen,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Advanced Settings',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.tealGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_showAdvanced) ...[
                    _SectionCard(
                      isDark: isDark,
                      cardColor: cardColor,
                      children: [
                        _FieldRow(
                          icon: Icons.terminal,
                          label: 'Custom System Prompt',
                          isDark: isDark,
                          child: TextField(
                            controller: _systemPromptController,
                            maxLines: 5,
                            minLines: 2,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Additional instructions beyond the base prompt...',
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 38, top: 4, bottom: 4),
                          child: Text(
                            'Base: "${AppConstants.baseSystemPrompt}"',
                            style: TextStyle(fontSize: 11, color: subtleText),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _createBot,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.lightGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _isCreating ? 'Creating...' : 'Create Bot',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createBot() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a bot name')),
      );
      return;
    }
    setState(() => _isCreating = true);
    final bot = await ref.read(botListProvider.notifier).createBot(
          name: _nameController.text.trim(),
          systemPrompt: _buildSystemPrompt(),
          voiceName: _voiceName,
        );
    if (bot != null) {
      await ref.read(chatListProvider.notifier).loadChats();
      if (mounted) context.pop();
    } else {
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create bot')),
        );
      }
    }
  }
}

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final Color cardColor;
  final List<Widget> children;

  const _SectionCard({
    required this.isDark,
    required this.cardColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? null
            : Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Widget child;

  const _FieldRow({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.tealGreen),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 34, top: 4),
          child: child,
        ),
      ],
    );
  }
}

class _VoiceOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _VoiceOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.tealGreen.withValues(alpha: 0.12)
              : isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.tealGreen : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: selected ? AppTheme.tealGreen : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppTheme.tealGreen : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
