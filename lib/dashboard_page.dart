
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'activity_calendar_page.dart';
import 'activity_session.dart';
import 'activity_status_page.dart';
import 'chat_page.dart';
import 'events_page.dart';
import 'food_nutrition_page.dart';
import 'direct_chat_page.dart';
import 'profile_view_page.dart';

enum TrackActivityType { running, walking, cycling }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _postController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _friendSearchController = TextEditingController();
  final TextEditingController _eventTitleController = TextEditingController();
  final TextEditingController _eventLocationController = TextEditingController();
  final MapController _mapController = MapController();

  late final AnimationController _introController;

  int _currentTab = 0;
  TrackActivityType _selectedActivity = TrackActivityType.running;
  String _profileName = 'Aditya';
  String _profileEmail = 'aditya@gmail.com';
  String? _selectedImagePath;
  bool _showPastEvents = false;

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isTracking = false;
  bool _isPaused = false;
  bool _gpsAcquired = false;
  String _gpsStatusText = 'GPS not acquired';
  double _distanceKm = 0;
  double _currentSpeedKmh = 0;
  int _steps = 0;
  double _calories = 0;
  Position? _lastPosition;
  LatLng? _currentLatLng;
  final List<LatLng> _routePoints = <LatLng>[];
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activitySubscription;

  double _lastMagnitude = 0;
  bool _stepPending = false;
  static const double _stepThreshold = 11.5;
  static const double _stepLow = 9.5;

  List<ActivitySession> _activitySessions = <ActivitySession>[];
  double _sevenDayKm = 0;
  int _sevenDayWorkouts = 0;
  double _sevenDayCalories = 0;
  int _dayStreak = 0;

  final List<_EventItem> _upcomingEvents = <_EventItem>[
    _EventItem(
      title: 'Sunday Morning Run',
      type: 'Running',
      dateLabel: 'Sunday, Feb 23',
      timeLabel: '7:00 AM',
      locationLabel: 'Central Park, 5K',
      organizer: 'Sarah Miller',
      joinedCount: 24,
      capacity: 30,
      joined: true,
      accent: const Color(0xFFFF7A18),
    ),
    _EventItem(
      title: 'Weekend Trail Walk',
      type: 'Walking',
      dateLabel: 'Saturday, Feb 22',
      timeLabel: '9:00 AM',
      locationLabel: 'Forest Trail, 3.5K',
      organizer: 'Mike Chen',
      joinedCount: 15,
      capacity: 20,
      joined: false,
      accent: const Color(0xFFFFA544),
    ),
  ];

  final List<_PastEventItem> _pastEvents = const <_PastEventItem>[
    _PastEventItem(
      title: '5K Charity Run',
      dateLabel: 'Feb 15, 2026',
      distance: '5K',
      participants: 45,
    ),
    _PastEventItem(
      title: 'Beach Walk',
      dateLabel: 'Feb 10, 2026',
      distance: '4K',
      participants: 18,
    ),
  ];

  final List<String> _friendSuggestions = <String>[
    'Alex Cooper',
    'Nina Patel',
    'Ravi Kumar',
    'Olivia Smith',
    'Liam Johnson',
  ];

  final List<_SocialPost> _posts = <_SocialPost>[
    _SocialPost(
      userName: 'Sarah Miller',
      timeAgo: '2 hours ago',
      caption: 'Completed a 10K run with a strong finish.',
      imageUrl:
          'https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?auto=format&fit=crop&w=1200&q=80',
      likes: 124,
      comments: 18,
      distance: '10.2 km',
      duration: '52 min',
      calories: '642',
    ),
    _SocialPost(
      userName: 'Mike Chen',
      timeAgo: '5 hours ago',
      caption: 'Beautiful morning walk in the park.',
      imageUrl:
          'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=1200&q=80',
      likes: 19,
      comments: 12,
      distance: '3.5 km',
      duration: '45 min',
      calories: '180',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _subscribeToActivities();
    _fetchProfile();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    _accelSubscription?.cancel();
    _activitySubscription?.cancel();
    _introController.dispose();
    _postController.dispose();
    _locationController.dispose();
    _friendSearchController.dispose();
    _eventTitleController.dispose();
    _eventLocationController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _firestore.collection('users').doc(uid).get();
    if (!mounted) return;
    final Map<String, dynamic>? data = doc.data();
    setState(() {
      final String fetchedName = (data?['name'] as String? ?? '').trim();
      final String fetchedEmail =
          (FirebaseAuth.instance.currentUser?.email ?? '').trim();
      if (fetchedName.isNotEmpty) _profileName = fetchedName;
      if (fetchedEmail.isNotEmpty) _profileEmail = fetchedEmail;
    });
  }

  void _subscribeToActivities() {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _activitySubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('activities')
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (!mounted) return;
      final List<ActivitySession> sessions = snapshot.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
        return ActivitySession.fromFirestore(doc.id, doc.data());
      }).toList()
        ..sort((ActivitySession a, ActivitySession b) {
          return b.completedAt.compareTo(a.completedAt);
        });
      setState(() {
        _activitySessions = sessions;
        _recalculateMetrics();
      });
    });
  }

  void _recalculateMetrics() {
    final DateTime now = DateTime.now();
    final DateTime sevenDaysAgo = now.subtract(const Duration(days: 7));
    final List<ActivitySession> recent = _activitySessions.where((ActivitySession s) {
      return s.completedAt.isAfter(sevenDaysAgo);
    }).toList();
    _sevenDayKm = recent.fold(0, (double sum, ActivitySession s) => sum + s.distanceKm);
    _sevenDayWorkouts = recent.length;
    _sevenDayCalories =
        recent.fold(0, (double sum, ActivitySession s) => sum + s.calories);

    int streak = 0;
    for (int i = 0; i < 30; i++) {
      final DateTime day = DateTime(now.year, now.month, now.day - i);
      final bool hasSession = _activitySessions.any((ActivitySession s) {
        return s.completedAt.year == day.year &&
            s.completedAt.month == day.month &&
            s.completedAt.day == day.day;
      });
      if (!hasSession) break;
      streak++;
    }
    _dayStreak = streak;
  }

  double _activityMet() {
    switch (_selectedActivity) {
      case TrackActivityType.running:
        return 9.8;
      case TrackActivityType.walking:
        return 3.8;
      case TrackActivityType.cycling:
        return 7.5;
    }
  }

  double _computeCalories(Duration elapsed) {
    return _activityMet() * 70 * (elapsed.inSeconds / 3600);
  }

  Future<bool> _ensureLocationReady() async {
    final bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
      }
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _startTracking() async {
    if (_isTracking) return;
    final bool ready = await _ensureLocationReady();
    if (!ready) return;
    try {
      final Position initial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      final LatLng start = LatLng(initial.latitude, initial.longitude);
      setState(() {
        _elapsed = Duration.zero;
        _distanceKm = 0;
        _currentSpeedKmh = 0;
        _steps = 0;
        _calories = 0;
        _lastPosition = initial;
        _currentLatLng = start;
        _routePoints
          ..clear()
          ..add(start);
        _isTracking = true;
        _isPaused = false;
        _gpsAcquired = true;
        _gpsStatusText = 'GPS acquired';
      });
      _startSensors();
      _startTimer();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to fetch location right now.')),
      );
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isTracking || _isPaused) return;
      setState(() {
        _elapsed += const Duration(seconds: 1);
        _calories = _computeCalories(_elapsed);
      });
    });
  }

  void _startSensors() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((Position position) {
      if (!mounted || !_isTracking || _isPaused) return;
      final LatLng point = LatLng(position.latitude, position.longitude);
      double extra = 0;
      if (_lastPosition != null) {
        extra = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
      }
      _lastPosition = position;
      setState(() {
        _distanceKm += extra / 1000;
        _currentSpeedKmh = math.max(0, position.speed * 3.6);
        _currentLatLng = point;
        _routePoints.add(point);
        _gpsAcquired = true;
        _gpsStatusText = 'GPS acquired';
        _calories = _computeCalories(_elapsed);
      });
      try {
        _mapController.move(point, 16.2);
      } catch (_) {}
    });

    _accelSubscription?.cancel();
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent e) {
      if (!_isTracking || _isPaused) return;
      final double magnitude = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (_lastMagnitude < _stepThreshold &&
          magnitude >= _stepThreshold &&
          !_stepPending) {
        _stepPending = true;
      } else if (_stepPending && magnitude <= _stepLow) {
        _stepPending = false;
        if (mounted) {
          setState(() {
            _steps++;
          });
        }
      }
      _lastMagnitude = magnitude;
    });
  }
  void _pauseTracking() {
    setState(() {
      _isPaused = true;
      _gpsStatusText = 'Paused';
    });
  }

  Future<void> _resumeTracking() async {
    final bool ready = await _ensureLocationReady();
    if (!ready) return;
    setState(() {
      _isPaused = false;
      _gpsStatusText = _gpsAcquired ? 'GPS acquired' : 'Searching for GPS';
    });
  }

  Future<void> _finishTracking() async {
    final double sessionDistance = _distanceKm;
    final double sessionSpeed = _currentSpeedKmh;
    final Duration sessionTime = _elapsed;
    final int sessionSteps = _steps;
    final double sessionCalories = _calories;
    final TrackActivityType sessionType = _selectedActivity;

    _timer?.cancel();
    _positionSubscription?.cancel();
    _accelSubscription?.cancel();

    setState(() {
      _isTracking = false;
      _isPaused = false;
      _gpsStatusText = _gpsAcquired ? 'GPS acquired' : 'GPS not acquired';
    });

    if (sessionTime.inSeconds == 0) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final ActivitySession session = ActivitySession(
        id: '',
        activityType: sessionType.name,
        distanceKm: sessionDistance,
        duration: _formatDuration(sessionTime),
        avgSpeedKmh: sessionSpeed,
        steps: sessionSteps,
        calories: sessionCalories,
        completedAt: DateTime.now(),
      );
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('activities')
          .add(session.toFirestore());
    }
    if (!mounted) return;
    await _showCompletionDialog(sessionDistance, sessionTime, sessionCalories);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityStatusPage(
          title: _activityLabel(sessionType),
          distanceKm: sessionDistance,
          movingTime: _formatDuration(sessionTime),
          avgSpeedKmh: sessionSpeed,
          routePoints: List<LatLng>.from(_routePoints),
          activityType: sessionType.name,
          steps: sessionSteps,
          calories: sessionCalories,
        ),
      ),
    );
  }

  Future<void> _showCompletionDialog(
    double distance,
    Duration duration,
    double calories,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF121B2D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: <Color>[Color(0xFFFF6A00), Color(0xFFFFA449)],
                    ),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Activity Complete',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${distance.toStringAsFixed(2)} km | ${_formatDuration(duration)} | ${calories.toStringAsFixed(0)} kcal',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFA9B4C7), height: 1.5),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickPostImage() async {
    final XFile? file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() {
      _selectedImagePath = file.path;
    });
  }

  void _publishPost() {
    final String caption = _postController.text.trim();
    if (caption.isEmpty && _selectedImagePath == null) return;
    setState(() {
      _posts.insert(
        0,
        _SocialPost(
          userName: _profileName,
          timeAgo: 'Just now',
          caption: caption.isEmpty ? 'New activity update' : caption,
          imageUrl: null,
          likes: 0,
          comments: 0,
          distance: _distanceKm.toStringAsFixed(1),
          duration: _formatDuration(_elapsed),
          calories: _calories.toStringAsFixed(0),
        ),
      );
      _postController.clear();
      _locationController.clear();
      _selectedImagePath = null;
    });
  }

  Future<void> _openCommunityComposer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131D31),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Create Post',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _postController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: _field('Share your activity...'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                style: const TextStyle(color: Colors.white),
                decoration: _field('Add location'),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: _pickPostImage,
                    icon: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFF93A0B6),
                    ),
                  ),
                  if (_selectedImagePath != null)
                    const Text(
                      'Image selected',
                      style: TextStyle(color: Color(0xFF93A0B6)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      _publishPost();
                      Navigator.pop(context);
                    },
                    child: const Text('Post'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleLike(_SocialPost post) {
    setState(() {
      post.isLiked = !post.isLiked;
      post.likes += post.isLiked ? 1 : -1;
    });
  }

  String _activityLabel(TrackActivityType type) {
    switch (type) {
      case TrackActivityType.running:
        return 'Running';
      case TrackActivityType.walking:
        return 'Walking';
      case TrackActivityType.cycling:
        return 'Cycling';
    }
  }

  String _formatDuration(Duration d) {
    final String hours = d.inHours.toString().padLeft(2, '0');
    final String minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF08111E), Color(0xFF091527), Color(0xFF07111F)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_currentTab),
                    child: _buildCurrentTab(),
                  ),
                ),
              ),
              _buildBottomNavigation(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentTab) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildTrackTab();
      case 2:
        return _buildSocialTab();
      case 3:
        return const EventsPage();
      case 4:
        return _buildProfileTab();
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    final DateTime today = DateTime.now();
    final List<ActivitySession> todaySessions = _activitySessions.where((ActivitySession s) {
      return s.completedAt.year == today.year &&
          s.completedAt.month == today.month &&
          s.completedAt.day == today.day;
    }).toList();
    final int todaySteps = todaySessions.fold(0, (int sum, ActivitySession s) => sum + s.steps);
    final double todayCalories =
        todaySessions.fold(0, (double sum, ActivitySession s) => sum + s.calories);
    final double todayKm =
        todaySessions.fold(0, (double sum, ActivitySession s) => sum + s.distanceKm);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        _buildHomeHeader(),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                label: 'Steps',
                value: '$todaySteps',
                sub: '/ 10,000',
                icon: Icons.directions_walk,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Calories',
                value: todayCalories.toStringAsFixed(0),
                sub: '/ 600 kcal',
                icon: Icons.local_fire_department_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Distance',
                value: todayKm.toStringAsFixed(2),
                sub: '/ 8 km',
                icon: Icons.timeline_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Today\'s Goal',
          child: Column(
            children: <Widget>[
              _GoalRow(label: 'Steps', current: todaySteps.toDouble(), goal: 10000, valueLabel: '$todaySteps / 10000'),
              const SizedBox(height: 14),
              _GoalRow(label: 'Calories', current: todayCalories, goal: 500, valueLabel: '${todayCalories.toStringAsFixed(0)} / 500 kcal'),
              const SizedBox(height: 14),
              _GoalRow(label: 'Distance', current: todayKm, goal: 5, valueLabel: '${todayKm.toStringAsFixed(1)} / 5 km'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: _QuickActionCard(
                title: 'Food & Nutrition',
                subtitle: 'Track your meals',
                colors: const <Color>[Color(0xFF1D8B4B), Color(0xFF173328)],
                icon: Icons.restaurant_menu_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ActivityCalendarPage(
                      sessions: _activitySessions,
                      initialTab: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                title: 'Start Activity',
                subtitle: 'Track your workout',
                colors: const <Color>[Color(0xFF6C2BD9), Color(0xFF2A1B5B)],
                icon: Icons.bolt_rounded,
                onTap: () => setState(() => _currentTab = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Activity Summary',
          child: _HomeSummaryPanel(
            steps: todaySteps,
            stepsGoal: 10000,
            calories: todayCalories,
            caloriesGoal: 500,
            distance: todayKm,
            distanceGoal: 5,
            stepsProgress: (todaySteps / 10000).clamp(0, 1),
            caloriesProgress: (todayCalories / 500).clamp(0, 1),
            distanceProgress: (todayKm / 5).clamp(0, 1),
          ),
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ActivityCalendarPage(sessions: _activitySessions),
            ),
          ),
          child: const _SectionHeader(title: 'Recent Activity', actionLabel: 'See All →'),
        ),
        const SizedBox(height: 10),
        if (_activitySessions.isEmpty)
          const _EmptyCard(
            title: 'No activities yet',
            subtitle: 'Your latest sessions will appear here once you start tracking.',
          )
        else
          ..._activitySessions.take(3).map((ActivitySession s) => _ActivityTile(
            session: s,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActivityCalendarPage(sessions: _activitySessions),
              ),
            ),
          )),
      ],
    );
  }

  Widget _buildHomeHeader() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Welcome back',
                style: TextStyle(color: Color(0xFF98A5B8), fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                _profileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        _ActionCircle(
          icon: Icons.search_rounded,
          onTap: () {},
        ),
        const SizedBox(width: 10),
        _ActionCircle(
          icon: Icons.chat_bubble_outline_rounded,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatPage()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTrackTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        _sectionBanner('Track Activity', 'Start your workout session'),
        const SizedBox(height: 16),
        Row(
          children: TrackActivityType.values.map((TrackActivityType type) {
            final bool selected = _selectedActivity == type;
            final bool disabled = _isTracking && !selected;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: type == TrackActivityType.cycling ? 0 : 10),
                child: _ActivityChip(
                  label: _activityLabel(type),
                  selected: selected,
                  onTap: disabled ? null : () => setState(() => _selectedActivity = type),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _MapCard(
          mapController: _mapController,
          routePoints: _routePoints,
          currentLatLng: _currentLatLng,
          gpsStatusText: _gpsStatusText,
          gpsAcquired: _gpsAcquired,
          isTracking: _isTracking,
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: <Widget>[
            _MetricCard(label: 'Duration', value: _formatDuration(_elapsed), icon: Icons.timer_outlined),
            _MetricCard(label: 'Distance', value: '${_distanceKm.toStringAsFixed(2)} km', icon: Icons.straighten_rounded),
            _MetricCard(label: 'Avg Speed', value: '${_currentSpeedKmh.toStringAsFixed(1)} km/h', icon: Icons.speed_rounded),
            _MetricCard(label: 'Calories', value: '${_calories.toStringAsFixed(0)} kcal', icon: Icons.local_fire_department_rounded),
          ],
        ),
        const SizedBox(height: 12),
        _MetricCard(label: 'Steps', value: '$_steps steps', icon: Icons.directions_walk_rounded, fullWidth: true),
        const SizedBox(height: 16),
        if (_isTracking)
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _isPaused ? _resumeTracking : _pauseTracking,
                  child: Text(_isPaused ? 'Resume' : 'Pause'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _finishTracking,
                  child: const Text('Finish Activity'),
                ),
              ),
            ],
          )
        else
          FilledButton.icon(
            onPressed: _startTracking,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start Activity'),
          ),
      ],
    );
  }
  Widget _buildSocialTab() {
    final String query = _friendSearchController.text.trim().toLowerCase();
    final List<String> friends = _friendSuggestions.where((String name) {
      return query.isEmpty || name.toLowerCase().contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        _sectionBanner('Community', 'Connect with friends and share your activity'),
        const SizedBox(height: 16),
        const Text(
          'Friends',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _friendSearchController,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Colors.white),
          decoration: _field('Search friends').copyWith(
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF93A0B6)),
          ),
        ),
        const SizedBox(height: 12),
        ...friends.map((String friendName) => _FriendCard(name: friendName)),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Posts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: _openCommunityComposer,
              icon: const Icon(
                Icons.mode_comment_outlined,
                color: Color(0xFFFF8A1F),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._posts.map(
          (_SocialPost post) => _PostCard(
            post: post,
            onLike: () => _toggleLike(post),
          ),
        ),
      ],
    );
  }

  Widget _buildEventsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _sectionBanner(
                'Events',
                'Join group activities and challenges',
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF162239),
                borderRadius: BorderRadius.circular(18),
              ),
              child: IconButton(
                onPressed: _createEvent,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: _SwitchPill(
                label: 'Upcoming',
                selected: !_showPastEvents,
                onTap: () => setState(() => _showPastEvents = false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SwitchPill(
                label: 'Past Events',
                selected: _showPastEvents,
                onTap: () => setState(() => _showPastEvents = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_showPastEvents)
          ..._pastEvents.map((_PastEventItem item) => _PastEventCard(item: item))
        else
          ..._upcomingEvents.map(
            (_EventItem item) => _EventCard(
              item: item,
              onToggle: () {
                setState(() {
                  item.joined = !item.joined;
                  item.joinedCount += item.joined ? 1 : -1;
                });
              },
            ),
          ),
      ],
    );
  }

  Future<void> _createEvent() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131D31),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Create Event',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _eventTitleController,
                style: const TextStyle(color: Colors.white),
                decoration: _field('Event title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _eventLocationController,
                style: const TextStyle(color: Colors.white),
                decoration: _field('Location'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_eventTitleController.text.trim().isEmpty ||
                        _eventLocationController.text.trim().isEmpty) {
                      return;
                    }
                    setState(() {
                      _upcomingEvents.insert(
                        0,
                        _EventItem(
                          title: _eventTitleController.text.trim(),
                          type: _activityLabel(_selectedActivity),
                          dateLabel: 'Upcoming',
                          timeLabel: 'Flexible',
                          locationLabel: _eventLocationController.text.trim(),
                          organizer: _profileName,
                          joinedCount: 1,
                          capacity: 20,
                          joined: true,
                          accent: const Color(0xFFFF7A18),
                        ),
                      );
                      _eventTitleController.clear();
                      _eventLocationController.clear();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Create Event'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Row(
          children: [
            const Expanded(child: SizedBox()),
            IconButton(
              tooltip: 'Log Out',
              onPressed: () async {
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1A2A44),
                    title: const Text('Log Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    content: const Text('Are you sure you want to log out?', style: TextStyle(color: Color(0xFFB2C1D7))),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                        child: const Text('Log Out'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await FirebaseAuth.instance.signOut();
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to log out. Please try again.')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 26),
            ),
          ],
        ),
        _sectionBanner('Profile', 'Your progress overview'),
        const SizedBox(height: 16),
        _SectionCard(
          child: Column(
            children: <Widget>[
              Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: <Color>[Color(0xFFFF6A00), Color(0xFFFFA449)],
                  ),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 42),
              ),
              const SizedBox(height: 18),
              Text(
                _profileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _profileEmail,
                style: const TextStyle(color: Color(0xFFA6B2C6)),
              ),
              const SizedBox(height: 6),
              const Text(
                'Fitness enthusiast | Marathon runner | Love to stay active',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8E9BB0), height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.18,
          children: <Widget>[
            _ProfileMetric(label: 'Total KM', value: _sevenDayKm.toStringAsFixed(1)),
            _ProfileMetric(label: 'Workouts', value: '$_sevenDayWorkouts'),
            _ProfileMetric(
              label: 'Calories',
              value: _sevenDayCalories.toStringAsFixed(0),
            ),
            _ProfileMetric(label: 'Day Streak', value: '$_dayStreak'),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Weekly Goals',
          child: Column(
            children: <Widget>[
              _GoalRow(
                label: 'Distance',
                current: _sevenDayKm,
                goal: 40,
                valueLabel: '${_sevenDayKm.toStringAsFixed(1)} / 40 km',
              ),
              const SizedBox(height: 14),
              _GoalRow(
                label: 'Workouts',
                current: _sevenDayWorkouts.toDouble(),
                goal: 7,
                valueLabel: '$_sevenDayWorkouts / 7 sessions',
              ),
              const SizedBox(height: 14),
              _GoalRow(
                label: 'Calories',
                current: _sevenDayCalories,
                goal: 3500,
                valueLabel:
                    '${_sevenDayCalories.toStringAsFixed(0)} / 3500 kcal',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FoodNutritionPage()),
                ),
                icon: const Icon(Icons.restaurant_menu_rounded),
                label: const Text('Food & Nutrition'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileViewPage()),
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open Profile'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _ConnectDoctorSection(),
      ],
    );
  }

  Widget _heroBanner() {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _introController, curve: Curves.easeOut),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFFF6A00), Color(0xFF8A2A12), Color(0xFF10192B)],
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _profileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A polished fitness dashboard built around your daily momentum.',
                    style: TextStyle(color: Color(0xFFF2D6C7), height: 1.45),
                  ),
                ],
              ),
            ),
            const Column(
              children: <Widget>[
                _ActionCircle(icon: Icons.search_rounded),
                SizedBox(height: 10),
                _ActionCircle(icon: Icons.notifications_none_rounded),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionBanner(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFF6A00), Color(0xFF7B2814), Color(0xFF10192B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Color(0xFFF1D5C7))),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF09111E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          _BottomItem(icon: Icons.home_rounded, label: 'Home', selected: _currentTab == 0, onTap: () => setState(() => _currentTab = 0)),
          _BottomItem(icon: Icons.blur_circular_rounded, label: 'Track', selected: _currentTab == 1, onTap: () => setState(() => _currentTab = 1)),
          _BottomItem(icon: Icons.groups_2_rounded, label: 'Social', selected: _currentTab == 2, onTap: () => setState(() => _currentTab = 2)),
          _BottomItem(icon: Icons.event_note_rounded, label: 'Events', selected: _currentTab == 3, onTap: () => setState(() => _currentTab = 3)),
          _BottomItem(icon: Icons.person_outline_rounded, label: 'Profile', selected: _currentTab == 4, onTap: () => setState(() => _currentTab = 4)),
        ],
      ),
    );
  }

  Widget _dateStamp() {
    final DateTime now = DateTime.now();
    return Text(
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      style: const TextStyle(color: Color(0xFF90A0B6)),
    );
  }

  InputDecoration _field(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF7E8CA3)),
      filled: true,
      fillColor: const Color(0xFF23314B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }
}
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          actionLabel,
          style: const TextStyle(
            color: Color(0xFFFFA449),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({this.title, this.trailing, required this.child});

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15233A),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x1CFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
  });

  final String label;
  final String value;
  final String sub;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF182840),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: const Color(0xFFFFA449)),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: Color(0xFFA7B2C4))),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(sub, style: const TextStyle(color: Color(0xFF6C7890), fontSize: 12)),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.label,
    required this.current,
    required this.goal,
    required this.valueLabel,
  });

  final String label;
  final double current;
  final double goal;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final double progress = goal == 0 ? 0 : (current / goal).clamp(0, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label, style: const TextStyle(color: Color(0xFFBBC6D7))),
            const Spacer(),
            Text(
              valueLabel,
              style: const TextStyle(color: Color(0xFF90A0B6), fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: progress,
            backgroundColor: const Color(0xFF31415C),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF8A1F)),
          ),
        ),
      ],
    );
  }
}

