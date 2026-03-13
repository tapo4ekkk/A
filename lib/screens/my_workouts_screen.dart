import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_screen.dart'; // экран входа/регистрации

class MyWorkoutsScreen extends StatelessWidget {
  const MyWorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Мои тренировки')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              const Text(
                'Войдите, чтобы увидеть свои записи',
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Войти'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои тренировки'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('userId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'active')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Ошибка загрузки записей:\n${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fitness_center_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 24),
                  const Text(
                    'У вас пока нет активных записей',
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text('Запишитесь на занятие в разделе "Запись"'),
                ],
              ),
            );
          }

          final bookings = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            itemBuilder: (context, index) {
              final bookingDoc = bookings[index];
              final bookingData = bookingDoc.data() as Map<String, dynamic>;
              final classId = bookingData['classId'] as String?;

              if (classId == null) {
                return const ListTile(title: Text('Ошибка: ID занятия отсутствует'));
              }

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('timetable').doc(classId).get(),
                builder: (context, classSnapshot) {
                  if (classSnapshot.connectionState == ConnectionState.waiting) {
                    return const ListTile(title: Text('Загрузка занятия...'));
                  }

                  if (!classSnapshot.hasData || !classSnapshot.data!.exists) {
                    return const ListTile(title: Text('Занятие удалено'));
                  }

                  final classData = classSnapshot.data!.data() as Map<String, dynamic>;
                  final title = classData['title'] as String? ?? 'Занятие';
                  final day = classData['day'] as String? ?? '—';
                  final time = classData['time'] as String? ?? '—';
                  final trainer = classData['trainer'] as String? ?? '—';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.indigo,
                        child: Icon(Icons.fitness_center, color: Colors.white),
                      ),
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('$day • $time • Тренер: $trainer'),
                      trailing: IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        tooltip: 'Отменить запись',
                        onPressed: () => _cancelBooking(
                          context: context,
                          bookingDoc: bookingDoc,
                          classId: classId,
                          bookingData: bookingData,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _cancelBooking({
    required BuildContext context,
    required DocumentSnapshot bookingDoc,
    required String classId,
    required Map<String, dynamic> bookingData,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить запись?'),
        content: const Text('Место освободится для других участников.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final bookingRef = bookingDoc.reference;

      print('Отмена: booking=${bookingDoc.id}, class=$classId');

      if (Platform.isWindows) {
        // Windows: без транзакции — последовательные операции
        print('Windows → без транзакции');

        final classRef = FirebaseFirestore.instance.collection('timetable').doc(classId);
        final classDoc = await classRef.get();

        if (!classDoc.exists) throw 'Занятие не найдено';

        final current = (classDoc.data()?['currentParticipants'] as num?) ?? 0;

        if (current > 0) {
          await classRef.update({'currentParticipants': current - 1});
          print('Уменьшено: $current → ${current - 1}');
        }

        await bookingRef.update({'status': 'cancelled'});
        print('Статус → cancelled');
      } else {
        // Мобильные / web / другие десктопы — с транзакцией
        print('Не Windows → транзакция');

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final bookingSnap = await transaction.get(bookingRef);
          if (!bookingSnap.exists) throw 'Запись не найдена';

          final classRef = FirebaseFirestore.instance.collection('timetable').doc(classId);
          final classSnap = await transaction.get(classRef);
          if (!classSnap.exists) throw 'Занятие не найдено';

          final current = (classSnap.data()?['currentParticipants'] as num?) ?? 0;
          if (current > 0) {
            transaction.update(classRef, {'currentParticipants': current - 1});
          }

          transaction.update(bookingRef, {'status': 'cancelled'});
        });
        print('Транзакция OK');
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запись успешно отменена'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stack) {
      print('Ошибка отмены: $e');
      print('Stack: $stack');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось отменить:\n$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}