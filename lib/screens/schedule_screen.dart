// lib/screens/schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // для форматирования даты

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Расписание занятий'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('timetable')
            .where('endTimestamp', isGreaterThan: Timestamp.now())
            .orderBy('endTimestamp')
            .snapshots(),
        builder: (context, snapshot) {
          // Ошибка загрузки
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Ошибка загрузки расписания:\n${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Идёт загрузка
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Нет данных
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy, size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Расписание пока пустое',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Занятия появятся после добавления в админ-панели',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          // Есть данные
          final classes = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: classes.length,
            itemBuilder: (context, index) {
              final data = classes[index].data() as Map<String, dynamic>;

              final title = data['title'] as String? ?? 'Без названия';
              final dateTs = data['date'] as Timestamp?;
              final time = data['time'] as String? ?? '—';
              final trainer = data['trainerName'] as String? ?? '—';
              final current = (data['currentParticipants'] as num?)?.toInt() ?? 0;
              final max = (data['maxParticipants'] as num?)?.toInt() ?? 999;

              // Форматируем дату красиво
              String formattedDate = 'Дата не указана';
              String dayOfWeek = '';
              if (dateTs != null) {
                final date = dateTs.toDate();
                formattedDate = DateFormat('dd.MM.yyyy').format(date);
                dayOfWeek = DateFormat('EEEE', 'ru').format(date); // Пн, Вт...
              }

              final isFull = current >= max;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    // Здесь можно открыть детали занятия или сразу записаться
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Выбрано: $title')),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Иконка слева
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: isFull ? Colors.red[100] : Colors.indigo[100],
                          child: Icon(
                            Icons.fitness_center,
                            color: isFull ? Colors.red : Colors.indigo,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Основная информация
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$formattedDate ($dayOfWeek) • $time',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Тренер: $trainer',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Количество мест справа
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$current / $max',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isFull ? Colors.red : Colors.green,
                              ),
                            ),
                            if (isFull)
                              const Text(
                                'Мест нет',
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}