// lib/screens/booking_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'auth_screen.dart';
import 'package:fitness/models/subscription.dart';

class BookingScreen extends StatelessWidget {
  const BookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Запись на занятие'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Фильтруем только будущие занятия
        stream: FirebaseFirestore.instance
            .collection('timetable')
            .where('endTimestamp', isGreaterThan: Timestamp.now())
            .orderBy('endTimestamp')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  'Ошибка загрузки:\n${snapshot.error.toString().replaceAll('Exception: ', '')}',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy, size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Нет доступных занятий для записи',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),
                    const Text('Добавьте занятия в админ-панели или подождите новых'),
                  ],
                ),
              ),
            );
          }

          final classes = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: classes.length,
            itemBuilder: (context, index) {
              final doc = classes[index];
              final data = doc.data() as Map<String, dynamic>;
              final classId = doc.id;
              final title = data['title'] as String? ?? 'Без названия';
              final dateTs = data['date'] as Timestamp?;
              String formattedDate = 'Дата не указана';
              if (dateTs != null) {
                formattedDate = DateFormat('dd.MM.yyyy (E)', 'ru').format(dateTs.toDate());
              }
              final time = data['time'] as String? ?? '—';
              final trainer = data['trainerName'] as String? ?? '—';
              final current = (data['currentParticipants'] as num?)?.toInt() ?? 0;
              final max = (data['maxParticipants'] as num?)?.toInt() ?? 999;
              final isFull = current >= max;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$formattedDate • $time • Тренер: $trainer',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Мест: $current / $max',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isFull ? Colors.red : Colors.green,
                              fontSize: 16,
                            ),
                          ),
                          ElevatedButton(
                            onPressed: isFull ? null : () => _bookClass(context, classId, current, max),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isFull ? Colors.grey : Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: Text(isFull ? 'Мест нет' : 'Записаться'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _bookClass(
    BuildContext context,
    String classId,
    int uiCurrent,
    int uiMax,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    // 0. Проверка авторизации
    if (user == null) {
      final loggedIn = await Navigator.push<bool?>(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
      if (loggedIn != true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Для записи нужно войти в аккаунт')),
          );
        }
        return;
      }
      final updatedUser = FirebaseAuth.instance.currentUser;
      if (updatedUser == null) return;
    }

    final currentUser = FirebaseAuth.instance.currentUser!;
    final userId = currentUser.uid;

    try {
      // 1. Проверяем, не записан ли уже (статус active/booked)
      final existingBooking = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: classId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (existingBooking.docs.isNotEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Вы уже записаны на это занятие'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 2. Проверяем актуальное количество мест (с сервера)
      final classRef = FirebaseFirestore.instance.collection('timetable').doc(classId);
      final classSnap = await classRef.get(const GetOptions(source: Source.server));

      if (!classSnap.exists) {
        throw Exception('Занятие не найдено');
      }

      final classData = classSnap.data()!;
      final currentInDb = (classData['currentParticipants'] as num?)?.toInt() ?? 0;
      final maxInDb = (classData['maxParticipants'] as num?)?.toInt() ?? 999;

      if (currentInDb >= maxInDb) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Места закончились'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // 3. Проверка наличия активного абонемента (без списания!)
      final subsQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subscriptions')
          .where('status', isEqualTo: 'active')
          .get();

      bool hasActiveSubscription = false;

      for (final subDoc in subsQuery.docs) {
        final data = subDoc.data();
        final type = data['type'] as String?;
        final remaining = data['visitsRemaining'] as int?;

        if (type == 'period' || (type == 'visits' && (remaining ?? 0) > 0)) {
          hasActiveSubscription = true;
          break;
        }
      }

      if (!hasActiveSubscription) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('У вас нет активного абонемента или закончились посещения'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // 4. Запись на занятие (без списания посещения!)
      try {
        // Перечитываем счётчик на случай race-condition
        final freshSnap = await classRef.get(const GetOptions(source: Source.server));
        final freshCurrent = (freshSnap.data()?['currentParticipants'] as num?)?.toInt() ?? 0;
        final freshMax = (freshSnap.data()?['maxParticipants'] as num?)?.toInt() ?? 999;

        if (freshCurrent >= freshMax) {
          throw Exception('Места закончились (конфликт)');
        }

        // Увеличиваем счётчик участников
        await classRef.update({
          'currentParticipants': FieldValue.increment(1),
        });

        // Создаём бронь
        await FirebaseFirestore.instance.collection('bookings').add({
          'userId': userId,
          'classId': classId,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'active',
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Вы успешно записаны!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Ошибка записи: $e');
        String message = 'Произошла ошибка при записи';
        if (e.toString().contains('Места закончились')) {
          message = 'Места закончились';
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Общая ошибка в _bookClass: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}