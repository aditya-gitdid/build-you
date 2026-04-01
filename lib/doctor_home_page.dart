import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'activity_calendar_page.dart';
import 'activity_session.dart';
import 'direct_chat_page.dart';

class DoctorHomePage extends StatefulWidget {
  const DoctorHomePage({super.key});

  @override
  State<DoctorHomePage> createState() => _DoctorHomePageState();
}

class _DoctorHomePageState extends State<DoctorHomePage> {
  int _currentTab = 0;
  String _doctorName = '';

  @override
  void initState() {
    super.initState();
    _fetchDoctorName();
  }

  Future<void> _fetchDoctorName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('doctors').doc(uid).get();
    if (!mounted) return;
    setState(() {
      _doctorName = (doc.data()?['name'] as String? ?? '').trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071327),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _PatientsTab(doctorName: _doctorName),
          _DoctorSocialTab(),
          _DoctorEventsTab(),
          _DoctorProfileTab(doctorName: _doctorName),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        backgroundColor: Colors.black,
        selectedItemColor: const Color(0xFFFF6200),
        unselectedItemColor: const Color(0xFF97A6BE),
        type: BottomNavigationBarType.fixed,
        onTap: (value) => setState(() => _currentTab = value),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Social'),
          BottomNavigationBarItem(icon: Icon(Icons.event_outlined), label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

// ── HOME TAB ─────────────────────────────────────────────────────────────────

class _PatientsTab extends StatelessWidget {
  const _PatientsTab({required this.doctorName});
  final String doctorName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(22),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF5B00), Color(0xFF170E1A)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Welcome back,',
                    style: TextStyle(color: Color(0xFFFFC8A0), fontSize: 17)),
                const SizedBox(height: 2),
                Text(
                  doctorName.isEmpty ? 'Doctor' : 'Dr. $doctorName',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text('Your patients activity overview',
                    style: TextStyle(color: Color(0xFFFFCCA6), fontSize: 15)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Patients',
                style: TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent)),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final doctorUid = FirebaseAuth.instance.currentUser?.uid;
                final docs = (snapshot.data?.docs ?? [])
                    .where((d) => d.data()['assignedDoctorId'] == doctorUid)
                    .toList();
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No patients found.',
                        style: TextStyle(color: Color(0xFFAAB3C3), fontSize: 16)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final uid = docs[index].id;
                    final name = (data['name'] as String? ?? 'Unknown').trim();
                    final email = data['email'] as String? ?? '';
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openUserCalendar(context, uid, name),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2A44),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 24,
                              backgroundColor: Color(0xFFFF6200),
                              child: Icon(Icons.person, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600)),
                                  if (email.isNotEmpty)
                                    Text(email,
                                        style: const TextStyle(
                                            color: Color(0xFF8FA0BA), fontSize: 13)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Chat with $name',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DirectChatPage(
                                    otherUid: uid,
                                    otherName: name,
                                    isDoctor: true,
                                  ),
                                ),
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                color: Color(0xFFFF6200),
                              ),
                            ),
                            const Icon(Icons.calendar_month_outlined,
                                color: Color(0xFFFF6200)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUserCalendar(BuildContext context, String uid, String name) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('activities')
        .orderBy('completed_at', descending: true)
        .get();
    final sessions = snap.docs
        .map((doc) => ActivitySession.fromFirestore(doc.id, doc.data()))
        .toList();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityCalendarPage(sessions: sessions, userName: name),
      ),
    );
  }
}

// ── SOCIAL TAB ────────────────────────────────────────────────────────────────