class _SummaryRings extends StatelessWidget {
  const _SummaryRings({
    required this.stepsProgress,
    required this.caloriesProgress,
    required this.distanceProgress,
  });

  final double stepsProgress;
  final double caloriesProgress;
  final double distanceProgress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          width: 220,
          height: 220,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 900),
            tween: Tween<double>(begin: 0, end: 1),
            builder: (_, double t, __) {
              return CustomPaint(
                painter: _RingPainter(
                  stepsProgress * t,
                  caloriesProgress * t,
                  distanceProgress * t,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _Legend(color: Color(0xFFFFB054), label: 'Steps'),
            SizedBox(width: 18),
            _Legend(color: Color(0xFFFF7A18), label: 'Calories'),
            SizedBox(width: 18),
            _Legend(color: Color(0xFFF7C948), label: 'Active'),
          ],
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.steps, this.calories, this.distance);

  final double steps;
  final double calories;
  final double distance;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final List<double> radii = <double>[88, 70, 52];
    final List<Color> colors = <Color>[
      const Color(0xFFFFB054),
      const Color(0xFFFF7A18),
      const Color(0xFFF7C948),
    ];
    final List<double> values = <double>[steps, calories, distance];

    for (int i = 0; i < radii.length; i++) {
      final Rect rect = Rect.fromCircle(center: center, radius: radii[i]);
      final Paint track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF31415C);
      final Paint progress = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = colors[i];
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * values[i], false, progress);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.steps != steps ||
        oldDelegate.calories != calories ||
        oldDelegate.distance != distance;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFF93A0B6))),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<Color> colors;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: colors),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFE4DFF4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSummaryPanel extends StatelessWidget {
  const _HomeSummaryPanel({
    required this.steps,
    required this.stepsGoal,
    required this.calories,
    required this.caloriesGoal,
    required this.distance,
    required this.distanceGoal,
    required this.stepsProgress,
    required this.caloriesProgress,
    required this.distanceProgress,
  });

  final int steps;
  final int stepsGoal;
  final double calories;
  final double caloriesGoal;
  final double distance;
  final double distanceGoal;
  final double stepsProgress;
  final double caloriesProgress;
  final double distanceProgress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 150,
          height: 150,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 900),
            tween: Tween<double>(begin: 0, end: 1),
            builder: (_, double t, __) {
              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CustomPaint(
                    size: const Size.square(150),
                    painter: _RingPainter(
                      stepsProgress * t,
                      caloriesProgress * t,
                      distanceProgress * t,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '$steps',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'steps',
                        style: TextStyle(color: Color(0xFF94A1B5), fontSize: 12),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SummaryLine(
                color: const Color(0xFFFFB054),
                label: 'Steps',
                value: '$steps / $stepsGoal',
                percent: '${(stepsProgress * 100).round()}%',
              ),
              const SizedBox(height: 12),
              _SummaryLine(
                color: const Color(0xFFFF7A18),
                label: 'Calories',
                value: '${calories.toStringAsFixed(0)} / ${caloriesGoal.toStringAsFixed(0)}',
                percent: '${(caloriesProgress * 100).round()}%',
              ),
              const SizedBox(height: 12),
              _SummaryLine(
                color: const Color(0xFFF7C948),
                label: 'Distance',
                value: '${distance.toStringAsFixed(1)} / ${distanceGoal.toStringAsFixed(0)} km',
                percent: '${(distanceProgress * 100).round()}%',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.color,
    required this.label,
    required this.value,
    required this.percent,
  });

  final Color color;
  final String label;
  final String value;
  final String percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(color: Color(0xFF96A3B7), fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Text(
          percent,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.session, this.onTap});

  final ActivitySession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _SectionCard(
          child: Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: <Color>[Color(0xFFFF6A00), Color(0xFFFF9E43)],
                  ),
                ),
                child: const Icon(Icons.show_chart_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      session.activityType.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Latest activity',
                      style: TextStyle(color: Color(0xFF8490A5)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${session.distanceKm.toStringAsFixed(2)} km',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${session.duration}  ${session.calories.toStringAsFixed(0)} cal',
                    style: const TextStyle(color: Color(0xFF8A96AB)),
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

class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.mapController,
    required this.routePoints,
    required this.currentLatLng,
    required this.gpsStatusText,
    required this.gpsAcquired,
    required this.isTracking,
  });

  final MapController mapController;
  final List<LatLng> routePoints;
  final LatLng? currentLatLng;
  final String gpsStatusText;
  final bool gpsAcquired;
  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    final bool hasRoute = routePoints.length >= 2;
    final LatLng center = currentLatLng ??
        (routePoints.isNotEmpty ? routePoints.last : const LatLng(20.5937, 78.9629));

    return _SectionCard(
      child: SizedBox(
        height: 300,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 17.5,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                ),
                children: [
                  // Base map tiles
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.build_u',
                  ),

                  // Route polyline â€” orange like Swiggy delivery route
                  if (hasRoute)
                    PolylineLayer(
                      polylines: [
                        // Shadow/outline for visibility
                        Polyline(
                          points: routePoints,
                          strokeWidth: 9,
                          color: Colors.black.withOpacity(0.25),
                          strokeCap: StrokeCap.round,
                          strokeJoin: StrokeJoin.round,
                        ),
                        // Main route line
                        Polyline(
                          points: routePoints,
                          strokeWidth: 6,
                          color: const Color(0xFFFF6200),
                          strokeCap: StrokeCap.round,
                          strokeJoin: StrokeJoin.round,
                        ),
                      ],
                    ),

                  // Markers layer
                  MarkerLayer(
                    markers: [
                      // Start marker â€” green dot
                      if (routePoints.isNotEmpty)
                        Marker(
                          point: routePoints.first,
                          width: 28,
                          height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.circle, color: Colors.white, size: 10),
                          ),
                        ),

                      // Current / end position â€” orange pulsing dot
                      if (currentLatLng != null)
                        Marker(
                          point: currentLatLng!,
                          width: 32,
                          height: 32,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer pulse ring
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6200).withOpacity(0.25),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              // Inner dot
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6200),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF6200).withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // GPS status bar at bottom
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      gpsAcquired ? Icons.gps_fixed : Icons.gps_off_rounded,
                      color: gpsAcquired ? const Color(0xFF4CAF50) : const Color(0xFF9A8D73),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        gpsStatusText,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    if (hasRoute)
                      Text(
                        '${routePoints.length} pts',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    if (!hasRoute)
                      Text(
                        isTracking ? 'Acquiring route...' : 'Press Start',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),

            // Legend â€” start/end
            if (hasRoute)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('Start', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFF6200), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('Current', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ]),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
