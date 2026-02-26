import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule.dart';
import '../services/api_service.dart';

class ScheduleListState {
  final List<Schedule> schedules;
  final bool isLoading;
  final String? error;

  const ScheduleListState({
    this.schedules = const [],
    this.isLoading = false,
    this.error,
  });

  ScheduleListState copyWith({
    List<Schedule>? schedules,
    bool? isLoading,
    String? error,
  }) =>
      ScheduleListState(
        schedules: schedules ?? this.schedules,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class ScheduleListNotifier extends StateNotifier<ScheduleListState> {
  ScheduleListNotifier() : super(const ScheduleListState());

  final _api = ApiService();

  Future<void> loadSchedules() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.get('/schedules');
      final list = (response.data as List)
          .map((j) => Schedule.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(schedules: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deleteSchedule(String id) async {
    try {
      await _api.delete('/schedules/$id');
      state = state.copyWith(
        schedules: state.schedules.where((s) => s.id != id).toList(),
      );
    } catch (_) {}
  }
}

final scheduleListProvider =
    StateNotifierProvider<ScheduleListNotifier, ScheduleListState>(
  (ref) => ScheduleListNotifier(),
);
