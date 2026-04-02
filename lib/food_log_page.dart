import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ── Firestore helpers ─────────────────────────────────────────────────────────

class FoodLogService {
  static final _db = FirebaseFirestore.instance;

  /// Save a food analysis result to the user's food log
  static Future<void> saveEntry({
    required String uid,
    required String foodName,
    required String analysisText,
    required DateTime date,
  }) async {
    final dayKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await _db
        .collection('users')
        .doc(uid)
        .collection('food_log')
        .add({
      'foodName': foodName,
      'analysisText': analysisText,
      'dayKey': dayKey,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream all food entries for a specific day
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamForDay(
      String uid, String dayKey) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('food_log')
        .where('dayKey', isEqualTo: dayKey)
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  /// Stream all food entries for a user (for doctor view)
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamAll(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('food_log')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Save doctor feedback on a food log entry
  static Future<void> saveFeedback({
    required String patientUid,
    required String entryId,
    required String feedback,
    required String doctorName,
  }) async {
    await _db
        .collection('users')
        .doc(patientUid)
        .collection('food_log')
        .doc(entryId)
        .update({
      'doctorFeedback': feedback,
      'doctorName': doctorName,
      'feedbackAt': FieldValue.serverTimestamp(),
    });
  }
}

// ── Daily Food History Widget (used in calendar) ──────────────────────────────

class DailyFoodHistory extends StatelessWidget {
  const DailyFoodHistory({
    super.key,
    required this.uid,
    required this.dayKey,
    required this.date,
  });

  final String uid;
  final String dayKey;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FoodLogService.streamForDay(uid, dayKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🥗 Food Log',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  '${date.day}/${date.month}/${date.year}',
                  style: const TextStyle(
                      color: Color(0xFF8FA0BA), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141922),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A3342)),
                ),
                child: const Center(
                  child: Text(
                    'No food logged for this day.\nUse the Food & Nutrition AI to analyze and save meals.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF8FA0BA), fontSize: 13),
                  ),
                ),
              )
            else
              ...docs.map((doc) {
                final data = doc.data();
                final foodName =
                    data['foodName'] as String? ?? 'Food';
                final analysisText =
                    data['analysisText'] as String? ?? '';
                final feedback =
                    data['doctorFeedback'] as String?;
                final doctorName =
                    data['doctorName'] as String?;
                final ts = data['createdAt'] as Timestamp?;
                final time = ts != null
                    ? TimeOfDay.fromDateTime(ts.toDate())
                        .format(context)
                    : '';

                return _FoodLogCard(
                  foodName: foodName,
                  analysisText: analysisText,
                  time: time,
                  doctorFeedback: feedback,
                  doctorName: doctorName,
                );
              }),
          ],
        );
      },
    );
  }
}

// ── Food Log Card ─────────────────────────────────────────────────────────────

class _FoodLogCard extends StatefulWidget {
  const _FoodLogCard({
    required this.foodName,
    required this.analysisText,
    required this.time,
    this.doctorFeedback,
    this.doctorName,
  });

  final String foodName;
  final String analysisText;
  final String time;
  final String? doctorFeedback;
  final String? doctorName;

  @override
  State<_FoodLogCard> createState() => _FoodLogCardState();
}

class _FoodLogCardState extends State<_FoodLogCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141922),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3342)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20).withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('🥗',
                        style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.foodName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        if (widget.time.isNotEmpty)
                          Text(widget.time,
                              style: const TextStyle(
                                  color: Color(0xFF8FA0BA),
                                  fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xFF8FA0BA),
                  ),
                ],
              ),
            ),
          ),

          // Expanded analysis
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFF2A3342)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                widget.analysisText,
                style: const TextStyle(
                    color: Color(0xFFB2C1D7),
                    fontSize: 13,
                    height: 1.6),
              ),
            ),
          ],

          // Doctor feedback
          if (widget.doctorFeedback != null &&
              widget.doctorFeedback!.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFF2A3342)),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFF0F2A1A),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.medical_services,
                          color: Color(0xFF4CAF50), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Dr. ${widget.doctorName ?? "Doctor"} says:',
                        style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.doctorFeedback!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Doctor: Patient Food History + Feedback ───────────────────────────────────

class PatientFoodHistoryPage extends StatefulWidget {
  const PatientFoodHistoryPage({
    super.key,
    required this.patientUid,
    required this.patientName,
    required this.doctorName,
  });

