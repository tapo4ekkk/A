import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Импортируем все экраны, которые у тебя уже есть
import 'schedule_screen.dart';
import 'booking_screen.dart';
import 'trainers_screen.dart'; // если переименовал trainers_tab.dart
import 'my_workouts_screen.dart'; // если создал
import 'auth_screen.dart'; // экран входа
import 'profile_screen.dart'; // если создал профиль
import 'admin_dashboard_screen.dart';
import 'dart:convert'; // Не забудьте добавить этот импорт в начало файла!
// lib/screens/home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';



class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoadingRole = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoadingRole = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      setState(() {
        _isAdmin = doc.exists && (doc.data()?['role'] == 'admin');
        _isLoadingRole = false;
      });

      // Создаём пользователя, если его нет
      if (!doc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'role': 'client',
          'email': user.email ?? 'unknown',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRole = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки роли: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fitness Center'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Новости / акции (заглушка, можно потом из Firestore)
            // 1. Новости и акции — на всю ширину экрана
            Container(
              width: double.infinity,                    // ← ключевой момент: растягивает контейнер полностью
              color: Colors.indigo[50],
              padding: const EdgeInsets.symmetric(vertical: 24),  // отступы только сверху/снизу
              margin: EdgeInsets.zero,                   // убираем любые внешние отступы
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок с небольшим отступом слева для красоты
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Новости и акции',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Горизонтальный скролл карточек
                  SizedBox(
                    height: 160,  // высота блока новостей — подбери под свой дизайн
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),  // отступы карточек от краёв
                      children: [
                        SizedBox(
                          width: 300,  // ширина одной карточки — можно менять
                          child: Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Скидка 20%',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('На любой абонемент до конца месяца!'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 300,
                          child: Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Пробное занятие бесплатно',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.indigo,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('Йога с новым тренером — приходите!'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Добавь ещё карточки при необходимости
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Расписание (короткий список)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Ближайшие занятия', style: Theme.of(context).textTheme.titleLarge),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('timetable').limit(5).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(16), child: Text('Занятий пока нет'));
                }

                final items = snapshot.data!.docs;

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final d = items[i].data() as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(d['title'] ?? 'Занятие'),
                      subtitle: Text('${d['time'] ?? ''} • ${d['trainer'] ?? ''}'),
                    );
                  },
                );
              },
            ),

            // Контакты
            Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.only(top: 32),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Контакты', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  ListTile(leading: Icon(Icons.phone), title: Text('+7 (999) 123-45-67')),
                  ListTile(leading: Icon(Icons.location_on), title: Text('г. Москва, ул. Ленина, 10')),
                  ListTile(leading: Icon(Icons.email), title: Text('info@fitness-center.ru')),
                  SizedBox(height: 16),
                  Text('Мы в соцсетях:', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.telegram, size: 32),
                      SizedBox(width: 16),
                      Icon(Icons.language, size: 32, color: Colors.blue), // VK заглушка
                      SizedBox(width: 16),
                      Icon(Icons.camera_alt, size: 32, color: Colors.pink), // Instagram заглушка
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// lib/screens/home_screen.dart (фрагмент с AppDrawer)



