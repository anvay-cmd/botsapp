import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../models/schedule.dart';
import '../../providers/schedule_provider.dart';
import '../../services/gps_service.dart';

// Activity type enum
enum ActivityType { all, voiceCalls, fences, webhooks }

// Current tab provider
final activityTabProvider = StateProvider<ActivityType>((ref) => ActivityType.all);

class ActivitiesTab extends ConsumerStatefulWidget {
  const ActivitiesTab({super.key});

  @override
  ConsumerState<ActivitiesTab> createState() => _ActivitiesTabState();
}

class _ActivitiesTabState extends ConsumerState<ActivitiesTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GPSService _gpsService = GPSService();
  List<Map<String, dynamic>> _geofences = [];
  bool _loadingFences = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    Future.microtask(() {
      ref.read(scheduleListProvider.notifier).loadSchedules();
      _loadGeofences();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGeofences() async {
    setState(() => _loadingFences = true);
    final fences = await _gpsService.getGeofences();
    setState(() {
      _geofences = fences;
      _loadingFences = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopRow(onRefresh: () {
            ref.read(scheduleListProvider.notifier).loadSchedules();
            _loadGeofences();
          }),
          _TabTitle(isDark: isDark),
          _SearchBar(isDark: isDark),
          const SizedBox(height: 12),
          _TwitterStyleTabs(
            tabController: _tabController,
            isDark: isDark,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AllActivitiesView(isDark: isDark, onRefresh: _loadGeofences, geofences: _geofences),
                _VoiceCallsView(isDark: isDark),
                _GeofencesView(isDark: isDark, geofences: _geofences, loading: _loadingFences, onRefresh: _loadGeofences),
                _WebhooksView(isDark: isDark),
              ],
            ),
          ),
        ],
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
            child: const Icon(Icons.notifications_active, color: Colors.white, size: 20),
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
        'Activities',
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
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: isDark ? Colors.grey : Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              'Search activities',
              style: TextStyle(fontSize: 15, color: isDark ? Colors.grey : Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _TwitterStyleTabs extends StatelessWidget {
  final TabController tabController;
  final bool isDark;

  const _TwitterStyleTabs({
    required this.tabController,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100,
            width: 0.5,
          ),
        ),
      ),
      child: TabBar(
        controller: tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(
            width: 3,
            color: isDark ? AppTheme.tealGreen : AppTheme.primaryGreen,
          ),
          insets: const EdgeInsets.symmetric(horizontal: 0),
        ),
        labelColor: isDark ? Colors.white : Colors.black,
        unselectedLabelColor: isDark ? Colors.grey.shade600 : Colors.grey.shade600,
        labelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.normal,
          letterSpacing: 0.2,
        ),
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Voice Calls'),
          Tab(text: 'Geofences'),
          Tab(text: 'Webhooks'),
        ],
      ),
    );
  }
}

// All Activities View
class _AllActivitiesView extends ConsumerWidget {
  final bool isDark;
  final VoidCallback onRefresh;
  final List<Map<String, dynamic>> geofences;

