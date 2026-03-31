import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'doctor_home_page.dart';
import 'ui_components.dart';

class DoctorProfileSetupPage extends StatefulWidget {
  const DoctorProfileSetupPage({super.key});

  @override
  State<DoctorProfileSetupPage> createState() => _DoctorProfileSetupPageState();
}

class _DoctorProfileSetupPageState extends State<DoctorProfileSetupPage> {
  final _degreeController = TextEditingController();
  final _educationController = TextEditingController();
  final _qualificationController = TextEditingController();
  final _clinicLocationController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _degreeController.dispose();
    _educationController.dispose();
    _qualificationController.dispose();
    _clinicLocationController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (_degreeController.text.trim().isEmpty ||
        _qualificationController.text.trim().isEmpty ||
        _clinicLocationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please fill degree, qualification and clinic location.',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFFB71C1C),
      ));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .set({
        'degree': _degreeController.text.trim(),
        'education': _educationController.text.trim(),
        'qualification': _qualificationController.text.trim(),
        'clinicLocation': _clinicLocationController.text.trim(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DoctorHomePage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to save: $e',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1328), Color(0xFF071A36)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10203A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2C3E5E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppLogo(size: 52),
                      const SizedBox(height: 20),
                      const Text(
                        'Complete Your Profile',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Add your professional details so patients can find you',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFAAB3C3), fontSize: 14),
                      ),
                      const SizedBox(height: 28),
                      _field(
                        controller: _degreeController,
                        label: 'Degree *',
                        hint: 'e.g. MBBS, MD',
                        icon: Icons.school_outlined,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        controller: _educationController,
                        label: 'Education',
                        hint: 'e.g. Harvard Medical School',
                        icon: Icons.menu_book_outlined,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        controller: _qualificationController,
                        label: 'Qualification / Specialization *',
                        hint: 'e.g. Cardiologist, Sports Medicine',
                        icon: Icons.verified_outlined,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        controller: _clinicLocationController,
                        label: 'Clinic Location *',
                        hint: 'e.g. 123 Main St, New York',
                        icon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        text: _saving ? 'Saving...' : 'Save & Continue',
                        onPressed: _saving ? () {} : _saveAndContinue,
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DoctorHomePage()),
                            (_) => false,
                          ),
                          child: const Text(
                            'Skip for now',
                            style: TextStyle(color: Color(0xFF8FA0BA)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputLabel(text: label),
        const SizedBox(height: 8),
        AppTextField(controller: controller, hint: hint, icon: icon),
      ],
    );
  }
}
