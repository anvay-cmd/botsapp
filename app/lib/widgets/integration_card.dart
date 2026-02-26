import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/integration.dart';

class IntegrationCard extends StatelessWidget {
  final IntegrationInfo integration;
  final VoidCallback onToggle;

  const IntegrationCard({
    super.key,
    required this.integration,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? AppTheme.darkSurface : Colors.white,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: integration.isConnected
                          ? AppTheme.tealGreen.withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getIcon(),
                      color: integration.isConnected
                          ? AppTheme.tealGreen
                          : Colors.grey,
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: integration.isConnected
                          ? AppTheme.lightGreen
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                integration.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                integration.description,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
