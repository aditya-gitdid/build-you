import 'package:flutter/material.dart';

import 'activity_session.dart';
import 'activity_status_page.dart';

class ActivityCalendarPage extends StatefulWidget {
  const ActivityCalendarPage({super.key, required this.sessions, this.userName});

  final List<ActivitySession> sessions;
  final String? userName;

  @override
  State<ActivityCalendarPage> createState() => _ActivityCalendarPageState();
}

class _ActivityCalendarPageState extends State<ActivityCalendarPage> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> get _last7Days {
    final today = DateTime.now();
    return List.generate(
      7,
      (i) {
        final d = today.subtract(Duration(days: 6 - i));
        return DateTime(d.year, d.month, d.day);
      },
    );
  }

  List<ActivitySession> _sessionsForDay(DateTime day) =>
      widget.sessions.where((s) => _isSameDate(s.completedAt, day)).toList();

  // 7-day aggregates
  double get _totalKm => _last7Days.fold(
        0.0,
        (sum, d) => sum + _sessionsForDay(d).fold(0.0, (s, a) => s + a.distanceKm),
      );

  int get _totalWorkouts =>
      _last7Days.fold(0, (sum, d) => sum + _sessionsForDay(d).length);

  double get _totalCalories => _last7Days.fold(
        0.0,
        (sum, d) => sum + _sessionsForDay(d).fold(0.0, (s, a) => s + a.calories),
      );

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
      case 'running':
        return 'Evening Run';
      case 'cycling':
        return 'Evening Cycling';
      default:
        return 'Evening Walk';
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _last7Days;
    final daySessions = _sessionsForDay(_selectedDate);
    final hasSession = daySessions.isNotEmpty;
    final displaySession = hasSession ? daySessions.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F13),
        title: Text(
          widget.userName != null ? '${widget.userName}\'s Activity' : 'Activity',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 28),
        ),
      ),
      body: SingleChildScrollView(
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

            // Calendar strip label
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(
                children: [
                  const Text(
                    'Last 7 Days',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: const TextStyle(color: Color(0xFFAAB3C3), fontSize: 14),
                  ),
                ],
              ),
            ),

            // Calendar day strip
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
                        color: selected ? const Color(0xFFFF6200) : const Color(0xFF141922),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? const Color(0xFFFF6200) : const Color(0xFF2A3342),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekdayLabel(day.weekday),
                            style: TextStyle(
                              color: selected ? Colors.white70 : const Color(0xFFAAB3C3),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasActivity
                                  ? (selected ? Colors.white : const Color(0xFFFF6200))
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

            // Selected day detail
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
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _Metric(
                                label: 'Distance',
                                value: '${displaySession.distanceKm.toStringAsFixed(2)} km',
                              ),
                              _Metric(label: 'Time', value: displaySession.duration),
                              _Metric(
                                label: 'Calories',
                                value: '${displaySession.calories.toStringAsFixed(0)} kcal',
                              ),
                            ],
                          ),
                          if (daySessions.length > 1) ...[
                            const SizedBox(height: 8),
                            Text(
                              '+${daySessions.length - 1} more session(s) this day',
                              style: const TextStyle(color: Color(0xFFAAB3C3), fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ActivityStatusPage(
                                    title: _labelForType(displaySession.activityType),
                                    distanceKm: displaySession.distanceKm,
                                    movingTime: displaySession.duration,
                                    avgSpeedKmh: displaySession.avgSpeedKmh,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.visibility),
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
                          child: Text(
                            'No activity on this day',
                            style: TextStyle(color: Color(0xFFAAB3C3), fontSize: 16),
                          ),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 14),

            // Route map visual
            Container(
              height: 220,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF181F2B),
              ),
              child: CustomPaint(painter: _MiniRoutePainter()),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _weekdayLabel(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - 1) % 7];
  }
}

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
            Text(label, style: const TextStyle(color: Color(0xFFAAB3C3), fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
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
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MiniRoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roads = Paint()
      ..color = const Color(0xFF3A4358)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < 10; i++) {
      final y = size.height * (i / 9);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 20), roads);
    }

    final route = Paint()
      ..color = const Color(0xFFFF6200)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.20, size.height * 0.20)
      ..lineTo(size.width * 0.45, size.height * 0.20)
      ..lineTo(size.width * 0.70, size.height * 0.76)
      ..lineTo(size.width * 0.54, size.height * 0.84);
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
