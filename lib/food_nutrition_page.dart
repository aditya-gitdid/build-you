import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// ─── Change this to your backend URL ──────────────────────────────────────────
// Local development:  'http://10.0.2.2:3000' (Android emulator)
//                     'http://localhost:3000'  (iOS simulator)
// Production:         'https://your-deployed-backend.com'
const String kBackendUrl = 'http://192.168.x.x:3000';
// ─────────────────────────────────────────────────────────────────────────────

class FoodNutritionPage extends StatefulWidget {
  const FoodNutritionPage({super.key});

  @override
  State<FoodNutritionPage> createState() => _FoodNutritionPageState();
}

class _FoodNutritionPageState extends State<FoodNutritionPage> {
  final ImagePicker _picker = ImagePicker();

  XFile? _imageFile;
  bool _isLoading = false;
  String _loadingText = 'Analyzing food...';
  _NutritionResult? _result;
  String? _errorMsg;

  // ── Image picking ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      setState(() {
        _imageFile = picked;
        _result = null;
        _errorMsg = null;
      });
    } catch (e) {
      _showError('Could not pick image: $e');
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2A44),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A4C68),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFFFF6200)),
              title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFFFF6200)),
              title: const Text('Choose from gallery', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Analysis ──────────────────────────────────────────────────────────────

  Future<void> _analyzeFood() async {
    if (_imageFile == null) return;

    setState(() {
      _isLoading = true;
      _loadingText = 'Detecting food items...';
      _errorMsg = null;
      _result = null;
    });

    try {
      final bytes = await File(_imageFile!.path).readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType = _imageFile!.mimeType ?? 'image/jpeg';

      setState(() => _loadingText = 'Calculating nutrition...');

      final response = await http
          .post(
            Uri.parse('$kBackendUrl/analyze-food'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'imageBase64': base64Image,
              'mimeType': mimeType,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['success'] != true) {
        throw Exception(json['error'] ?? 'Analysis failed');
      }

      setState(() {
        _result = _NutritionResult.fromJson(json['data'] as Map<String, dynamic>);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _reset() {
    setState(() {
      _imageFile = null;
      _result = null;
      _errorMsg = null;
      _isLoading = false;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1A2E),
        elevation: 0,
        title: const Text(
          'Food Nutrition Analyzer',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        leading: _result != null || _imageFile != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _reset,
              )
            : null,
      ),
      body: SafeArea(
        child: _isLoading
            ? _buildLoading()
            : _result != null
                ? _buildResult()
                : _imageFile != null
                    ? _buildPreview()
                    : _buildUpload(),
      ),
    );
  }

  // ── Upload screen ─────────────────────────────────────────────────────────

  Widget _buildUpload() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF1A2A44),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF314461)),
              ),
              child: const Icon(Icons.camera_enhance_outlined,
                  color: Color(0xFFFF6200), size: 48),
            ),
            const SizedBox(height: 24),
            const Text(
              'Analyze any food photo',
              style: TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Upload a photo of your meal and get instant nutritional breakdown — calories, protein, carbs, fiber, and more.',
              style: TextStyle(color: Color(0xFF9CB0CB), fontSize: 15, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showImageSourceSheet,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Upload food photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6200),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Supports any food from any cuisine or language',
              style: TextStyle(color: Color(0xFF6B7A94), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Preview screen ────────────────────────────────────────────────────────

  Widget _buildPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(_imageFile!.path),
              width: double.infinity,
              height: 280,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
          if (_errorMsg != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A0F0F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
              ),
              child: Text(
                _errorMsg!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _analyzeFood,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Analyze nutrition'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6200),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showImageSourceSheet,
              icon: const Icon(Icons.swap_horiz, color: Color(0xFFFF6200)),
              label: const Text('Use different photo',
                  style: TextStyle(color: Color(0xFFFF6200))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF314461)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading screen ────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              color: Color(0xFFFF6200),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _loadingText,
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI is scanning your meal...',
            style: TextStyle(color: Color(0xFF6B7A94), fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Result screen ─────────────────────────────────────────────────────────

  Widget _buildResult() {
    final r = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(_imageFile!.path),
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),

          // Detected items
          const Text('Detected items',
              style: TextStyle(
                  color: Color(0xFF9CB0CB),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: r.items
                .map((item) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A44),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF314461)),
                      ),
                      child: Text(item,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),

          // Calories card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2A44),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total calories',
                          style: TextStyle(
                              color: Color(0xFF9CB0CB), fontSize: 13)),
                      Text(
                        '${r.calories}',
                        style: const TextStyle(
                            color: Color(0xFFFF6200),
                            fontSize: 40,
                            fontWeight: FontWeight.w700),
                      ),
                      const Text('kcal',
                          style:
                              TextStyle(color: Color(0xFF6B7A94), fontSize: 13)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Meal size',
                        style:
                            TextStyle(color: Color(0xFF9CB0CB), fontSize: 13)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2A1A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF2E7D32)),
                      ),
                      child: Text(
                        r.mealSize,
                        style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Macros row
          Row(
            children: [
              Expanded(child: _MacroCard(label: 'Protein', value: r.protein, unit: 'g', color: const Color(0xFF378ADD))),
              const SizedBox(width: 8),
              Expanded(child: _MacroCard(label: 'Carbs', value: r.carbs, unit: 'g', color: const Color(0xFFFF6200))),
              const SizedBox(width: 8),
              Expanded(child: _MacroCard(label: 'Fat', value: r.fat, unit: 'g', color: const Color(0xFFF5C433))),
            ],
          ),
          const SizedBox(height: 10),

          // Detailed breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2A44),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Detailed breakdown',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                _BarRow(label: 'Fiber', value: r.fiber, maxValue: 30, color: const Color(0xFF639922)),
                _BarRow(label: 'Sugars', value: r.sugars, maxValue: 50, color: const Color(0xFFE24B4A)),
                _BarRow(label: 'Saturated fat', value: r.saturatedFat, maxValue: 20, color: const Color(0xFFBA7517)),
                _BarRow(label: 'Sodium', value: r.sodium, maxValue: 2300, color: const Color(0xFF7F77DD)),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Advice box
          if (r.advice.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1E35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1D4E8A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tips_and_updates_outlined,
                      color: Color(0xFF378ADD), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.advice,
                      style: const TextStyle(
                          color: Color(0xFFB2C1D7), fontSize: 14, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Analyze another
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Analyze another photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A2A44),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _MacroCard extends StatelessWidget {
  const _MacroCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final int value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A44),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$value$unit',
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label,
              style:
                  const TextStyle(color: Color(0xFF9CB0CB), fontSize: 13)),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (value / maxValue).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Color(0xFF9CB0CB), fontSize: 13)),
              ),
              Text(
                label == 'Sodium' ? '${value}mg' : '${value}g',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: const Color(0xFF2A3A54),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _NutritionResult {
  const _NutritionResult({
    required this.items,
    required this.mealSize,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.sugars,
    required this.saturatedFat,
    required this.sodium,
    required this.advice,
  });

  final List<String> items;
  final String mealSize;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final int fiber;
  final int sugars;
  final int saturatedFat;
  final int sodium;
  final String advice;

  factory _NutritionResult.fromJson(Map<String, dynamic> j) {
    int _i(dynamic v) => (v is num) ? v.round() : int.tryParse('$v') ?? 0;
    return _NutritionResult(
      items: (j['items'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
      mealSize: j['mealSize']?.toString() ?? 'medium',
      calories: _i(j['calories']),
      protein: _i(j['protein']),
      carbs: _i(j['carbs']),
      fat: _i(j['fat']),
      fiber: _i(j['fiber']),
      sugars: _i(j['sugars']),
      saturatedFat: _i(j['saturatedFat']),
      sodium: _i(j['sodium']),
      advice: j['advice']?.toString() ?? '',
    );
  }
}