import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ActivityStatusPage extends StatefulWidget {
  const ActivityStatusPage({
    super.key,
    required this.title,
    required this.distanceKm,
    required this.movingTime,
    required this.avgSpeedKmh,
    this.routePoints = const [],
    this.activityType = 'running',
    this.steps = 0,
    this.calories = 0,
  });

  final String title;
  final double distanceKm;
  final String movingTime;
  final double avgSpeedKmh;
  final List<LatLng> routePoints;
  final String activityType;
  final int steps;
  final double calories;

  @override
  State<ActivityStatusPage> createState() => _ActivityStatusPageState();
}

class _ActivityStatusPageState extends State<ActivityStatusPage> {
  String _userName = '';
  String _locationLabel = '';
  bool _posting = false;
  bool _sharing = false;
  final _captionController = TextEditingController();
  final _shareCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchUserName();
    _fetchLocation();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!mounted) return;
    setState(() =>
        _userName = (doc.data()?['name'] as String? ?? '').trim());
  }

  Future<void> _fetchLocation() async {
    if (widget.routePoints.isEmpty) return;
    try {
      final mid =
          widget.routePoints[widget.routePoints.length ~/ 2];
      final placemarks =
          await placemarkFromCoordinates(mid.latitude, mid.longitude);
      if (!mounted) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.locality, p.administrativeArea]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        setState(() => _locationLabel = parts);
      }
    } catch (_) {}
  }

  String get _dateLabel {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  String get _initials {
    if (_userName.isEmpty) return 'U';
    final parts = _userName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return _userName[0].toUpperCase();
  }

  IconData get _activityIcon {
    switch (widget.activityType.toLowerCase()) {
      case 'cycling': return Icons.directions_bike;
      case 'walking': return Icons.directions_walk;
      default: return Icons.directions_run;
    }
  }

  LatLng get _mapCenter {
    if (widget.routePoints.isEmpty) return const LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in widget.routePoints) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(
        lat / widget.routePoints.length, lng / widget.routePoints.length);
  }

  double get _zoomLevel {
    if (widget.routePoints.length < 2) return 15;
    double minLat = widget.routePoints.first.latitude;
    double maxLat = minLat;
    double minLng = widget.routePoints.first.longitude;
    double maxLng = minLng;
    for (final p in widget.routePoints) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final span = math.max(maxLat - minLat, maxLng - minLng);
    if (span < 0.002) return 16;
    if (span < 0.01) return 14;
    if (span < 0.05) return 12;
    return 11;
  }

  // ── Capture share card as image and share ─────────────────────────────────

  Future<void> _shareToInstagram() async {
    setState(() => _sharing = true);
    try {
      // Capture the share card widget as image
      final boundary = _shareCardKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        setState(() => _sharing = false);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        setState(() => _sharing = false);
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/route_card.png');
      await file.writeAsBytes(bytes);

      final caption =
          '${widget.title} 🏃\n'
          '📍 ${_locationLabel.isNotEmpty ? _locationLabel : _dateLabel}\n'
          '📏 ${widget.distanceKm.toStringAsFixed(2)} km  '
          '⏱ ${widget.movingTime}  '
          '⚡ ${widget.avgSpeedKmh.toStringAsFixed(1)} km/h\n'
          '👟 ${widget.steps} steps  🔥 ${widget.calories.toStringAsFixed(0)} kcal\n\n'
          'Tracked with BuildYou 💪\n#fitness #running #buildyou';

      await Share.shareXFiles(
        [XFile(file.path)],
        text: caption,
        subject: widget.title,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _postActivity(BuildContext sheetCtx) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _posting = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('posts')
          .add({
        'caption': _captionController.text.trim().isEmpty
            ? widget.title
            : _captionController.text.trim(),
        'activityType': widget.activityType,
        'distanceKm': widget.distanceKm,
        'movingTime': widget.movingTime,
        'avgSpeedKmh': widget.avgSpeedKmh,
        'location': _locationLabel,
        'userName': _userName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(sheetCtx);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Posted to community!',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF1B5E20),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _showPostDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111F37),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Post to Community',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _captionController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Write something about your activity...',
                hintStyle:
                    const TextStyle(color: Color(0xFF8FA0BA)),
                filled: true,
                fillColor: const Color(0xFF1A2A44),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _posting ? null : () => _postActivity(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6200),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(_posting ? 'Posting...' : 'Post'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F18),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Share Card (captured for Instagram) ──────────────────
              RepaintBoundary(
                key: _shareCardKey,
                child: _ShareCard(
                  userName: _userName.isEmpty ? 'User' : _userName,
                  initials: _initials,
                  title: widget.title,
                  activityIcon: _activityIcon,
                  distanceKm: widget.distanceKm,
                  movingTime: widget.movingTime,
                  avgSpeedKmh: widget.avgSpeedKmh,
                  steps: widget.steps,
                  calories: widget.calories,
                  locationLabel: _locationLabel,
                  dateLabel: _dateLabel,
                  routePoints: widget.routePoints,
                  mapCenter: _mapCenter,
                  zoomLevel: _zoomLevel,
                ),
              ),

              // ── Action buttons ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  children: [
                    // Share to Instagram
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _sharing ? null : _shareToInstagram,
                        icon: _sharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.share_rounded),
                        label: Text(_sharing
                            ? 'Preparing...'
                            : 'Share Route Card'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6200),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showPostDialog,
                            icon: const Icon(Icons.people_outline,
                                color: Color(0xFFFF6200)),
                            label: const Text('Post to Community',
                                style: TextStyle(
                                    color: Color(0xFFFF6200))),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Color(0xFFFF6200)),
                              minimumSize:
                                  const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back,
                                color: Color(0xFF8FA0BA)),
                            label: const Text('Back',
                                style: TextStyle(
                                    color: Color(0xFF8FA0BA))),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Color(0xFF2A3A54)),
                              minimumSize:
                                  const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                            ),
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
      ),
    );
  }
}

