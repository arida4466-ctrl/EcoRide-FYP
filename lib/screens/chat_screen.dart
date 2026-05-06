import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:indriver_clone/ui/constants.dart';

class ChatScreen extends StatefulWidget {
  final String requestId;   // passenger uid (doc id in 'request' collection)
  final String otherName;   // display name of the other party
  final bool isDriver;      // true = driver sending, false = passenger sending

  const ChatScreen({
    Key? key,
    required this.requestId,
    required this.otherName,
    required this.isDriver,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _me   = FirebaseAuth.instance.currentUser!.uid;

  CollectionReference get _msgs => FirebaseFirestore.instance
      .collection('request')
      .doc(widget.requestId)
      .collection('messages');

  void _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    await _msgs.add({
      'text':      text,
      'senderId':  _me,
      'isDriver':  widget.isDriver,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: Row(children: [
          const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(widget.otherName,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ]),
      ),
      body: Column(
        children: [
          // ── Messages list ───────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _msgs
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No messages yet.\nSay hello! 👋',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                final docs = snap.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d    = docs[i].data() as Map<String, dynamic>;
                    final mine = d['senderId'] == _me;
                    return _Bubble(
                      text:  d['text'] ?? '',
                      mine:  mine,
                      time:  (d['timestamp'] as Timestamp?)?.toDate(),
                    );
                  },
                );
              },
            ),
          ),

          // ── Input bar ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: primaryColor,
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

class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  final DateTime? time;

  const _Bubble({required this.text, required this.mine, this.time});

  @override
  Widget build(BuildContext context) {
    final timeStr = time != null
        ? '${time!.hour.toString().padLeft(2, '0')}:'
        '${time!.minute.toString().padLeft(2, '0')}'
        : '';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? primaryColor : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(16),
            topRight:    const Radius.circular(16),
            bottomLeft:  Radius.circular(mine ? 16 : 0),
            bottomRight: Radius.circular(mine ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(text,
                style: TextStyle(
                    color: mine ? Colors.white : Colors.black87,
                    fontSize: 14)),
            const SizedBox(height: 4),
            Text(timeStr,
                style: TextStyle(
                    color: mine ? Colors.white70 : Colors.grey,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }
}