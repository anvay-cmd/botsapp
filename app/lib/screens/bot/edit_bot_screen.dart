import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../models/bot.dart';
import '../../models/integration.dart';
import '../../providers/bot_provider.dart';
import '../home/integrations_tab.dart';

class EditBotScreen extends ConsumerStatefulWidget {
  final Bot bot;

  const EditBotScreen({super.key, required this.bot});

  @override
  ConsumerState<EditBotScreen> createState() => _EditBotScreenState();
}

class _EditBotScreenState extends ConsumerState<EditBotScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _systemPromptController;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isGeneratingImage = false;
  final _imagePromptController = TextEditingController();
  String? _avatarUrl;
  late String _voiceName;
  late int _proactiveMinutes;
  late Map<String, List<String>> _selectedTools;

  static const List<Map<String, dynamic>> _proactiveOptions = [
    {'label': 'Never', 'minutes': 0},
    {'label': '1 min', 'minutes': 1},
    {'label': '5 min', 'minutes': 5},
    {'label': '15 min', 'minutes': 15},
    {'label': '30 min', 'minutes': 30},
    {'label': '1 hour', 'minutes': 60},
    {'label': '3 hours', 'minutes': 180},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.bot.name);
    _systemPromptController =
        TextEditingController(text: widget.bot.systemPrompt);
    _avatarUrl = widget.bot.avatarUrl;
    _voiceName = widget.bot.voiceName;
    _proactiveMinutes = widget.bot.proactiveMinutes ?? 0;

    // Initialize selected tools from bot's integrations_config
    _selectedTools = {};
    if (widget.bot.integrationsConfig != null) {
      widget.bot.integrationsConfig!.forEach((key, value) {
        if (value is List) {
          _selectedTools[key] = List<String>.from(value);
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _systemPromptController.dispose();
    _imagePromptController.dispose();
    super.dispose();
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
            expandedHeight: 200,
            pinned: true,
            backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primaryGreen,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (!widget.bot.isDefault)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _isDeleting ? null : _confirmDelete,
                ),
            ],
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
                        GestureDetector(
                          onTap: _isGeneratingImage ? null : _showAvatarOptions,
                          child: Stack(
                            children: [
                              _buildAvatar(),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppTheme.lightGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? AppTheme.darkBackground : AppTheme.primaryGreen,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              ),
                              if (_isGeneratingImage)
                                const Positioned.fill(
                                  child: CircleAvatar(
                                    backgroundColor: Colors.black38,
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _nameController.text.isEmpty ? 'Bot' : _nameController.text,
                          style: const TextStyle(
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
                          ),
                          onChanged: (_) => setState(() {}),
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
                        label: 'System Prompt',
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
                            hintText: 'Custom instructions for this bot...',
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
                  const SizedBox(height: 24),

                  _SectionCard(
                    isDark: isDark,
                    cardColor: cardColor,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome_outlined,
                                size: 20, color: AppTheme.tealGreen),
                            const SizedBox(width: 14),
                            Text(
                              'Proactive message frequency',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 34),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _proactiveOptions.map((opt) {
                            final minutes = opt['minutes'] as int;
                            final label = opt['label'] as String;
                            final selected = _proactiveMinutes == minutes;
                            return ChoiceChip(
                              label: Text(label),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _proactiveMinutes = minutes),
                              selectedColor:
                                  AppTheme.tealGreen.withValues(alpha: 0.18),
                              side: BorderSide(
                                color: selected
                                    ? AppTheme.tealGreen
                                    : Colors.transparent,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildIntegrationsSection(isDark, cardColor, subtleText),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveBot,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.lightGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _isSaving ? 'Saving...' : 'Save Changes',
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

  Widget _buildAvatar() {
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          _avatarUrl!.startsWith('http')
              ? _avatarUrl!
              : '${AppConstants.baseUrl}$_avatarUrl',
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholderAvatar(),
        ),
      );
    }
    return _placeholderAvatar();
  }

  Widget _placeholderAvatar() {
    return CircleAvatar(
      radius: 44,
      backgroundColor: Colors.white.withValues(alpha: 0.2),
      child: Text(
        widget.bot.name[0].toUpperCase(),
        style: const TextStyle(
          fontSize: 36,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _imagePromptController,
                      decoration: InputDecoration(
                        hintText: 'Describe avatar look...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _generateAvatar();
                    },
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Generate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.lightGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntegrationsSection(bool isDark, Color cardColor, Color subtleText) {
    final integrationsAsync = ref.watch(integrationsProvider);

    return integrationsAsync.when(
      data: (integrations) {
        final connectedIntegrations = integrations.where((i) => i.isConnected).toList();
        if (connectedIntegrations.isEmpty) {
          return const SizedBox.shrink();
        }

        return _SectionCard(
          isDark: isDark,
          cardColor: cardColor,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.extension_outlined,
                      size: 20, color: AppTheme.tealGreen),
                  const SizedBox(width: 14),
                  Text(
                    'Enabled Tools',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            ...connectedIntegrations.map((integration) {
              return _buildIntegrationTools(integration, isDark);
            }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildIntegrationTools(IntegrationInfo integration, bool isDark) {
    final tools = _getToolsForIntegration(integration.provider);
    final selectedForProvider = _selectedTools[integration.provider] ?? [];

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            integration.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tools.map((tool) {
              final isSelected = selectedForProvider.contains(tool['id']);
              return FilterChip(
                label: Text(tool['label']!),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedTools[integration.provider] = [
                        ...selectedForProvider,
                        tool['id']!
                      ];
                    } else {
                      _selectedTools[integration.provider] = selectedForProvider
                          .where((t) => t != tool['id'])
                          .toList();
                    }
                  });
                },
                selectedColor: AppTheme.tealGreen.withValues(alpha: 0.18),
                checkmarkColor: AppTheme.tealGreen,
                side: BorderSide(
                  color: isSelected ? AppTheme.tealGreen : Colors.transparent,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> _getToolsForIntegration(String provider) {
    switch (provider) {
      case 'web_search':
        return [
          {'id': 'web_search', 'label': 'Web Search'},
          {'id': 'scrape_url', 'label': 'Scrape URL'},
        ];
      case 'gmail':
        return [
          {'id': 'gmail_list_emails', 'label': 'List Emails'},
          {'id': 'gmail_search_emails', 'label': 'Search Emails'},
          {'id': 'gmail_send_email', 'label': 'Send Email'},
          {'id': 'gmail_read_email', 'label': 'Read Email'},
        ];
      default:
        return [];
    }
  }

  Future<void> _saveBot() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bot name cannot be empty')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final updated = await ref.read(botListProvider.notifier).updateBot(
          botId: widget.bot.id,
          name: name,
          systemPrompt: _systemPromptController.text.trim(),
          voiceName: _voiceName,
          proactiveMinutes: _proactiveMinutes,
          integrationsConfig: _selectedTools,
        );

    if (updated != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bot updated')),
      );
      context.pop(updated);
    } else {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save')),
        );
      }
    }
  }

  Future<void> _generateAvatar() async {
    final prompt = _imagePromptController.text.isNotEmpty
        ? _imagePromptController.text
        : _nameController.text;
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name or image prompt first')),
      );
      return;
    }
    setState(() => _isGeneratingImage = true);
    final updated = await ref
        .read(botListProvider.notifier)
        .generateImage(widget.bot.id, prompt);
    if (mounted) {
      setState(() {
        _isGeneratingImage = false;
        if (updated != null && updated.avatarUrl != null) {
          _avatarUrl = updated.avatarUrl;
        }
      });
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image generation failed')),
        );
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bot'),
        content: Text(
            'Are you sure you want to delete "${widget.bot.name}"? '
            'This will also delete all chats with this bot.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteBot();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBot() async {
    setState(() => _isDeleting = true);
    await ref.read(botListProvider.notifier).deleteBot(widget.bot.id);
    if (mounted) context.go('/');
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
