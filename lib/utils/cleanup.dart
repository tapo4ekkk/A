import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';  // ← добавьте это

Future<void> cleanupOldClasses() async {
  final now = Timestamp.now();
  debugPrint('cleanupOldClasses запущена в ${DateTime.now()}');

  try {
    final query = await FirebaseFirestore.instance
        .collection('timetable')
        .where('endTimestamp', isLessThan: now)
        .get();

    debugPrint('Найдено прошедших занятий: ${query.docs.length}');

    if (query.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in query.docs) {
      final classData = doc.data();
      final classId = doc.id;
      debugPrint('Обрабатываем занятие: $classId → ${classData['title']}');

      // Архивируем (опционально)
      final archiveRef = FirebaseFirestore.instance.collection('class_archive').doc(classId);
      batch.set(archiveRef, {
        ...classData,
        'archivedAt': now,
      });

      // Удаляем из timetable
      batch.delete(doc.reference);

      // Находим bookings (убираем фильтр по status, чтобы не пропускать)
      final bookings = await FirebaseFirestore.instance
          .collection('bookings')
          .where('classId', isEqualTo: classId)
          .get();  // ← без .where('status'...) для теста

      debugPrint('Найдено записей на это занятие: ${bookings.docs.length}');

      for (final booking in bookings.docs) {
        final bookingData = booking.data();
        final userId = bookingData['userId'] as String?;
        final currentStatus = bookingData['status'] as String?;

        if (userId == null) {
          debugPrint('Пропуск: нет userId в booking ${booking.id}');
          continue;
        }

        debugPrint('Обрабатываем booking ${booking.id} для user $userId (status: $currentStatus)');

        // Меняем статус
        batch.update(booking.reference, {
          'status': 'completed',
          'completedAt': now,
        });

        // Списание посещения
        final subs = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('subscriptions')
            .where('type', isEqualTo: 'visits')           // ← поменяйте, если тип другой!
            .where('status', isEqualTo: 'active')
            .get();

        debugPrint('Найдено подходящих абонементов: ${subs.docs.length}');

        if (subs.docs.isNotEmpty) {
          final subDoc = subs.docs.first;
          final remaining = subDoc['visitsRemaining'] as int? ?? 0;
          debugPrint('Абонемент ${subDoc.id}: visitsRemaining = $remaining');

          if (remaining > 0) {
            batch.update(subDoc.reference, {
              'visitsRemaining': FieldValue.increment(-1),
            });
            debugPrint('Списано 1 посещение');
          } else {
            debugPrint('Посещения уже закончились — не списываем');
          }
        } else {
          debugPrint('Подходящих абонементов по визитам не найдено');
        }

        // Запись в историю
        final historyRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('visit_history')
            .doc();

        batch.set(historyRef, {
          'classId': classId,
          'title': classData['title'] ?? 'Занятие',
          'date': classData['date'],
          'time': classData['time'],
          'trainerName': classData['trainerName'] ?? '—',
          'completedAt': now,
          'createdAt': bookingData['timestamp'] ?? now,
        });

        debugPrint('Добавлена запись в visit_history');
      }
    }

    await batch.commit();
    debugPrint('Успешно обработано ${query.docs.length} занятий');
  } catch (e, stack) {
    debugPrint('Ошибка в cleanupOldClasses: $e');
    debugPrint('Stack: $stack');
  }
}