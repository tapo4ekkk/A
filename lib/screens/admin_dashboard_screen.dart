// lib/screens/admin_dashboard_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Админ-панель'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.schedule), text: 'Расписание'),
              Tab(icon: Icon(Icons.people), text: 'Тренеры'),
              Tab(icon: Icon(Icons.card_membership), text: 'Абонементы'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            TimetableAdminTab(),
            TrainersAdminTab(),
            SubscriptionsAdminTab(),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Tab 1: Расписание занятий
// ──────────────────────────────────────────────

class TimetableAdminTab extends StatelessWidget {
  const TimetableAdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showClassDialog(context),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('timetable').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Нет занятий в расписании'));
          }

          final classes = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: classes.length,
            itemBuilder: (context, index) {
              final doc = classes[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};

              final title = data['title'] as String? ?? 'Без названия';
              final date = data['date'] as Timestamp?;
              final formattedDate = date != null
                  ? DateFormat('dd.MM.yyyy (E)', 'ru').format(date.toDate())
                  : '—';
              final time = data['time'] as String? ?? '—';
              final trainerName = data['trainerName'] as String? ?? 'Тренер не выбран';
              final max = data['maxParticipants'] as int? ?? 0;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('$formattedDate • $time • Тренер: $trainerName • Макс: $max'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showClassDialog(context, id: doc.id, initialData: data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Удалить занятие?'),
                              content: const Text('Действие нельзя отменить.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await FirebaseFirestore.instance.collection('timetable').doc(doc.id).delete();
                          }
                        },
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

Future<void> _showClassDialog(
  BuildContext context, {
  String? id,
  Map<String, dynamic>? initialData,
}) async {
  final titleCtrl = TextEditingController(text: initialData?['title'] as String? ?? '');
  final timeCtrl = TextEditingController(text: initialData?['time'] as String? ?? '');
  final maxCtrl = TextEditingController(text: (initialData?['maxParticipants'] as int?)?.toString() ?? '20');

  DateTime? selectedDate;
  final initialDate = initialData?['date'] as Timestamp?;
  if (initialDate != null) {
    selectedDate = initialDate.toDate();
  }

  String? selectedTrainerId = initialData?['trainerId'] as String?;

  // Загружаем тренеров один раз
  final trainersSnapshot = await FirebaseFirestore.instance.collection('trainers').get();
  final trainers = trainersSnapshot.docs;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final isSaveEnabled = selectedDate != null &&
            selectedTrainerId != null &&
            titleCtrl.text.trim().isNotEmpty;

        return AlertDialog(
          title: Text(id == null ? 'Добавить занятие' : 'Редактировать занятие'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Название занятия'),
                ),
                const SizedBox(height: 16),

                // Дата
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Дата',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      selectedDate != null
                          ? DateFormat('dd.MM.yyyy (E)', 'ru').format(selectedDate!)
                          : 'Выберите дату',
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: timeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Время (например 18:00–19:30)',
                  ),
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: selectedTrainerId,
                  hint: const Text('Выберите тренера'),
                  isExpanded: true,
                  items: trainers.isEmpty
                      ? [const DropdownMenuItem(value: null, child: Text('Тренеры не добавлены'))]
                      : trainers.map((doc) {
                          final name = doc['name'] as String? ?? 'Без имени';
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(name),
                          );
                        }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedTrainerId = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: maxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Макс. участников'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: isSaveEnabled
                  ? () async {
                      // ────────────────────────────────
                      // Определяем имя тренера
                      String trainerNameToSave = 'Тренер не выбран';

                      if (selectedTrainerId != null && trainers.isNotEmpty) {
                        final matching = trainers.where((doc) => doc.id == selectedTrainerId).toList();
                        if (matching.isNotEmpty) {
                          trainerNameToSave = matching.first['name'] as String? ?? 'Без имени';
                        } else {
                          debugPrint('Тренер id=$selectedTrainerId не найден среди ${trainers.length}');
                        }
                      }

                      // ────────────────────────────────
                      // Парсим время окончания
                      final timeStr = timeCtrl.text.trim();
                      DateTime endDateTime;

                      if (timeStr.contains('–') || timeStr.contains('-')) {
                        final separator = timeStr.contains('–') ? '–' : '-';
                        final parts = timeStr.split(separator);
                        if (parts.length >= 2) {
                          final endPart = parts[1].trim();
                          final timeParts = endPart.split(':');
                          final hour = int.tryParse(timeParts[0]) ?? 23;
                          final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 59 : 59;

                          if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
                            endDateTime = DateTime(
                              selectedDate!.year,
                              selectedDate!.month,
                              selectedDate!.day,
                              hour,
                              minute,
                            );
                          } else {
                            // Некорректное время → дефолт
                            endDateTime = selectedDate!.add(const Duration(hours: 2));
                          }
                        } else {
                          endDateTime = selectedDate!.add(const Duration(hours: 2));
                        }
                      } else {
                        // Нет диапазона → +2 часа по умолчанию
                        endDateTime = selectedDate!.add(const Duration(hours: 2));
                      }

                      // ────────────────────────────────
                      // Формируем данные
                      final data = {
                        'title': titleCtrl.text.trim(),
                        'date': Timestamp.fromDate(selectedDate!),
                        'time': timeStr,
                        'trainerId': selectedTrainerId,
                        'trainerName': trainerNameToSave,
                        'maxParticipants': int.tryParse(maxCtrl.text) ?? 20,
                        'currentParticipants': initialData?['currentParticipants'] as int? ?? 0,
                        'endTimestamp': Timestamp.fromDate(endDateTime),
                      };

                      try {
                        if (id == null) {
                          await FirebaseFirestore.instance.collection('timetable').add(data);
                        } else {
                          await FirebaseFirestore.instance.collection('timetable').doc(id).update(data);
                        }

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Занятие сохранено')),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка сохранения: $e')),
                          );
                        }
                      }
                    }
                  : null,
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    ),
  );
}}

