import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
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
  });

  final String title;
  final double distanceKm;
  final String movingTime;
  final double avgSpeedKmh;
  final List<LatLng> routePoints;
  final String activityType;

  @override
  State<ActivityStatusPage> createState() => _ActivityStatusPageState();
}

class _ActivityStatusPageState extends State<ActivityStatusPage> {
  String _userName = '';
  String _locationLabel = '';
  bool _posting = false;
  final _captionController = TextEditingController();

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
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    setState(() {
      _userName = (doc.data()?['name'] as String? ?? '').trim();
    });
  }

  Future<void> _fetchLocation() async {
    if (widget.routePoints.isEmpty) return;
    try {
      final mid = widget.routePoints[widget.routePoints.length ~/ 2];
      final placemarks = await placemarkFromCoordinates(mid.latitude, mid.longitude);
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  String get _initials {
    if (_userName.isEmpty) return 'U';
    final parts = _userName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return _userName[0].toUpperCase();
  }

  void _shareActivity() {
    final text = '${widget.title}\n'
        '📍 $_locationLabel\n'
        '🏃 ${widget.distanceKm.toStringAsFixed(2)} km  '
        '⏱ ${widget.movingTime}  '
        '⚡ ${widget.avgSpeedKmh.toStringAsFixed(1)} km/h\n'
        'Tracked with BuildYou 💪';
    Share.share(text);
  }

  void _showPostDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111F37),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Post to Community',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _captionController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Write something about your activity...',
                hintStyle: const TextStyle(color: Color(0xFF8FA0BA)),
                filled: true,
                fillColor: const Color(0xFF1A2A44),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
        content: Text('Posted to community!', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF1B5E20),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  LatLng get _mapCenter {
    if (widget.routePoints.isEmpty) return const LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in widget.routePoints) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / widget.routePoints.length, lng / widget.routePoints.length);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F18),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: widget.routePoints.length >= 2
                        ? FlutterMap(
                            options: MapOptions(
                              initialCenter: _mapCenter,
                              initialZoom: _zoomLevel,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.build_u',
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: widget.routePoints,
                                    color: const Color(0xFFFF5B00),
                                    strokeWidth: 6,
                                    strokeCap: StrokeCap.round,
                                    strokeJoin: StrokeJoin.round,
                                  ),
                                ],
                              ),
                              MarkerLayer(markers: [
                                if (widget.routePoints.isNotEmpty)
                                  Marker(
                                    point: widget.routePoints.first,
                                    width: 20,
                                    height: 20,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                                if (widget.routePoints.length >= 2)
                                  Marker(
                                    point: widget.routePoints.last,
                                    width: 20,
                                    height: 20,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF5B00),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                              ]),
                            ],
                          )
                        : CustomPaint(painter: _FallbackMapPainter()),
                  ),
                  // Back button
                  Positioned(
                    left: 14,
                    top: 14,
                    child: _CircleIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  // Share button
                  Positioned(
                    right: 62,
                    top: 14,
                    child: _CircleIconButton(
                      icon: Icons.share,
                      onTap: _shareActivity,
                    ),
                  ),
                  // Post to community button
                  Positioned(
                    right: 14,
                    top: 14,
                    child: _CircleIconButton(
                      icon: Icons.add_box_outlined,
                      onTap: _showPostDialog,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              decoration: const BoxDecoration(
                color: Color(0xFF0A0D14),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFFF6200),
                        child: Text(
                          _initials,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _userName.isEmpty ? 'User' : _userName,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              _locationLabel.isEmpty
                                  ? _dateLabel
                                  : '$_dateLabel · $_locationLabel',
                              style: const TextStyle(color: Color(0xFF9CB0CB), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatusMetric(
                          title: 'Distance',
                          value: '${widget.distanceKm.toStringAsFixed(2)} km',
                        ),
                      ),
                      Expanded(
                        child: _StatusMetric(title: 'Moving Time', value: widget.movingTime),
                      ),
                      Expanded(
                        child: _StatusMetric(
                          title: 'Speed',
                          value: '${widget.avgSpeedKmh.toStringAsFixed(1)} km/h',
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

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Color(0xFF9CB0CB), fontSize: 13)),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        height: 46,
        width: 46,
        decoration: const BoxDecoration(
            color: Color(0xE613151C), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _FallbackMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF9DB7D8));
    final roads = Paint()
      ..color = const Color(0xFF8DA2C2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    for (int i = 0; i < 10; i++) {
      final y = size.height * (i / 9);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 24), roads);
    }
    final route = Paint()
      ..color = const Color(0xFFFF5B00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final path = ui.Path()
      ..moveTo(size.width * 0.18, size.height * 0.10)
      ..lineTo(size.width * 0.62, size.height * 0.10)
      ..lineTo(size.width * 0.78, size.height * 0.66)
      ..lineTo(size.width * 0.58, size.height * 0.70)
      ..lineTo(size.width * 0.55, size.height * 0.46);
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
