import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../models/integration.dart';
import '../../services/api_service.dart';

final integrationsProvider =
    FutureProvider<List<IntegrationInfo>>((ref) async {
  try {
    final response = await ApiService().get('/integrations');
    return (response.data as List)
        .map((j) => IntegrationInfo.fromJson(j))
        .toList();
  } catch (e) {
    return [];
  }
});

class IntegrationsTab extends ConsumerWidget {
  const IntegrationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final integrationsAsync = ref.watch(integrationsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return integrationsAsync.when(
      loading: () => SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TopRow(),
            _TabTitle(title: 'Integrations', isDark: isDark),
            _SearchBar(
              isDark: isDark,
              placeholder: 'Search integrations',
            ),
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (integrations) {
        return SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TopRow(),
              _TabTitle(title: 'Integrations', isDark: isDark),
              _SearchBar(
                isDark: isDark,
                placeholder: 'Search integrations',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: integrations.isEmpty
                    ? _EmptyIntegrations(isDark: isDark)
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(integrationsProvider);
                        },
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: integrations.length,
                          itemBuilder: (context, index) {
                            final integration = integrations[index];
                            return _IntegrationTile(
                              integration: integration,
                              isDark: isDark,
                              onToggle: () async {
                                final api = ApiService();
                                try {
                                  if (integration.isConnected) {
                                    await api.delete(
                                        '/integrations/${integration.provider}');
                                  } else {
                                    await api.post(
                                        '/integrations/${integration.provider}/connect');
                                  }
                                  ref.invalidate(integrationsProvider);
                                } catch (_) {}
                              },
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 26),
            onPressed: () {},
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.sync, size: 22),
            onPressed: () {},
          ),
          const SizedBox(width: 2),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppTheme.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.extension, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

class _TabTitle extends StatelessWidget {
  final String title;
  final bool isDark;
  const _TabTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final bool isDark;
  final String placeholder;
  const _SearchBar({required this.isDark, required this.placeholder});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
              placeholder,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.grey : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyIntegrations extends StatelessWidget {
  final bool isDark;
  const _EmptyIntegrations({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.extension_outlined,
            size: 64,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No integrations available',
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.grey.shade600 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegrationTile extends StatelessWidget {
  final IntegrationInfo integration;
  final bool isDark;
  final VoidCallback onToggle;

  const _IntegrationTile({
    required this.integration,
    required this.isDark,
    required this.onToggle,
  });

  IconData _getIcon() {
    switch (integration.icon) {
      case 'search':
        return Icons.search;
      case 'calendar_today':
        return Icons.calendar_today;
      case 'email':
        return Icons.email;
      case 'music_note':
        return Icons.music_note;
      case 'code':
        return Icons.code;
      case 'folder':
        return Icons.folder;
      case 'newspaper':
        return Icons.newspaper;
      default:
        return Icons.extension;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor:
                  integration.isConnected ? AppTheme.tealGreen : Colors.grey.shade500,
              child: Icon(_getIcon(), color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    integration.name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    integration.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: integration.isConnected
                    ? AppTheme.lightGreen.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                integration.isConnected ? 'Connected' : 'Connect',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: integration.isConnected ? AppTheme.lightGreen : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