// ──────────────────────────────────────────────
// Tab 2: Тренеры (полный набор полей + удаление)
// ──────────────────────────────────────────────
class TrainersAdminTab extends StatelessWidget {
  const TrainersAdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTrainerDialog(context),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('trainers').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Тренеры не добавлены'));
          }

          final trainers = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: trainers.length,
            itemBuilder: (context, index) {
              final doc = trainers[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};

              final name = data['name'] as String? ?? 'Без имени';
              final specialty = data['specialty'] as String? ?? '—';
              final experience = data['experience'] as int? ?? 0;
              final phone = data['phone'] as String? ?? '—';
              final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
              final description = data['description'] as String? ?? 'Нет описания';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Специализация: $specialty'),
                      Text('Опыт: $experience лет'),
                      Text('Телефон: $phone'),
                      Text('Рейтинг: ${rating.toStringAsFixed(1)} ★'),
                      Text('Описание: ${description.length > 50 ? '${description.substring(0, 50)}...' : description}'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showTrainerDialog(context, id: doc.id, initialData: data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Удалить тренера?'),
                              content: const Text('Это действие нельзя отменить.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await FirebaseFirestore.instance.collection('trainers').doc(doc.id).delete();
                          }
                        },
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

  Future<void> _showTrainerDialog(
    BuildContext context, {
    String? id,
    Map<String, dynamic>? initialData,
  }) async {
    final nameCtrl = TextEditingController(text: initialData?['name'] as String? ?? '');
    final specialtyCtrl = TextEditingController(text: initialData?['specialty'] as String? ?? '');
    final descriptionCtrl = TextEditingController(text: initialData?['description'] as String? ?? '');
    final experienceCtrl = TextEditingController(text: (initialData?['experience'] as int?)?.toString() ?? '0');
    final phoneCtrl = TextEditingController(text: initialData?['phone'] as String? ?? '');
    final ratingCtrl = TextEditingController(text: (initialData?['rating'] as num?)?.toStringAsFixed(1) ?? '0.0');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(id == null ? 'Добавить тренера' : 'Редактировать тренера'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'ФИО')),
              TextField(controller: specialtyCtrl, decoration: const InputDecoration(labelText: 'Специализация')),
              TextField(
                controller: descriptionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Описание / о себе'),
              ),
              TextField(
                controller: experienceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Опыт (лет)'),
              ),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон'),
              ),
              TextField(
                controller: ratingCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Рейтинг (0.0–5.0)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || specialtyCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Заполните ФИО и специализацию')),
                );
                return;
              }

              final data = {
                'name': nameCtrl.text.trim(),
                'specialty': specialtyCtrl.text.trim(),
                'description': descriptionCtrl.text.trim(),
                'experience': int.tryParse(experienceCtrl.text) ?? 0,
                'phone': phoneCtrl.text.trim(),
                'rating': double.tryParse(ratingCtrl.text) ?? 0.0,
              };

              if (id == null) {
                await FirebaseFirestore.instance.collection('trainers').add(data);
              } else {
                await FirebaseFirestore.instance.collection('trainers').doc(id).update(data);
              }

              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Tab 3: Абонементы пользователей
// ──────────────────────────────────────────────
class SubscriptionsAdminTab extends StatelessWidget {
  const SubscriptionsAdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Нет пользователей'));
        }

        final users = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userDoc = users[index];
            final userData = userDoc.data() as Map<String, dynamic>? ?? {};
            final userId = userDoc.id;
            final userName = userData['name'] as String? ?? userData['email'] as String? ?? 'Без имени';

            return ExpansionTile(
              title: Text(userName),
              subtitle: Text('ID: $userId'),
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('subscriptions')
                      .snapshots(),
                  builder: (context, subSnapshot) {
                    if (subSnapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!subSnapshot.hasData || subSnapshot.data!.docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Нет абонементов'),
                      );
                    }

                    final subs = subSnapshot.data!.docs;

                    return Column(
                      children: subs.map((subDoc) {
                        final subData = subDoc.data() as Map<String, dynamic>? ?? {};
                        final subId = subDoc.id;
                        final comment = subData['comment'] as String? ?? 'Без комментария';
                        final status = subData['status'] as String? ?? 'unknown';
                        final type = subData['type'] as String? ?? '—';

                        return ListTile(
                          title: Text(comment),
                          subtitle: Text('Тип: $type • Статус: $status'),
                          trailing: status == 'active'
                              ? TextButton(
                                  onPressed: () async {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(userId)
                                        .collection('subscriptions')
                                        .doc(subId)
                                        .update({'status': 'frozen'});
                                  },
                                  child: const Text('Заморозить'),
                                )
                              : status == 'frozen'
                                  ? TextButton(
                                      onPressed: () async {
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(userId)
                                            .collection('subscriptions')
                                            .doc(subId)
                                            .update({'status': 'active'});
                                      },
                                      child: const Text('Разморозить'),
                                    )
                                  : const Text('—'),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}