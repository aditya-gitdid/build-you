import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DirectChatPage extends StatefulWidget {
  const DirectChatPage({
    super.key,
    required this.otherUid,
    required this.otherName,
    required this.isDoctor,
  });

  final String otherUid;
  final String otherName;
  final bool isDoctor; // true = current user is doctor, false = current user is patient

  @override
  State<DirectChatPage> createState() => _DirectChatPageState();
}

class _DirectChatPageState extends State<DirectChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _myName = '';

  // Chat room ID is always sorted so both sides get the same room
  late final String _roomId;

  @override
  void initState() {
    super.initState();
    final ids = [_myUid, widget.otherUid]..sort();
    _roomId = ids.join('_');
    _fetchMyName();
  }

  Future<void> _fetchMyName() async {
    final collection = widget.isDoctor ? 'doctors' : 'users';
    final doc = await FirebaseFirestore.instance
        .collection(collection)
        .doc(_myUid)
        .get();
    if (!mounted) return;
    final raw = doc.data()?['name'] as String? ?? '';
    setState(() => _myName = raw.trim().isEmpty ? 'Me' : raw.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await FirebaseFirestore.instance
        .collection('direct_chats')
        .doc(_roomId)
        .collection('messages')
        .add({
      'text': text,
      'senderUid': _myUid,
      'senderName': _myName,
      'isDoctor': widget.isDoctor,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Also update room metadata for notification purposes
    await FirebaseFirestore.instance
        .collection('direct_chats')
        .doc(_roomId)
        .set({
      'participants': [_myUid, widget.otherUid],
      'lastMessage': text,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071327),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1730),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFFF6200),
              child: Icon(
                widget.isDoctor ? Icons.person : Icons.medical_services,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isDoctor ? widget.otherName : 'Dr. ${widget.otherName}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  widget.isDoctor ? 'Patient' : 'Your Doctor',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF8FA0BA)),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('direct_chats')
                  .doc(_roomId)
                  .collection('messages')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            color: Color(0xFF3A4A64), size: 52),
                        const SizedBox(height: 12),
                        Text(
                          'Start a conversation with\n${widget.isDoctor ? widget.otherName : "Dr. ${widget.otherName}"}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFF8FA0BA), fontSize: 15),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final isMe = data['senderUid'] == _myUid;
                    final name = data['senderName'] as String? ?? '';
                    final text = data['text'] as String? ?? '';
                    final ts = data['createdAt'] as Timestamp?;
                    final time = ts != null
                        ? TimeOfDay.fromDateTime(ts.toDate()).format(context)
                        : '';

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.72),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFFFF6200)
                              : const Color(0xFF1A2A44),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  data['isDoctor'] == true
                                      ? 'Dr. $name'
                                      : name,
                                  style: const TextStyle(
                                      color: Color(0xFFFF8B2D),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            Text(
                              text,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              time,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.55),
                                  fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            color: const Color(0xFF0C1730),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle:
                          const TextStyle(color: Color(0xFF8FA0BA)),
                      filled: true,
                      fillColor: const Color(0xFF1A2A44),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF6200),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
