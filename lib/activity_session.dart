import 'package:cloud_firestore/cloud_firestore.dart';

class ActivitySession {
  const ActivitySession({
    required this.id,
    required this.activityType,
    required this.distanceKm,
    required this.duration,
    required this.avgSpeedKmh,
    required this.steps,
    required this.calories,
    required this.completedAt,
  });

  final String id;
  final String activityType;
  final double distanceKm;
  final String duration;
  final double avgSpeedKmh;
  final int steps;
  final double calories;
  final DateTime completedAt;

  static ActivitySession fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final ts = data['completed_at'];
    return ActivitySession(
      id: id,
      activityType: (data['activity_type'] ?? 'walking').toString(),
      distanceKm: _toDouble(data['distance']),
      duration: (data['duration'] ?? '00:00:00').toString(),
      avgSpeedKmh: _toDouble(data['avg_speed']),
      steps: _toInt(data['steps']),
      calories: _toDouble(data['calories']),
      completedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'activity_type': activityType,
      'distance': distanceKm,
      'duration': duration,
      'avg_speed': avgSpeedKmh,
      'steps': steps,
      'calories': calories,
      'completed_at': Timestamp.fromDate(completedAt),
    };
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}