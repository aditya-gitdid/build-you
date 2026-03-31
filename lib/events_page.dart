import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'event_chat_page.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final _db = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _myName = '';
  bool _showPast = false;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  DateTime? _eventDate;
  TimeOfDay? _eventTime;
  String _eventType = 'Running';

  @override
  void initState() {
    super.initState();
    _fetchName();
  }

  Future<void> _fetchName() async {
    final doc = await _db.collection('users').doc(_uid).get();
    if (!mounted) return;
    setState(() => _myName = (doc.data()?['name'] as String? ?? 'User').trim());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  // ── Create event in Firestore ─────────────────────────────────────────────
  Future<void> _createEvent() async {
    if (_titleCtrl.text.trim().isEmpty || _eventDate == null || _eventTime == null) return;
    final dateLabel =
        '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}';
    final timeLabel = _eventTime!.format(context);

    final ref = await _db.collection('events').add({
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'location': _locationCtrl.text.trim().isEmpty
          ? 'Custom Location'
          : _locationCtrl.text.trim(),
      'type': _eventType,
      'dateLabel': dateLabel,
      'timeLabel': timeLabel,
      'creatorUid': _uid,
      'creatorName': _myName.isEmpty ? 'User' : _myName,
      'members': [_uid],
      'pendingRequests': [],
      'createdAt': FieldValue.serverTimestamp(),
      'isPast': false,
    });

    // Creator is automatically in the chat
    await ref.collection('messages').add({
      'text': '🎉 Event created! Welcome everyone.',
      'senderUid': 'system',
      'senderName': 'System',
      'createdAt': FieldValue.serverTimestamp(),
    });

    _titleCtrl.clear();
    _descCtrl.clear();
    _locationCtrl.clear();
    setState(() {
      _eventDate = null;
      _eventTime = null;
      _eventType = 'Running';
    });
    if (mounted) Navigator.pop(context);
  }

  // ── Send join request ─────────────────────────────────────────────────────
  Future<void> _requestJoin(String eventId) async {
    await _db.collection('events').doc(eventId).update({
      'pendingRequests': FieldValue.arrayUnion([
        {'uid': _uid, 'name': _myName.isEmpty ? 'User' : _myName}
      ]),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Join request sent! Waiting for approval 🕐'),
        backgroundColor: Color(0xFF1A2A44),
      ),
    );
  }

  // ── Leave event ───────────────────────────────────────────────────────────
  Future<void> _leaveEvent(String eventId) async {
    await _db.collection('events').doc(eventId).update({
      'members': FieldValue.arrayRemove([_uid]),
    });
  }

  // ── Accept a join request (only creator) ─────────────────────────────────
  Future<void> _acceptRequest(
      String eventId, String requesterUid, String requesterName, List pendingRequests) async {
    // Remove from pending, add to members
    final updatedPending = pendingRequests
        .where((r) => r['uid'] != requesterUid)
        .toList();
    await _db.collection('events').doc(eventId).update({
      'members': FieldValue.arrayUnion([requesterUid]),
      'pendingRequests': updatedPending,
    });
    // Welcome message in chat
    await _db
        .collection('events')
        .doc(eventId)
        .collection('messages')
        .add({
      'text': '✅ $requesterName has joined the event!',
      'senderUid': 'system',
      'senderName': 'System',
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$requesterName accepted! ✅'),
        backgroundColor: const Color(0xFF1B5E20),
      ),
    );
  }

  // ── Decline a join request ────────────────────────────────────────────────
  Future<void> _declineRequest(
      String eventId, String requesterUid, List pendingRequests) async {
    final updatedPending = pendingRequests
        .where((r) => r['uid'] != requesterUid)
        .toList();
    await _db.collection('events').doc(eventId).update({
      'pendingRequests': updatedPending,
    });
  }

  void _openCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111F37),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎉 Create Event',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _field(_titleCtrl, 'Event title *'),
                const SizedBox(height: 8),
                _field(_descCtrl, 'Description'),
                const SizedBox(height: 8),
                _field(_locationCtrl, 'Location'),
                const SizedBox(height: 8),
                // Type selector
                DropdownButtonFormField<String>(
                  value: _eventType,
                  dropdownColor: const Color(0xFF1A2A44),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1A2A44),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                  items: ['Running', 'Walking', 'Cycling', 'Swimming', 'Custom']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setSheet(() => _eventType = v ?? 'Running'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final p = await showDatePicker(
                            context: context,
                            initialDate: _eventDate ?? now,
                            firstDate: now,
                            lastDate: DateTime(now.year + 5),
                          );
                          if (p != null) setSheet(() => _eventDate = p);
                        },
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: Text(_eventDate == null
                            ? 'Date *'
                            : '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final p = await showTimePicker(
                            context: context,
                            initialTime: _eventTime ?? TimeOfDay.now(),
                          );
                          if (p != null) setSheet(() => _eventTime = p);
                        },
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(_eventTime == null
                            ? 'Time *'
                            : _eventTime!.format(context)),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _createEvent,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6200),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48)),
                  child: const Text('Create Event'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
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
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF5B00), Color(0xFF130E19)],
                begin: Alignment.topLeft,
                end: Alignment.topRight,
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🏅 Events',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700)),
                      Text('Join group activities & challenges',
                          style: TextStyle(
                              color: Color(0xFFFFCCA6), fontSize: 13)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _openCreateSheet,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1E2A),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          // Tab toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2A44),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF314461)),
              ),
              child: Row(
                children: [
                  Expanded(child: _chip('Upcoming', !_showPast, () => setState(() => _showPast = false))),
                  Expanded(child: _chip('Past Events', _showPast, () => setState(() => _showPast = true))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Events list
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('events')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                final filtered = docs.where((d) {
                  final isPast = d.data()['isPast'] as bool? ?? false;
                  return _showPast ? isPast : !isPast;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_busy,
                            size: 52, color: Color(0xFF3A4A64)),
                        const SizedBox(height: 12),
                        Text(
                          _showPast
                              ? 'No past events yet'
                              : 'No upcoming events.\nBe the first to create one! 🎉',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF8FA0BA)),
                        ),
                        if (!_showPast) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _openCreateSheet,
                            icon: const Icon(Icons.add),
                            label: const Text('Create Event'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6200),
                                foregroundColor: Colors.white),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final doc = filtered[i];
                    final data = doc.data();
                    return _EventFirestoreCard(
                      eventId: doc.id,
                      data: data,
                      myUid: _uid,
                      myName: _myName,
                      onRequestJoin: () => _requestJoin(doc.id),
                      onLeave: () => _leaveEvent(doc.id),
                      onAccept: (rUid, rName, pending) =>
                          _acceptRequest(doc.id, rUid, rName, pending),
                      onDecline: (rUid, pending) =>
                          _declineRequest(doc.id, rUid, pending),
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

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF7A00) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.black : const Color(0xFF8FA0BA),
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

// ── Single event card ─────────────────────────────────────────────────────────

class _EventFirestoreCard extends StatelessWidget {
  const _EventFirestoreCard({
    required this.eventId,
    required this.data,
    required this.myUid,
    required this.myName,
    required this.onRequestJoin,
    required this.onLeave,
    required this.onAccept,
    required this.onDecline,
  });

  final String eventId;
  final Map<String, dynamic> data;
  final String myUid;
  final String myName;
  final VoidCallback onRequestJoin;
  final VoidCallback onLeave;
  final void Function(String uid, String name, List pending) onAccept;
  final void Function(String uid, List pending) onDecline;

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'Event';
    final type = data['type'] as String? ?? 'Custom';
    final dateLabel = data['dateLabel'] as String? ?? '';
    final timeLabel = data['timeLabel'] as String? ?? '';
    final location = data['location'] as String? ?? '';
    final creatorName = data['creatorName'] as String? ?? 'Unknown';
    final creatorUid = data['creatorUid'] as String? ?? '';
    final description = data['description'] as String? ?? '';
    final members = List<String>.from(data['members'] ?? []);
    final pendingRequests = List<Map<String, dynamic>>.from(
        (data['pendingRequests'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

    final isMember = members.contains(myUid);
    final isCreator = creatorUid == myUid;
    final hasPendingRequest =
        pendingRequests.any((r) => r['uid'] == myUid);

    final accentColors = {
      'Running': const Color(0xFFFF6200),
      'Walking': const Color(0xFFFF8B2D),
      'Cycling': const Color(0xFF4FC3F7),
      'Swimming': const Color(0xFF26C6DA),
    };
    final accent = accentColors[type] ?? const Color(0xFFFF6200);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A44),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white24,
                  child: const Icon(Icons.event, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(type,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
                if (isCreator)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('👑 Creator',
                        style:
                            TextStyle(color: Colors.white, fontSize: 11)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date / time / location
                Row(children: [
                  const Icon(Icons.calendar_today,
                      color: Color(0xFF8FA0BA), size: 14),
                  const SizedBox(width: 5),
                  Text(dateLabel,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  const SizedBox(width: 12),
                  const Icon(Icons.access_time,
                      color: Color(0xFF8FA0BA), size: 14),
                  const SizedBox(width: 5),
                  Text(timeLabel,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ]),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        color: Color(0xFF8FA0BA), size: 14),
                    const SizedBox(width: 5),
                    Expanded(
                        child: Text(location,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13))),
                  ]),
                ],
                const Divider(height: 16, color: Color(0x333A4C68)),
                Row(children: [
                  const CircleAvatar(
                      radius: 12,
                      child: Icon(Icons.person, size: 12)),
                  const SizedBox(width: 6),
                  Text('Organized by $creatorName',
                      style: const TextStyle(
                          color: Color(0xFF8FA0BA), fontSize: 12)),
                ]),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(description,
                      style: const TextStyle(
                          color: Color(0xFFB2C1D7), fontSize: 13)),
                ],
                const SizedBox(height: 8),
                Text('👥 ${members.length} member(s)',
                    style: const TextStyle(
                        color: Color(0xFF9CB0CB), fontSize: 12)),

                // Pending requests (only creator sees)
                if (isCreator && pendingRequests.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1E35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF6200)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '🔔 ${pendingRequests.length} join request(s)',
                            style: const TextStyle(
                                color: Color(0xFFFF6200),
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(height: 8),
                        ...pendingRequests.map((r) {
                          final rUid = r['uid'] as String? ?? '';
                          final rName = r['name'] as String? ?? 'User';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                    radius: 14,
                                    child: Icon(Icons.person, size: 14)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(rName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13))),
                                TextButton(
                                  onPressed: () => onDecline(
                                      rUid, pendingRequests),
                                  child: const Text('Decline',
                                      style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12)),
                                ),
                                ElevatedButton(
                                  onPressed: () => onAccept(
                                      rUid, rName, pendingRequests),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF1B5E20),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    textStyle:
                                        const TextStyle(fontSize: 12),
                                  ),
                                  child: const Text('Accept'),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),
                // Action buttons
                Row(
                  children: [
                    if (isMember)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventChatPage(
                                eventId: eventId,
                                eventTitle: title,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline,
                              size: 16),
                          label: const Text('Open Chat'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A3A5C),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    if (isMember) const SizedBox(width: 8),
                    Expanded(
                      child: isMember
                          ? (isCreator
                              ? const SizedBox.shrink()
                              : ElevatedButton(
                                  onPressed: onLeave,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF465A78),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Leave'),
                                ))
                          : hasPendingRequest
                              ? ElevatedButton(
                                  onPressed: null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF2A3A54),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Requested ⏳'),
                                )
                              : ElevatedButton(
                                  onPressed: onRequestJoin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFFFF6200),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Request to Join'),
                                ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