// ── Aesthetic Share Card ──────────────────────────────────────────────────────

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.userName,
    required this.initials,
    required this.title,
    required this.activityIcon,
    required this.distanceKm,
    required this.movingTime,
    required this.avgSpeedKmh,
    required this.steps,
    required this.calories,
    required this.locationLabel,
    required this.dateLabel,
    required this.routePoints,
    required this.mapCenter,
    required this.zoomLevel,
  });

  final String userName;
  final String initials;
  final String title;
  final IconData activityIcon;
  final double distanceKm;
  final String movingTime;
  final double avgSpeedKmh;
  final int steps;
  final double calories;
  final String locationLabel;
  final String dateLabel;
  final List<LatLng> routePoints;
  final LatLng mapCenter;
  final double zoomLevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1B2A), Color(0xFF1A0A2E)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6200).withOpacity(0.3),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Map section ─────────────────────────────────────────
            SizedBox(
              height: 280,
              child: Stack(
                children: [
                  // Map
                  Positioned.fill(
                    child: routePoints.length >= 2
                        ? FlutterMap(
                            options: MapOptions(
                              initialCenter: mapCenter,
                              initialZoom: zoomLevel,
                              interactionOptions:
                                  const InteractionOptions(
                                flags: InteractiveFlag.none,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'com.example.build_u',
                              ),
                              // Route shadow
                              PolylineLayer(polylines: [
                                Polyline(
                                  points: routePoints,
                                  color: Colors.black
                                      .withOpacity(0.3),
                                  strokeWidth: 10,
                                  strokeCap: StrokeCap.round,
                                ),
                              ]),
                              // Route line
                              PolylineLayer(polylines: [
                                Polyline(
                                  points: routePoints,
                                  color: const Color(0xFFFF6200),
                                  strokeWidth: 6,
                                  strokeCap: StrokeCap.round,
                                  strokeJoin: StrokeJoin.round,
                                ),
                              ]),
                              // Start / End markers
                              MarkerLayer(markers: [
                                if (routePoints.isNotEmpty)
                                  Marker(
                                    point: routePoints.first,
                                    width: 24,
                                    height: 24,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(
                                            0xFF2E7D32),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white,
                                            width: 3),
                                      ),
                                    ),
                                  ),
                                if (routePoints.length >= 2)
                                  Marker(
                                    point: routePoints.last,
                                    width: 24,
                                    height: 24,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(
                                            0xFFFF6200),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white,
                                            width: 3),
                                      ),
                                    ),
                                  ),
                              ]),
                            ],
                          )
                        : Container(
                            color: const Color(0xFF0D1B2A),
                            child: CustomPaint(
                                painter: _FallbackPainter()),
                          ),
                  ),
                  // Dark gradient overlay at bottom
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    height: 80,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0xCC0D1B2A),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // App branding top-right
                  Positioned(
                    top: 12, right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6200),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'BuildYou',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ),
                  // Activity icon top-left
                  Positioned(
                    top: 12, left: 12,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(activityIcon,
                          color: const Color(0xFFFF6200), size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // ── Stats section ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User + date
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFFF6200),
                        child: Text(initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(userName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            Text(
                              locationLabel.isNotEmpty
                                  ? '📍 $locationLabel · $dateLabel'
                                  : '📅 $dateLabel',
                              style: const TextStyle(
                                  color: Color(0xFF8FA0BA),
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Activity title
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 14),

                  // Divider
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        const Color(0xFFFF6200).withOpacity(0.6),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Main stats row
                  Row(
                    children: [
                      _StatBox(
                          label: 'Distance',
                          value:
                              '${distanceKm.toStringAsFixed(2)}',
                          unit: 'km',
                          color: const Color(0xFFFF6200)),
                      _StatDivider(),
                      _StatBox(
                          label: 'Time',
                          value: movingTime,
                          unit: '',
                          color: const Color(0xFF4FC3F7)),
                      _StatDivider(),
                      _StatBox(
                          label: 'Pace',
                          value: avgSpeedKmh
                              .toStringAsFixed(1),
                          unit: 'km/h',
                          color: const Color(0xFF66BB6A)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Secondary stats row
                  Row(
                    children: [
                      _StatBox(
                          label: 'Steps',
                          value: '$steps',
                          unit: '',
                          color: const Color(0xFFF5C433)),
                      _StatDivider(),
                      _StatBox(
                          label: 'Calories',
                          value: calories.toStringAsFixed(0),
                          unit: 'kcal',
                          color: const Color(0xFFE57373)),
                      _StatDivider(),
                      // Start/End legend
                      Expanded(
                        child: Column(
                          children: [
                            Row(children: [
                              Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFF2E7D32),
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              const Text('Start',
                                  style: TextStyle(
                                      color: Color(0xFF8FA0BA),
                                      fontSize: 11)),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFFFF6200),
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              const Text('Finish',
                                  style: TextStyle(
                                      color: Color(0xFF8FA0BA),
                                      fontSize: 11)),
                            ]),
                          ],
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

// ── Supporting widgets ────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            unit.isEmpty ? value : '$value $unit',
            style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF8FA0BA), fontSize: 11)),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: const Color(0xFF2A3A54),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _FallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0D1B2A));
    final roads = Paint()
      ..color = const Color(0xFF1A2A44)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < 8; i++) {
      final y = size.height * (i / 7);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 20), roads);
    }
    final route = Paint()
      ..color = const Color(0xFFFF6200)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final path = ui.Path()
      ..moveTo(size.width * 0.15, size.height * 0.15)
      ..lineTo(size.width * 0.55, size.height * 0.15)
      ..lineTo(size.width * 0.75, size.height * 0.65)
      ..lineTo(size.width * 0.50, size.height * 0.75);
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
