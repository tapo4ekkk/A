import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class VisitHistoryScreen extends StatelessWidget {
  const VisitHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Не авторизован')));

    return Scaffold(
      appBar: AppBar(title: const Text('История посещений')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('userId', isEqualTo: uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Нет посещений'));
          }

          final bookings = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: bookings.length,
            itemBuilder: (ctx, i) {
              final data = bookings[i].data() as Map<String, dynamic>;
              final classId = data['classId'] as String?;
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

              return ListTile(
                leading: const Icon(Icons.fitness_center),
                title: Text('Занятие $classId'),
                subtitle: Text(timestamp != null ? DateFormat('dd.MM.yyyy HH:mm').format(timestamp) : '—'),
                trailing: data['status'] == 'active'
                    ? const Chip(label: Text('Активно'), backgroundColor: Colors.green)
                    : const Chip(label: Text('Отменено'), backgroundColor: Colors.grey),
              );
            },
          );
        },
      ),
    );
  }
}