  const _AllActivitiesView({
    required this.isDark,
    required this.onRefresh,
    required this.geofences,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scheduleListProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(scheduleListProvider.notifier).loadSchedules();
        onRefresh();
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          if (state.schedules.isNotEmpty) ...[
            _SectionHeader(title: 'Voice Calls', isDark: isDark),
            ...state.schedules.take(3).map((s) => _ScheduleTile(schedule: s, isDark: isDark)),
          ],
          if (geofences.isNotEmpty) ...[
            _SectionHeader(title: 'Geofences', isDark: isDark),
            ...geofences.take(3).map((f) => _GeofenceTile(fence: f, isDark: isDark)),
          ],
          if (state.schedules.isEmpty && geofences.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'No activities yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Voice Calls View
class _VoiceCallsView extends ConsumerWidget {
  final bool isDark;

  const _VoiceCallsView({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scheduleListProvider);

    if (state.isLoading && state.schedules.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.schedules.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone_outlined, size: 64, color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No scheduled calls',
              style: TextStyle(fontSize: 18, color: isDark ? Colors.grey.shade600 : Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask a bot to schedule a call for you',
              style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade700 : Colors.grey),
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
        padding: const EdgeInsets.only(top: 8),
        children: [
          if (upcoming.isNotEmpty) ...[
            _SectionHeader(title: 'Upcoming', isDark: isDark),
            ...upcoming.map((s) => _ScheduleTile(schedule: s, isDark: isDark)),
          ],
          if (past.isNotEmpty) ...[
            _SectionHeader(title: 'Past', isDark: isDark),
            ...past.map((s) => _ScheduleTile(schedule: s, isDark: isDark)),
          ],
        ],
      ),
    );
  }
}

// Geofences View
class _GeofencesView extends StatelessWidget {
  final bool isDark;
  final List<Map<String, dynamic>> geofences;
  final bool loading;
  final VoidCallback onRefresh;

  const _GeofencesView({
    required this.isDark,
    required this.geofences,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && geofences.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (geofences.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fence_outlined, size: 64, color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No geofences',
              style: TextStyle(fontSize: 18, color: isDark ? Colors.grey.shade600 : Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Create geofences in GPS settings',
              style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade700 : Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: geofences.map((f) => _GeofenceTile(fence: f, isDark: isDark)).toList(),
      ),
    );
  }
}

// Webhooks View
class _WebhooksView extends StatelessWidget {
  final bool isDark;

  const _WebhooksView({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.webhook_outlined, size: 64, color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No webhooks configured',
            style: TextStyle(fontSize: 18, color: isDark ? Colors.grey.shade600 : Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade700 : Colors.grey),
          ),
        ],
      ),
    );
  }
}

// Section Header Widget
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

// Schedule Tile Widget (Voice Calls)
class _ScheduleTile extends ConsumerWidget {
  final Schedule schedule;
  final bool isDark;

  const _ScheduleTile({required this.schedule, required this.isDark});

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
        return Icons.phone_outlined;
      case 'completed':
        return Icons.check_circle_outline;
      case 'missed':
        return Icons.phone_missed_outlined;
      default:
        return Icons.phone_outlined;
    }
  }

  String _formatTime() {
    final now = DateTime.now();
    final diff = schedule.scheduledFor.difference(now);
    final fmt = DateFormat('h:mm a');
    final dateFmt = DateFormat('d MMM');

    if (diff.inDays == 0 && schedule.scheduledFor.day == now.day) {
      return 'Today, ${fmt.format(schedule.scheduledFor)}';
    } else if (diff.inDays == 1 || (diff.inDays == 0 && schedule.scheduledFor.day == now.day + 1)) {
      return 'Tomorrow, ${fmt.format(schedule.scheduledFor)}';
    } else if (diff.inDays == -1 || (diff.inDays == 0 && schedule.scheduledFor.day == now.day - 1)) {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push('/chat/${schedule.chatId}', extra: {'botName': schedule.botName, 'botAvatar': schedule.botAvatar}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100,
              backgroundImage: _resolveAvatarUrl(schedule.botAvatar) != null
                  ? NetworkImage(_resolveAvatarUrl(schedule.botAvatar)!)
                  : null,
              child: schedule.botAvatar == null || schedule.botAvatar!.isEmpty
                  ? Icon(Icons.smart_toy, color: isDark ? Colors.grey : Colors.grey.shade500, size: 22)
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
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(),
                        style: TextStyle(
                          fontSize: 12,
                          color: schedule.status == 'upcoming'
                              ? AppTheme.lightGreen
                              : (isDark ? Colors.grey.shade600 : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(_statusIcon(), size: 13, color: _statusColor()),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          schedule.message,
                          style: TextStyle(
                            fontSize: 13,
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

// Geofence Tile Widget
class _GeofenceTile extends StatelessWidget {
  final Map<String, dynamic> fence;
  final bool isDark;

  const _GeofenceTile({required this.fence, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        // Navigate to GPS settings or show details
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.lightGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.location_on, color: AppTheme.lightGreen, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fence['name'] ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Radius: ${(fence['radius'] ?? 0).toStringAsFixed(0)}m',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}