class _ActivityChip extends StatelessWidget {
  const _ActivityChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF7A18) : const Color(0xFF15233A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFFFF7A18) : const Color(0x1CFFFFFF),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF8592A8),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15233A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1CFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: const Color(0xFFFF9E43), size: 18),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Color(0xFF90A0B6))),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: fullWidth ? 28 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2841),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1CFFFFFF)),
      ),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFFE8DDFE),
            child: Icon(Icons.person, color: Color(0xFF7A678A), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Icon(
            Icons.person_add_alt_1_rounded,
            color: Color(0xFFFF8A1F),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onLike});

  final _SocialPost post;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B2943),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x1CFFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: <Widget>[
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFFE7D8FF),
                    child: Icon(Icons.person, color: Color(0xFF5B4B7C), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          post.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          post.timeAgo,
                          style: const TextStyle(
                            color: Color(0xFF8A96AB),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_horiz_rounded, color: Color(0xFF8A96AB)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                post.caption,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
            ),
            SizedBox(
              height: 220,
              width: double.infinity,
              child: post.imageUrl == null
                  ? Container(
                      color: const Color(0xFF1A2742),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_outlined,
                        color: Color(0xFF60708A),
                        size: 44,
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(0),
                      child: Image.network(post.imageUrl!, fit: BoxFit.cover),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              color: const Color(0xFF20314D),
              child: Row(
                children: <Widget>[
                  Expanded(child: _MiniStat(label: 'Distance', value: post.distance)),
                  Expanded(child: _MiniStat(label: 'Time', value: post.duration)),
                  Expanded(child: _MiniStat(label: 'Calories', value: post.calories)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: <Widget>[
                  Text(
                    '${post.likes} likes',
                    style: const TextStyle(color: Color(0xFF8A96AB), fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    '${post.comments} comments',
                    style: const TextStyle(color: Color(0xFF8A96AB), fontSize: 13),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x223B4C67)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onLike,
                      icon: Icon(
                        post.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: const Color(0xFFC6CFDD),
                        size: 20,
                      ),
                      label: const Text(
                        'Like',
                        style: TextStyle(color: Color(0xFFC6CFDD)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Color(0xFFC6CFDD),
                        size: 20,
                      ),
                      label: const Text(
                        'Comment',
                        style: TextStyle(color: Color(0xFFC6CFDD)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.share_outlined,
                        color: Color(0xFFC6CFDD),
                        size: 20,
                      ),
                      label: const Text(
                        'Share',
                        style: TextStyle(color: Color(0xFFC6CFDD)),
                      ),
                    ),
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(color: Color(0xFF8795AA), fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.item, required this.onToggle});

  final _EventItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(colors: <Color>[item.accent, item.accent.withOpacity(0.86)]),
        ),
        child: Container(
          margin: const EdgeInsets.only(top: 62),
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: Color(0xFF16233A),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.dateLabel, style: const TextStyle(color: Color(0xFFA6B1C5))),
              Text(item.timeLabel, style: const TextStyle(color: Color(0xFFA6B1C5))),
              Text(item.locationLabel, style: const TextStyle(color: Color(0xFFA6B1C5))),
              const SizedBox(height: 12),
              Text(
                'Organized by ${item.organizer}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                '${item.joinedCount} / ${item.capacity} joined',
                style: const TextStyle(color: Color(0xFF7D889D)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: item.joined
                    ? OutlinedButton(onPressed: onToggle, child: const Text('Leave Event'))
                    : FilledButton(onPressed: onToggle, child: const Text('Join Event')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastEventCard extends StatelessWidget {
  const _PastEventCard({required this.item});

  final _PastEventItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SectionCard(
        child: Row(
          children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2D47),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.history_rounded, color: Color(0xFFFFB054)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(item.dateLabel, style: const TextStyle(color: Color(0xFF90A0B6))),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(item.distance, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${item.participants} joined', style: const TextStyle(color: Color(0xFF90A0B6))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchPill extends StatelessWidget {
  const _SwitchPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF8A1F) : const Color(0xFF152139),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? const Color(0xFF111826) : const Color(0xFF93A0B6),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15233A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1CFFFFFF)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFFF8A1F),
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Color(0xFF8E9BB0))),
        ],
      ),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 48,
        height: 48,
        child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: Colors.white),
      ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0x18FF7A18) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: selected ? const Color(0xFFFF8A1F) : const Color(0xFF8795AA),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFFFF8A1F) : const Color(0xFF8795AA),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        children: <Widget>[
          const Icon(Icons.insights_outlined, color: Color(0xFFFF9E43), size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF90A0B6), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ConnectDoctorSection extends StatefulWidget {
  const _ConnectDoctorSection();

  @override
  State<_ConnectDoctorSection> createState() => _ConnectDoctorSectionState();
}

class _ConnectDoctorSectionState extends State<_ConnectDoctorSection> {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String? _assignedDoctorId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAssigned();
  }

  Future<void> _loadAssigned() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    if (!mounted) return;
    setState(() {
      _assignedDoctorId = doc.data()?['assignedDoctorId'] as String?;
      _loading = false;
    });
  }

  Future<void> _connect(String doctorId) async {
    await FirebaseFirestore.instance.collection('users').doc(_uid).update({
      'assignedDoctorId': doctorId,
    });
    if (!mounted) return;
    setState(() => _assignedDoctorId = doctorId);
  }

  Future<void> _disconnect() async {
    await FirebaseFirestore.instance.collection('users').doc(_uid).update({
      'assignedDoctorId': FieldValue.delete(),
    });
    if (!mounted) return;
    setState(() => _assignedDoctorId = null);
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Connect to a Doctor',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('doctors').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Text(
                    'No doctors available yet.',
                    style: TextStyle(color: Color(0xFF8A96AB)),
                  );
                }
                return Column(
                  children: docs.map((doc) {
                    final data = doc.data();
                    final name = (data['name'] as String? ?? '').trim();
                    final qualification = data['qualification'] as String? ?? '';
                    final isConnected = _assignedDoctorId == doc.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2841),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isConnected
                              ? const Color(0xFFFF7A18)
                              : const Color(0x1CFFFFFF),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFFFF6A00), Color(0xFFFFA449)],
                              ),
                            ),
                            child: const Icon(Icons.medical_services_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dr. $name',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (qualification.isNotEmpty)
                                  Text(
                                    qualification,
                                    style: const TextStyle(
                                        color: Color(0xFF8A96AB), fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          if (isConnected) ...<Widget>[
                            IconButton(
                              tooltip: 'Chat with Dr. $name',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DirectChatPage(
                                    otherUid: doc.id,
                                    otherName: name,
                                    isDoctor: false,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.chat_bubble_outline_rounded,
                                  color: Color(0xFFFF8A1F)),
                            ),
                            TextButton(
                              onPressed: _disconnect,
                              child: const Text('Disconnect',
                                  style: TextStyle(color: Colors.redAccent)),
                            ),
                          ] else
                            TextButton(
                              onPressed: () => _connect(doc.id),
                              child: const Text('Connect',
                                  style: TextStyle(color: Color(0xFFFF8A1F))),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}

class _SocialPost {
  _SocialPost({
    required this.userName,
    required this.timeAgo,
    required this.caption,
    required this.imageUrl,
    required this.likes,
    required this.comments,
    required this.distance,
    required this.duration,
    required this.calories,
    this.isLiked = false,
  });

  final String userName;
  final String timeAgo;
  final String caption;
  final String? imageUrl;
  int likes;
  int comments;
  final String distance;
  final String duration;
  final String calories;
  bool isLiked;
}

class _EventItem {
  _EventItem({
    required this.title,
    required this.type,
    required this.dateLabel,
    required this.timeLabel,
    required this.locationLabel,
    required this.organizer,
    required this.joinedCount,
    required this.capacity,
    required this.joined,
    required this.accent,
  });

  final String title;
  final String type;
  final String dateLabel;
  final String timeLabel;
  final String locationLabel;
  final String organizer;
  int joinedCount;
  final int capacity;
  bool joined;
  final Color accent;
}

class _PastEventItem {
  const _PastEventItem({
    required this.title,
    required this.dateLabel,
    required this.distance,
    required this.participants,
  });

  final String title;
  final String dateLabel;
  final String distance;
  final int participants;
}