import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../models/schedule.dart';
import '../../providers/schedule_provider.dart';

class SchedulesTab extends ConsumerStatefulWidget {
  const SchedulesTab({super.key});

  @override
  ConsumerState<SchedulesTab> createState() => _SchedulesTabState();
}

class _SchedulesTabState extends ConsumerState<SchedulesTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(scheduleListProvider.notifier).loadSchedules());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scheduleListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopRow(onRefresh: () => ref.read(scheduleListProvider.notifier).loadSchedules()),
          _TabTitle(isDark: isDark),
          _SearchBar(isDark: isDark),
          const SizedBox(height: 8),
          Expanded(child: _buildList(state, isDark)),
        ],
      ),
    );
  }

  Widget _buildList(ScheduleListState state, bool isDark) {
    if (state.isLoading && state.schedules.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.schedules.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 64,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No scheduled calls',
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.grey.shade600 : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask a bot to schedule a call for you',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade700 : Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    final upcoming = state.schedules.where((s) => s.status == 'upcoming').toList();
    final past = state.schedules.where((s) => s.status != 'upcoming').toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(scheduleListProvider.notifier).loadSchedules(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (upcoming.isNotEmpty) ...[
            _SectionHeader(title: 'Upcoming', isDark: isDark),
            ...upcoming.map((s) => _ScheduleTile(
                  schedule: s,
                  isDark: isDark,
                  onDelete: () => _confirmDelete(s),
                  onTap: () => context.push(
                    '/chat/${s.chatId}',
                    extra: {'botName': s.botName, 'botAvatar': s.botAvatar},
                  ),
                )),
          ],
          if (past.isNotEmpty) ...[
            _SectionHeader(title: 'Past', isDark: isDark),
            ...past.map((s) => _ScheduleTile(
                  schedule: s,
                  isDark: isDark,
                  onDelete: () => _confirmDelete(s),
                  onTap: () => context.push(
                    '/chat/${s.chatId}',
                    extra: {'botName': s.botName, 'botAvatar': s.botAvatar},
                  ),
                )),
          ],
        ],
      ),
    );
  }

  void _confirmDelete(Schedule schedule) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cancel schedule?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '"${schedule.message}" with ${schedule.botName}',
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Keep',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(scheduleListProvider.notifier).deleteSchedule(schedule.id);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel it'),
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
}

class _TopRow extends StatelessWidget {
  final VoidCallback onRefresh;
  const _TopRow({required this.onRefresh});

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
            icon: const Icon(Icons.refresh, size: 22),
            onPressed: onRefresh,
          ),
          const SizedBox(width: 2),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppTheme.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.schedule, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

class _TabTitle extends StatelessWidget {
  final bool isDark;
  const _TabTitle({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Text(
        'Schedules',
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
  const _SearchBar({required this.isDark});

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
              'Search schedules',
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.tealGreen : AppTheme.primaryGreen,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  final Schedule schedule;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _ScheduleTile({
    required this.schedule,
    required this.isDark,
    required this.onDelete,
    required this.onTap,
  });

  Color _statusColor() {
    switch (schedule.status) {
      case 'upcoming':
        return AppTheme.lightGreen;
      case 'completed':
        return Colors.grey;
      case 'missed':
        return Colors.red.shade400;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon() {
    switch (schedule.status) {
      case 'upcoming':
        return Icons.schedule;
      case 'completed':
        return Icons.check_circle_outline;
      case 'missed':
        return Icons.phone_missed_outlined;
      default:
        return Icons.schedule;
    }
  }

  String _formatTime() {
    final now = DateTime.now();
    final diff = schedule.scheduledFor.difference(now);
    final fmt = DateFormat('h:mm a');
    final dateFmt = DateFormat('d MMM');

    if (diff.inDays == 0 && schedule.scheduledFor.day == now.day) {
      return 'Today, ${fmt.format(schedule.scheduledFor)}';
    } else if (diff.inDays == 1 ||
        (diff.inDays == 0 && schedule.scheduledFor.day == now.day + 1)) {
      return 'Tomorrow, ${fmt.format(schedule.scheduledFor)}';
    } else if (diff.inDays == -1 ||
        (diff.inDays == 0 && schedule.scheduledFor.day == now.day - 1)) {
      return 'Yesterday, ${fmt.format(schedule.scheduledFor)}';
    }
    return '${dateFmt.format(schedule.scheduledFor)}, ${fmt.format(schedule.scheduledFor)}';
  }

  String? _resolveAvatarUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final normalized = url.startsWith('/') ? url : '/$url';
    return '${AppConstants.baseUrl}$normalized';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();

    return InkWell(
      onTap: onTap,
      onLongPress: schedule.status == 'upcoming' ? onDelete : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade100,
              backgroundImage: _resolveAvatarUrl(schedule.botAvatar) != null
                  ? NetworkImage(_resolveAvatarUrl(schedule.botAvatar)!)
                  : null,
              child: schedule.botAvatar == null || schedule.botAvatar!.isEmpty
                  ? Icon(Icons.smart_toy, color: isDark ? Colors.grey : Colors.grey.shade500, size: 24)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          schedule.botName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(),
                        style: TextStyle(
                          fontSize: 12,
                          color: schedule.status == 'upcoming'
                              ? AppTheme.lightGreen
                              : (isDark ? Colors.grey.shade600 : Colors.grey),
                          fontWeight: schedule.status == 'upcoming'
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(_statusIcon(), size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          schedule.message,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
