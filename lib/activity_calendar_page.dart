import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'activity_session.dart';
import 'activity_status_page.dart';
import 'food_log_page.dart';

class ActivityCalendarPage extends StatefulWidget {
  const ActivityCalendarPage(
      {super.key, required this.sessions, this.userName, this.patientUid, this.initialTab = 0});

  final List<ActivitySession> sessions;
  final String? userName;
  final String? patientUid;
  final int initialTab;

  @override
  State<ActivityCalendarPage> createState() => _ActivityCalendarPageState();
}

class _ActivityCalendarPageState extends State<ActivityCalendarPage>
    with SingleTickerProviderStateMixin {
  late DateTime _selectedDate;
  late TabController _tabController;

  String get _viewUid =>
      widget.patientUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> get _last7Days {
    final today = DateTime.now();
    return List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    });
  }

  List<ActivitySession> _sessionsForDay(DateTime day) =>
      widget.sessions.where((s) => _isSameDate(s.completedAt, day)).toList();

  double get _totalKm => _last7Days.fold(
      0.0,
      (sum, d) =>
          sum + _sessionsForDay(d).fold(0.0, (s, a) => s + a.distanceKm));

  int get _totalWorkouts =>
      _last7Days.fold(0, (sum, d) => sum + _sessionsForDay(d).length);

  double get _totalCalories => _last7Days.fold(
      0.0,
      (sum, d) =>
          sum + _sessionsForDay(d).fold(0.0, (s, a) => s + a.calories));

  int get _dayStreak {
    int streak = 0;
    final today = DateTime.now();
    for (int i = 0; i < 7; i++) {
      final d = today.subtract(Duration(days: i));
      final day = DateTime(d.year, d.month, d.day);
      if (_sessionsForDay(day).isNotEmpty) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  String _labelForType(String type) {
    switch (type.toLowerCase()) {
      case 'running': return 'Evening Run';
      case 'cycling': return 'Evening Cycling';
      default: return 'Evening Walk';
    }
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _weekdayLabel(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - 1) % 7];
  }

  @override
  Widget build(BuildContext context) {
    final days = _last7Days;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F13),
        title: Text(
          widget.userName != null
              ? '${widget.userName}\'s Activity'
              : 'Activity',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF6200),
          labelColor: const Color(0xFFFF6200),
          unselectedLabelColor: const Color(0xFF8FA0BA),
          tabs: const [
            Tab(icon: Icon(Icons.directions_run), text: 'Activity'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Food Log'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Activity Tab ──────────────────────────────────────────────
          _buildActivityTab(days),

          // ── Food Log Tab ──────────────────────────────────────────────
          _buildFoodLogTab(),
        ],
      ),
    );
  }

  Widget _buildActivityTab(List<DateTime> days) {
    final daySessions = _sessionsForDay(_selectedDate);
    final hasSession = daySessions.isNotEmpty;
    final displaySession = hasSession ? daySessions.first : null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 7-day stat cards
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                _StatBox(label: 'Total KM', value: _totalKm.toStringAsFixed(1)),
                const SizedBox(width: 10),
                _StatBox(label: 'Workouts', value: '$_totalWorkouts'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                _StatBox(label: 'Calories', value: _totalCalories.toStringAsFixed(0)),
                const SizedBox(width: 10),
                _StatBox(label: 'Day Streak', value: '$_dayStreak 🔥'),
              ],
            ),
          ),

          // Calendar strip
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                const Text('Last 7 Days',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                  style: const TextStyle(
                      color: Color(0xFFAAB3C3), fontSize: 14),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 90,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final day = days[i];
                final selected = _isSameDate(day, _selectedDate);
                final hasActivity = _sessionsForDay(day).isNotEmpty;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = day),
                  child: Container(
                    width: 64,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFFF6200)
                          : const Color(0xFF141922),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFFF6200)
                            : const Color(0xFF2A3342),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_weekdayLabel(day.weekday),
                            style: TextStyle(
                                color: selected
                                    ? Colors.white70
                                    : const Color(0xFFAAB3C3),
                                fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('${day.day}',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                        const SizedBox(height: 4),
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasActivity
                                ? (selected
                                    ? Colors.white
                                    : const Color(0xFFFF6200))
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 14),

          // Activity detail
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1218),
                borderRadius: BorderRadius.circular(16),
              ),
              child: hasSession
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _labelForType(displaySession!.activityType),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _Metric(
                                label: 'Distance',
                                value:
                                    '${displaySession.distanceKm.toStringAsFixed(2)} km'),
                            _Metric(
                                label: 'Time',
                                value: displaySession.duration),
                            _Metric(
                                label: 'Calories',
                                value:
                                    '${displaySession.calories.toStringAsFixed(0)} kcal'),
                          ],
                        ),
                        if (daySessions.length > 1) ...[
                          const SizedBox(height: 8),
                          Text(
                            '+${daySessions.length - 1} more session(s)',
                            style: const TextStyle(
                                color: Color(0xFFAAB3C3), fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ActivityStatusPage(
                                title: _labelForType(
                                    displaySession.activityType),
                                distanceKm: displaySession.distanceKm,
                                movingTime: displaySession.duration,
                                avgSpeedKmh: displaySession.avgSpeedKmh,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Open Route View'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6200),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No activity on this day',
                            style: TextStyle(
                                color: Color(0xFFAAB3C3), fontSize: 16)),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFoodLogTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day selector
          const Text('Select Day',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _last7Days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final day = _last7Days[i];
                final selected = _isSameDate(day, _selectedDate);
                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = day),
                  child: Container(
                    width: 64,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF141922),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF2A3342),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_weekdayLabel(day.weekday),
                            style: TextStyle(
                                color: selected
                                    ? Colors.white70
                                    : const Color(0xFFAAB3C3),
                                fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('${day.day}',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                        const SizedBox(height: 4),
                        const Text('🥗', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Food history for selected day
          DailyFoodHistory(
            uid: _viewUid,
            dayKey: _dayKey(_selectedDate),
            date: _selectedDate,
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF141922),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A3342)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFFAAB3C3), fontSize: 13)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