  final String patientUid;
  final String patientName;
  final String doctorName;

  @override
  State<PatientFoodHistoryPage> createState() =>
      _PatientFoodHistoryPageState();
}

class _PatientFoodHistoryPageState
    extends State<PatientFoodHistoryPage> {
  final _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _giveFeedback(String entryId, String foodName) async {
    _feedbackController.clear();
    await showModalBottomSheet(
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
            Text(
              '💬 Feedback on "$foodName"',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _feedbackController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText:
                    'Write your dietary advice or feedback...',
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
              onPressed: () async {
                if (_feedbackController.text.trim().isEmpty) return;
                await FoodLogService.saveFeedback(
                  patientUid: widget.patientUid,
                  entryId: entryId,
                  feedback: _feedbackController.text.trim(),
                  doctorName: widget.doctorName,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Feedback sent! ✅',
                        style: TextStyle(color: Colors.white)),
                    backgroundColor: Color(0xFF1B5E20),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6200),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Send Feedback'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071327),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1730),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.patientName,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const Text('Food History',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF8FA0BA))),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FoodLogService.streamAll(widget.patientUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🥗', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text('No food logs yet.',
                      style: TextStyle(
                          color: Color(0xFF8FA0BA), fontSize: 16)),
                ],
              ),
            );
          }

          // Group by dayKey
          final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> grouped = {};
          for (final doc in docs) {
            final key = doc.data()['dayKey'] as String? ?? 'Unknown';
            grouped.putIfAbsent(key, () => []).add(doc);
          }
          final sortedKeys = grouped.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: sortedKeys.length,
            itemBuilder: (context, i) {
              final dayKey = sortedKeys[i];
              final entries = grouped[dayKey]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Day header
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2A44),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '📅 $dayKey',
                            style: const TextStyle(
                                color: Color(0xFFFF8B2D),
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${entries.length} meal(s)',
                            style: const TextStyle(
                                color: Color(0xFF8FA0BA),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  // Entries
                  ...entries.map((doc) {
                    final data = doc.data();
                    final foodName =
                        data['foodName'] as String? ?? 'Food';
                    final analysisText =
                        data['analysisText'] as String? ?? '';
                    final feedback =
                        data['doctorFeedback'] as String?;
                    final doctorName =
                        data['doctorName'] as String?;
                    final ts =
                        data['createdAt'] as Timestamp?;
                    final time = ts != null
                        ? TimeOfDay.fromDateTime(ts.toDate())
                            .format(context)
                        : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A44),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFF2A3A54)),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                const Text('🥗',
                                    style:
                                        TextStyle(fontSize: 22)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(foodName,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight:
                                                  FontWeight.w600)),
                                      if (time.isNotEmpty)
                                        Text(time,
                                            style: const TextStyle(
                                                color: Color(
                                                    0xFF8FA0BA),
                                                fontSize: 12)),
                                    ],
                                  ),
                                ),
                                // Feedback button
                                ElevatedButton.icon(
                                  onPressed: () => _giveFeedback(
                                      doc.id, foodName),
                                  icon: const Icon(
                                      Icons.rate_review_outlined,
                                      size: 14),
                                  label: Text(
                                    feedback != null
                                        ? 'Edit'
                                        : 'Feedback',
                                    style: const TextStyle(
                                        fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: feedback != null
                                        ? const Color(0xFF1B5E20)
                                        : const Color(0xFFFF6200),
                                    foregroundColor: Colors.white,
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize
                                            .shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Analysis preview
                          if (analysisText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  14, 0, 14, 10),
                              child: Text(
                                analysisText.length > 120
                                    ? '${analysisText.substring(0, 120)}...'
                                    : analysisText,
                                style: const TextStyle(
                                    color: Color(0xFF8FA0BA),
                                    fontSize: 12,
                                    height: 1.5),
                              ),
                            ),
                          // Existing feedback
                          if (feedback != null &&
                              feedback.isNotEmpty) ...[
                            const Divider(
                                height: 1,
                                color: Color(0xFF2A3A54)),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F2A1A),
                                borderRadius: BorderRadius.vertical(
                                    bottom: Radius.circular(14)),
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                      Icons.medical_services,
                                      color: Color(0xFF4CAF50),
                                      size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Dr. ${doctorName ?? "Doctor"}: $feedback',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