class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _buildGuestDrawer(context);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Drawer(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final role = userData?['role'] as String? ?? 'client';
        final name = userData?['name'] ?? user.email ?? 'Клиент';
        final photoUrl = userData?['photoURL'] as String?;

        return Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Заголовок с аватаром, именем и ролью
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      backgroundImage: photoUrl != null
                          ? _getImageProvider(photoUrl)
                          : null,
                      child: photoUrl == null
                          ? const Icon(
                              Icons.person,
                              size: 40,
                              color: Colors.indigo,
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      role == 'admin' ? 'Администратор' : 'Клиент',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Общие пункты (для всех авторизованных)
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Главная'),
                onTap: () {
                  Navigator.pop(context);
                  // Если уже на главной — ничего не делаем
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Расписание'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScheduleScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.book_online),
                title: const Text('Запись на занятие'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BookingScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Тренеры'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TrainersScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.fitness_center),
                title: const Text('Мои тренировки'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyWorkoutsScreen()),
                  );
                },
              ),

              const Divider(height: 32),

              // Профиль
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Профиль'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
              ),

              // Выход
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Выйти', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Вы вышли из аккаунта')),
                  );
                },
              ),

              // Блок только для админа
              if (role == 'admin') ...[
                const Divider(
                  color: Colors.redAccent,
                  thickness: 1.5,
                  indent: 16,
                  endIndent: 16,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Администрирование',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings, color: Colors.redAccent),
                  title: const Text('Админ-панель', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // Вспомогательная функция для получения ImageProvider из строки (base64 или url)
  ImageProvider? _getImageProvider(String url) {
    if (url.startsWith('data:image')) {
      try {
        final base64 = url.split(',').last;
        return MemoryImage(base64Decode(base64));
      } catch (e) {
        debugPrint('Ошибка декодирования base64 аватара: $e');
        return null;
      }
    }
    return NetworkImage(url);
  }

  // Drawer для гостей (не авторизован)
  Widget _buildGuestDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 40, color: Colors.indigo),
                ),
                SizedBox(height: 12),
                Text(
                  'Гость',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Главная'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text('Расписание'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScheduleScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Тренеры'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrainersScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('Войти / Зарегистрироваться'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuthScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────
// Вкладки (все StatelessWidget, без дубликатов)
// ────────────────────────────────────────────────

// --------------- TrainersTab ---------------
class TrainersTab extends StatelessWidget {
  const TrainersTab({super.key});

  String _safeToString(dynamic value) {
    if (value == null) return '—';
    if (value is String) return value;
    if (value is num) return value.toString();
    return value.toString(); // на всякий случай
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('trainers')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Ошибка: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Тренеры пока не добавлены'));
        }

        final trainers = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: trainers.length,
          itemBuilder: (context, index) {
            final data = trainers[index].data() as Map<String, dynamic>;

            final name = _safeToString(data['name']);
            final spec = _safeToString(data['specialization']);
            final exp = _safeToString(data['experience']);
            final photoUrl = data['photoUrl'] as String?;
            final description = _safeToString(data['description']);
            final phone = _safeToString(data['phone']);
            final rating = data['rating'] as num?;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) => DraggableScrollableSheet(
                      initialChildSize: 0.7,
                      minChildSize: 0.5,
                      maxChildSize: 0.95,
                      expand: false,
                      builder: (context, scrollController) => SingleChildScrollView(
                        controller: scrollController,
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: CircleAvatar(
                                  radius: 60,
                                  backgroundColor: Colors.grey[300],
                                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                  child: photoUrl == null ? const Icon(Icons.person, size: 60) : null,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                                  if (rating != null)
                                    Row(
                                      children: [
                                        const Icon(Icons.star, color: Colors.amber, size: 20),
                                        const SizedBox(width: 4),
                                        Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(spec, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text('Опыт: $exp', style: const TextStyle(fontSize: 15)),
                              const SizedBox(height: 16),
                              Text('О тренере', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(description, style: const TextStyle(fontSize: 15, height: 1.5)),
                              const SizedBox(height: 24),
                              if (phone != '—') ...[
                                Row(
                                  children: [
                                    const Icon(Icons.phone, color: Colors.green),
                                    const SizedBox(width: 12),
                                    Text(phone, style: const TextStyle(fontSize: 16)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              Align(
                                alignment: Alignment.center,
                                child: ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Закрыть'),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null ? const Icon(Icons.person) : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(spec, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                            Text('Опыт: $exp', style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
// --------------- MyWorkoutsTab ---------------
class MyWorkoutsTab extends StatelessWidget {
  const MyWorkoutsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('Здесь будут твои предстоящие тренировки'),
            Text('Пока записей нет', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class ScheduleTab extends StatelessWidget {
  const ScheduleTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('timetable')
          .snapshots(), // убрал orderBy, чтобы точно не падало, если полей нет
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Ошибка: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Расписание пустое'));
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return ListTile(
              title: Text(data['title']?.toString() ?? 'Без названия'),
              subtitle: Text(
                '${data['day']?.toString() ?? ''} • ${data['time']?.toString() ?? ''} • ${data['trainer']?.toString() ?? ''}',
              ),
            );
          },
        );
      },
    );
  }
}

class BookingTab extends StatelessWidget {
  const BookingTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('timetable')
          .orderBy('day')
          .orderBy('time')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Ошибка: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('Нет доступных занятий для записи'),
          );
        }

        final classes = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: classes.length,
          itemBuilder: (context, index) {
            final data = classes[index].data() as Map<String, dynamic>;
            final classId = classes[index].id;

            final title = data['title']?.toString() ?? 'Без названия';
            final day = data['day']?.toString() ?? '';
            final time = data['time']?.toString() ?? '';
            final trainer = data['trainer']?.toString() ?? '';
            final current = (data['currentParticipants'] as num?) ?? 0;
            final max = (data['maxParticipants'] as num?) ?? 999;

            final isFull = current >= max;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$day • $time • Тренер: $trainer',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Мест: $current / $max',
                          style: TextStyle(
                            color: isFull ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton(
                          onPressed: isFull
                              ? null
                              : () => _bookClass(context, classId, current, max),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFull ? Colors.grey : null,
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
    );
  }
}

Future<void> _bookClass(
  BuildContext context,
  String classId,
  num current,
  num max,
) async {
  var user = FirebaseAuth.instance.currentUser;

  // ← Вот этот блок, который ты спрашивал — вставлен именно сюда
  if (user == null) {
    // Если пользователь не авторизован — обрабатываем
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нужно войти в аккаунт')),
    );

    // Перенаправляем на экран входа
    final loggedIn = await Navigator.push<bool?>(
      context,
      MaterialPageRoute(builder: (context) => const AuthScreen()),
    );

    // Если не вошёл или отменил — выходим
    if (loggedIn != true) {
      return;
    }

    // Обновляем user после входа
    user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось войти')),
      );
      return;
    }
  }

  // Теперь user гарантированно не null — можно использовать uid без опасений
  final uid = user.uid;

  // Проверка на дубликат записи
  final existing = await FirebaseFirestore.instance
      .collection('bookings')
      .where('userId', isEqualTo: uid)
      .where('classId', isEqualTo: classId)
      .where('status', isEqualTo: 'active')
      .limit(1)
      .get();

  if (existing.docs.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Вы уже записаны на это занятие')),
    );
    return;
  }

  // Проверка мест
  if (current >= max) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Мест уже нет')),
    );
    return;
  }

  // Транзакция
  try {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final classRef = FirebaseFirestore.instance.collection('timetable').doc(classId);
      final classSnap = await transaction.get(classRef);

      if (!classSnap.exists) throw 'Занятие не найдено';

      final currentInDb = classSnap.data()?['currentParticipants'] as num? ?? 0;
      final maxInDb = classSnap.data()?['maxParticipants'] as num? ?? 999;

      final newCurrent = currentInDb + 1;

      if (newCurrent > maxInDb) throw 'Места закончились';

      transaction.update(classRef, {'currentParticipants': newCurrent});

      final bookingRef = FirebaseFirestore.instance.collection('bookings').doc();
      transaction.set(bookingRef, {
        'userId': uid,
        'classId': classId,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Вы успешно записаны!'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ошибка записи: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

class AdminTab extends StatelessWidget {
  const AdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(child: Text('Админ-панель (доступно только админам)')),
    );
  }
}