class _DoctorSocialTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.topRight,
                  colors: [Color(0xFFFF5B00), Color(0xFF130E19)],
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Community',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text('Connect with patients & colleagues',
                      style: TextStyle(color: Color(0xFFFFCCA6), fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Icon(Icons.people_outline, color: Color(0xFF3A4A64), size: 64),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text('Social feed coming soon',
                  style: TextStyle(color: Color(0xFFAAB3C3), fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── EVENTS TAB ────────────────────────────────────────────────────────────────

class _DoctorEventsTab extends StatefulWidget {
  @override
  State<_DoctorEventsTab> createState() => _DoctorEventsTabState();
}

class _DoctorEventsTabState extends State<_DoctorEventsTab> {
  final List<_DoctorEvent> _events = [];
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime? _eventDate;
  TimeOfDay? _eventTime;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _eventTime = picked);
  }

  void _openCreateDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111F37),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Create Event',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _modalField(_titleController, 'Event title'),
                const SizedBox(height: 10),
                _modalField(_descController, 'Description'),
                const SizedBox(height: 10),
                _modalField(_locationController, 'Location'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _pickDate();
                          setModal(() {});
                        },
                        icon: const Icon(Icons.calendar_month),
                        label: Text(_eventDate == null
                            ? 'Select Date'
                            : '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _pickTime();
                          setModal(() {});
                        },
                        icon: const Icon(Icons.access_time),
                        label: Text(_eventTime == null
                            ? 'Select Time'
                            : _eventTime!.format(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6200)),
                  onPressed: () {
                    if (_titleController.text.trim().isEmpty ||
                        _eventDate == null ||
                        _eventTime == null) return;
                    setState(() {
                      _events.insert(
                        0,
                        _DoctorEvent(
                          title: _titleController.text.trim(),
                          description: _descController.text.trim(),
                          location: _locationController.text.trim().isEmpty
                              ? 'TBD'
                              : _locationController.text.trim(),
                          dateLabel:
                              '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}',
                          timeLabel: _eventTime!.format(context),
                        ),
                      );
                      _titleController.clear();
                      _descController.clear();
                      _locationController.clear();
                      _eventDate = null;
                      _eventTime = null;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Create Event',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modalField(TextEditingController c, String hint) => TextField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF8FA0BA)),
          filled: true,
          fillColor: const Color(0xFF1A2A44),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.topRight,
                colors: [Color(0xFFFF5B00), Color(0xFF130E19)],
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Events',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Manage your health events',
                          style:
                              TextStyle(color: Color(0xFFFFCCA6), fontSize: 15)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _openCreateDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1E2A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _events.isEmpty
                ? const Center(
                    child: Text('No events yet. Create one!',
                        style:
                            TextStyle(color: Color(0xFFAAB3C3), fontSize: 16)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: _events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _EventCard(event: _events[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DoctorEvent {
  const _DoctorEvent({
    required this.title,
    required this.description,
    required this.location,
    required this.dateLabel,
    required this.timeLabel,
  });
  final String title;
  final String description;
  final String location;
  final String dateLabel;
  final String timeLabel;
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final _DoctorEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A44),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF6200).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(event.description,
                style: const TextStyle(color: Color(0xFFB2C1D7), fontSize: 14)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today,
                  color: Color(0xFF8FA0BA), size: 14),
              const SizedBox(width: 4),
              Text(event.dateLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(width: 12),
              const Icon(Icons.access_time,
                  color: Color(0xFF8FA0BA), size: 14),
              const SizedBox(width: 4),
              Text(event.timeLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  color: Color(0xFF8FA0BA), size: 14),
              const SizedBox(width: 4),
              Text(event.location,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── PROFILE TAB ───────────────────────────────────────────────────────────────

class _DoctorProfileTab extends StatefulWidget {
  const _DoctorProfileTab({required this.doctorName});
  final String doctorName;

  @override
  State<_DoctorProfileTab> createState() => _DoctorProfileTabState();
}

class _DoctorProfileTabState extends State<_DoctorProfileTab> {
  final _degreeController = TextEditingController();
  final _educationController = TextEditingController();
  final _qualificationController = TextEditingController();
  final _clinicLocationController = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('doctors').doc(uid).get();
    final data = doc.data() ?? {};
    _degreeController.text = data['degree'] as String? ?? '';
    _educationController.text = data['education'] as String? ?? '';
    _qualificationController.text = data['qualification'] as String? ?? '';
    _clinicLocationController.text = data['clinicLocation'] as String? ?? '';
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    await FirebaseFirestore.instance.collection('doctors').doc(uid).update({
      'degree': _degreeController.text.trim(),
      'education': _educationController.text.trim(),
      'qualification': _qualificationController.text.trim(),
      'clinicLocation': _clinicLocationController.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile saved!', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF1B5E20),
      ),
    );
  }

  @override
  void dispose() {
    _degreeController.dispose();
    _educationController.dispose();
    _qualificationController.dispose();
    _clinicLocationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.topRight,
                  colors: [Color(0xFFFF5B00), Color(0xFF130E19)],
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Profile',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Avatar + name
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2A44),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 38,
                    backgroundColor: Color(0xFFFF6200),
                    child: Icon(Icons.medical_services,
                        color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.doctorName.isEmpty
                        ? 'Doctor'
                        : 'Dr. ${widget.doctorName}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(
                        color: Color(0xFF9CB0CB), fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Editable fields
            if (_loaded)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2A44),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Professional Details',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _profileField(
                        controller: _degreeController,
                        label: 'Degree',
                        hint: 'e.g. MBBS, MD',
                        icon: Icons.school_outlined),
                    const SizedBox(height: 12),
                    _profileField(
                        controller: _educationController,
                        label: 'Education',
                        hint: 'e.g. Harvard Medical School',
                        icon: Icons.menu_book_outlined),
                    const SizedBox(height: 12),
                    _profileField(
                        controller: _qualificationController,
                        label: 'Qualification',
                        hint: 'e.g. Cardiologist, Sports Medicine',
                        icon: Icons.verified_outlined),
                    const SizedBox(height: 12),
                    _profileField(
                        controller: _clinicLocationController,
                        label: 'Clinic Location',
                        hint: 'e.g. 123 Main St, New York',
                        icon: Icons.location_on_outlined),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6200),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _saving ? 'Saving...' : 'Save Profile',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _profileField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFFAAB3C3),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF4A5A74)),
            prefixIcon: Icon(icon, color: const Color(0xFF8FA0BA), size: 20),
            filled: true,
            fillColor: const Color(0xFF0F1E35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2A3A54)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2A3A54)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFFF6200)),
            ),
          ),
        ),
      ],
    );
  }
}
