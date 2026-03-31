import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dashboard_page.dart';

class ProfileViewPage extends StatefulWidget {
  const ProfileViewPage({super.key});

  @override
  State<ProfileViewPage> createState() => _ProfileViewPageState();
}

class _ProfileViewPageState extends State<ProfileViewPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    setState(() {
      _data = doc.data();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Profile'),
        backgroundColor: const Color(0xFF0C1730),
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A1226), Color(0xFF071833)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final d = _data ?? {};
    final name = d['name'] as String? ?? '';
    final age = d['age'] as String? ?? '';
    final weight = d['weight'] as String? ?? '';
    final height = d['height'] as String? ?? '';
    final goalWeight = d['goalWeight'] as String? ?? '';
    final stepsGoal = d['stepsGoal'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CircleAvatar(
            radius: 46,
            backgroundColor: Color(0xFFFF6200),
            child: Icon(Icons.person, color: Colors.white, size: 52),
          ),
          const SizedBox(height: 16),
          Text(
            name.isEmpty ? 'User' : name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Health Profile Overview',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFAAB3C3), fontSize: 16),
          ),
          const SizedBox(height: 16),
          _ProfileStatTile(label: 'Age', value: age.isEmpty ? '-' : '$age years', icon: Icons.cake_outlined),
          _ProfileStatTile(label: 'Current Weight', value: weight.isEmpty ? '-' : '$weight kg', icon: Icons.monitor_weight_outlined),
          _ProfileStatTile(label: 'Height', value: height.trim().isEmpty ? '-' : height, icon: Icons.height),
          _ProfileStatTile(label: 'Goal Weight', value: goalWeight.isEmpty ? '-' : '$goalWeight kg', icon: Icons.flag_outlined),
          _ProfileStatTile(label: 'Daily Steps Goal', value: stepsGoal.isEmpty ? '-' : '$stepsGoal steps', icon: Icons.directions_walk),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardPage()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6200),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Go to Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  const _ProfileStatTile({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF132642),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C3E5E)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF6200)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFFAAB3C3), fontSize: 15))),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
