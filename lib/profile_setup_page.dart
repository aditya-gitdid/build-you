import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_view_page.dart';
import 'ui_components.dart';

enum HeightUnit { cm, ftIn }

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key, this.initialName = ''});

  final String initialName;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  late final TextEditingController _nameController;
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightCmController = TextEditingController();
  final _heightFeetController = TextEditingController();
  final _heightInchesController = TextEditingController();
  final _goalWeightController = TextEditingController();
  final _stepsGoalController = TextEditingController(text: '10000');

  HeightUnit _heightUnit = HeightUnit.cm;
  bool _saving = false;

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final heightText = _heightUnit == HeightUnit.cm
        ? '${_heightCmController.text} cm'
        : '${_heightFeetController.text} ft ${_heightInchesController.text} in';
    setState(() => _saving = true);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'name': _nameController.text,
      'age': _ageController.text,
      'weight': _weightController.text,
      'height': heightText,
      'goalWeight': _goalWeightController.text,
      'stepsGoal': _stepsGoalController.text,
    });
    setState(() => _saving = false);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileViewPage()),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightCmController.dispose();
    _heightFeetController.dispose();
    _heightInchesController.dispose();
    _goalWeightController.dispose();
    _stepsGoalController.dispose();
    super.dispose();
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 700;
              final cardWidth = isTablet ? 620.0 : constraints.maxWidth * 0.94;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardWidth),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 24 : 16,
                        vertical: 22,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10203A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF2C3E5E)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AppLogo(size: 48),
                          const SizedBox(height: 18),
                          const Text(
                            'Complete Your Profile',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add your body stats and goals to personalize tracking',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFFAAB3C3), fontSize: 15),
                          ),
                          const SizedBox(height: 24),
                          const InputLabel(text: 'Name'),
                          const SizedBox(height: 8),
                          AppTextField(
                            controller: _nameController,
                            hint: 'Alex Johnson',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 16),
                          const InputLabel(text: 'Age'),
                          const SizedBox(height: 8),
                          AppTextField(
                            controller: _ageController,
                            hint: '28',
                            icon: Icons.calendar_today_outlined,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          const InputLabel(text: 'Weight (kg)'),
                          const SizedBox(height: 8),
                          AppTextField(
                            controller: _weightController,
                            hint: '74',
                            icon: Icons.monitor_weight_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const InputLabel(text: 'Height Unit'),
                          const SizedBox(height: 8),
                          SegmentedButton<HeightUnit>(
                            style: ButtonStyle(
                              side: WidgetStateProperty.all(
                                const BorderSide(color: Color(0xFF2C3E5E)),
                              ),
                              backgroundColor: WidgetStateProperty.resolveWith((states) {
                                return states.contains(WidgetState.selected)
                                    ? const Color(0xFFFF6200)
                                    : const Color(0xFF1A2A44);
                              }),
                              foregroundColor: WidgetStateProperty.resolveWith((states) {
                                return states.contains(WidgetState.selected)
                                    ? Colors.white
                                    : const Color(0xFFAAB3C3);
                              }),
                            ),
                            segments: const [
                              ButtonSegment(value: HeightUnit.cm, label: Text('CM')),
                              ButtonSegment(
                                value: HeightUnit.ftIn,
                                label: Text('Feet/Inches'),
                              ),
                            ],
                            selected: {_heightUnit},
                            onSelectionChanged: (newSelection) {
                              setState(() {
                                _heightUnit = newSelection.first;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          if (_heightUnit == HeightUnit.cm)
                            AppTextField(
                              controller: _heightCmController,
                              hint: '175',
                              icon: Icons.height,
                              keyboardType: TextInputType.number,
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: AppTextField(
                                    controller: _heightFeetController,
                                    hint: '5 ft',
                                    icon: Icons.height,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AppTextField(
                                    controller: _heightInchesController,
                                    hint: '9 in',
                                    icon: Icons.straighten,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          const InputLabel(text: 'Goal Weight (kg)'),
                          const SizedBox(height: 8),
                          AppTextField(
                            controller: _goalWeightController,
                            hint: '68',
                            icon: Icons.flag_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const InputLabel(text: 'Daily Steps Goal'),
                          const SizedBox(height: 8),
                          AppTextField(
                            controller: _stepsGoalController,
                            hint: '10000',
                            icon: Icons.directions_walk,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 24),
                          PrimaryButton(
                            text: _saving ? 'Saving...' : 'Save and Open Profile',
                            onPressed: _saving ? () {} : _saveProfile,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}