
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert'; // Не забудьте добавить этот импорт в начало файла!
import 'subscriptions_screen.dart';   // ← ваш экран абонементов
import 'visit_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  User? get user => _auth.currentUser;

  Map<String, dynamic>? _userData;
  String? _avatarUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final docRef = _firestore.collection('users').doc(user!.uid);
      final doc = await docRef.get();

      String? photoUrl = doc.data()?['photoURL'] as String?;

      // Удаляем заведомо битые / локальные / Windows-пути
      if (photoUrl != null &&
          (photoUrl.startsWith('file://') ||
              photoUrl.isEmpty ||
              photoUrl.contains('D:/') ||
              photoUrl.contains(r'\') ||
              !photoUrl.startsWith('http'))) {
        print("Обнаружен и удаляется некорректный путь photoURL: $photoUrl");
        await docRef.update({'photoURL': FieldValue.delete()});
        photoUrl = null;
      }

      // Проверяем существование файла только если это валидная https-ссылка
      if (photoUrl != null &&
          (photoUrl.startsWith('https://') || photoUrl.startsWith('http://'))) {
        try {
          // await _storage.refFromURL(photoUrl).getMetadata();
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('object-not-found') ||
              errorStr.contains('404') ||
              errorStr.contains('does not exist')) {
            print("Объект в Storage не найден → чистим ссылку: $photoUrl");
            await docRef.update({'photoURL': FieldValue.delete()});
            photoUrl = null;
          } else {
            print("Не удалось проверить metadata: $e");
          }
        }
      }

      if (!doc.exists) {
        // Создаём начальный документ пользователя
        await docRef.set({
          'fullName': user!.displayName ?? 'Пользователь',
          'email': user!.email,
          'balance': 0.0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // После создания перечитываем
        return _loadUserData();
      }

      if (mounted) {
        setState(() {
          _userData = doc.data();
          _avatarUrl = photoUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Ошибка при загрузке данных профиля: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки профиля: $e')),
        );
      }
    }
  }

  Future<void> _updateUserData(Map<String, dynamic> updates) async {
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user!.uid).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _loadUserData(); // перечитываем актуальные данные
    } catch (e) {
      print("Ошибка обновления данных: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    }
  }


Future<void> _pickAndUploadAvatar() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true, // Нам нужны байты
    );

    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;

    // 1. Получаем байты
    final bytes = result.files.single.bytes!;
    
    // Проверка на размер (Firestore лимит 1МБ, лучше ограничить до 500КБ)
    if (bytes.length > 800000) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Файл слишком большой. Выберите фото до 800 КБ')),
       );
       return;
    }

    // 2. Кодируем в Base64
    final base64String = base64Encode(bytes);
    final String dataUri = "data:image/jpeg;base64,$base64String";

    if (!mounted) return;
    setState(() => _isLoading = true);

    // 3. Сохраняем строку прямо в документ пользователя в Firestore
    await _firestore.collection('users').doc(user!.uid).update({
      'photoURL': dataUri,
    });

    if (mounted) {
      setState(() {
        _avatarUrl = dataUri;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото сохранено локально в БД'), backgroundColor: Colors.green),
      );
    }
  } catch (e) {
    setState(() => _isLoading = false);
    print("Ошибка сохранения в Base64: $e");
  }
}

ImageProvider? _getAvatarImage() {
  final url = _avatarUrl ?? _userData?['photoURL'] as String?;
  if (url == null || url.isEmpty) return null;

  // Если это обычная ссылка (например, от Google Auth)
  if (url.startsWith('http')) {
    return NetworkImage(url);
  }

  // Если это наша Base64 строка
  if (url.startsWith('data:image')) {
    try {
      // Отсекаем заголовок "data:image/jpeg;base64,"
      final base64Content = url.split(',').last;
      return MemoryImage(base64Decode(base64Content));
    } catch (e) {
      print("Ошибка декодирования Base64: $e");
      return null;
    }
  }

  return null;
}

  void _showEditDialog() {
    final nameCtrl = TextEditingController(text: _userData?['fullName'] ?? '');
    final phoneCtrl = TextEditingController(text: _userData?['phone'] ?? '');
    String? selectedGender = _userData?['gender'] ?? 'male';
    DateTime? pickedDate;

    final birthDateStr = _userData?['birthDate'] as String?;
    if (birthDateStr != null && birthDateStr.isNotEmpty) {
      pickedDate = DateTime.tryParse(birthDateStr);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext dialogContext, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Редактировать профиль'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'ФИО'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Телефон'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedGender,
                      decoration: const InputDecoration(labelText: 'Пол'),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('Мужской')),
                        DropdownMenuItem(value: 'female', child: Text('Женский')),
                        DropdownMenuItem(value: 'other', child: Text('Другой')),
                      ],
                      onChanged: (v) {
                        setDialogState(() {
                          selectedGender = v;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Дата рождения',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final DateTime? selected = await showDatePicker(
                          context: dialogContext,
                          initialDate: pickedDate ?? DateTime(2000),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                          helpText: 'Выберите дату рождения',
                          cancelText: 'Отмена',
                          confirmText: 'OK',
                        );
                        if (selected != null) {
                          setDialogState(() {
                            pickedDate = selected;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        child: Text(
                          pickedDate != null
                              ? DateFormat('dd.MM.yyyy').format(pickedDate!)
                              : 'Не указана',
                          style: TextStyle(
                            color: pickedDate != null
                                ? Colors.black
                                : Colors.grey[600],
                          ),
                        ),
                      ),
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
                  onPressed: () {
                    final updates = {
                      'fullName': nameCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'gender': selectedGender,
                      if (pickedDate != null)
                        'birthDate':
                            "${pickedDate!.year}-${pickedDate!.month.toString().padLeft(2, '0')}-${pickedDate!.day.toString().padLeft(2, '0')}",
                    };
                    _updateUserData(updates);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTopUpDialog() {
    final amountCtrl = TextEditingController(text: '1000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Пополнить баланс'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Сумма (₽)',
                prefixText: '₽ ',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            const Text('Для демо — отсканируйте QR-код в банковском приложении'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;
              Navigator.pop(ctx);
              _showQrPaymentDialog(amount);
            },
            child: const Text('Сгенерировать QR'),
          ),
        ],
      ),
    );
  }

  void _showQrPaymentDialog(double amount) {
    final qrData =
        'fitness-app:topup?user=${user!.uid}&amount=$amount&desc=Пополнение баланса';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Оплатите по QR-коду (демо)'),
        content: SizedBox(
          width: 280,
          height: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              QrImageView(
                data: qrData.isNotEmpty ? qrData : 'test-qr-demo',
                version: QrVersions.auto,
                size: 220.0,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF000000),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Сумма: ${amount.toStringAsFixed(0)} ₽',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Это демо-QR. В реальном приложении здесь был бы платёжный код.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
          TextButton(
            onPressed: () {
              _updateUserData({'balance': FieldValue.increment(amount)});
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Баланс пополнен на $amount ₽ (демо-режим)'),
                ),
              );
            },
            child: const Text('Имитировать оплату'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/auth'),
            child: const Text('Войти / Зарегистрироваться'),
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final data = _userData ?? {};
    final balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
    final birthDateStr = data['birthDate'] as String?;
    final birthDate = birthDateStr != null ? DateTime.tryParse(birthDateStr) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showEditDialog,
            tooltip: 'Редактировать данные',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Аватар + имя
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: _getAvatarImage(),
                        child: _getAvatarImage() == null
                            ? const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: IconButton(
                            icon: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: _pickAndUploadAvatar,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    data['fullName'] ?? user!.displayName ?? 'Пользователь',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    user!.email ?? 'Нет email',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Личные данные
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Личные данные',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const Divider(),
                    _InfoRow(icon: Icons.person, label: 'ФИО', value: data['fullName'] ?? '—'),
                    _InfoRow(
                      icon: Icons.cake,
                      label: 'Дата рождения',
                      value: birthDate != null
                          ? DateFormat('dd.MM.yyyy').format(birthDate)
                          : '—',
                    ),
                    _InfoRow(
                      icon: Icons.transgender,
                      label: 'Пол',
                      value: _genderToString(data['gender']),
                    ),
                    _InfoRow(icon: Icons.phone, label: 'Телефон', value: data['phone'] ?? '—'),
                    _InfoRow(icon: Icons.email, label: 'Email', value: user!.email ?? '—'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Баланс
            // Баланс (заменяем Card на StreamBuilder)
            Card(
              color: Colors.green[50],
              child: StreamBuilder<DocumentSnapshot>(
                stream: user != null
                    ? _firestore.collection('users').doc(user!.uid).snapshots()
                    : null,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Баланс недоступен'),
                    );
                  }

                  final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                  final balance = (data['balance'] as num?)?.toDouble() ?? 0.0;

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Баланс',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${balance.toStringAsFixed(0)} ₽',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add_circle),
                          label: const Text('Пополнить баланс'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: _showTopUpDialog,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Абонементы (заглушка)
            // Абонементы (было заглушкой — теперь реальные данные)
            Card(
              child: StreamBuilder<QuerySnapshot>(
                stream: user != null
                    ? _firestore
                        .collection('users')
                        .doc(user!.uid)
                        .collection('subscriptions')
                        .where('status', isEqualTo: 'active')
                        .snapshots()
                    : null,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const ListTile(
                      leading: Icon(Icons.card_membership, color: Colors.purple),
                      title: Text('Мои абонементы'),
                      subtitle: Text('Загрузка...'),
                    );
                  }

                  int activeCount = 0;
                  int remainingVisits = 0;

                  if (snapshot.hasData && snapshot.data != null) {
                    final docs = snapshot.data!.docs;
                    activeCount = docs.length;

                    for (final doc in docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      if (data['type'] == 'visits') {
                        final rem = (data['visitsRemaining'] as num?)?.toInt() ?? 0;
                        remainingVisits += rem;
                      }
                      // Если хотите суммировать только активные по периоду — можно добавить логику
                    }
                  }

                  String subtitleText;
                  if (activeCount == 0) {
                    subtitleText = 'Нет активных абонементов';
                  } else {
                    subtitleText = 'Активных: $activeCount';
                    if (remainingVisits > 0) {
                      subtitleText += ' • Осталось посещений: $remainingVisits';
                    }
                  }

                  return ListTile(
                    leading: const Icon(Icons.card_membership, color: Colors.purple),
                    title: const Text('Мои абонементы'),
                    subtitle: Text(subtitleText),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      if (user == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Необходимо войти в аккаунт')),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SubscriptionsScreen(),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // История посещений
            Card(
              child: ListTile(
                leading: const Icon(Icons.history, color: Colors.blue),
                title: const Text('История посещений'),
                subtitle: const Text('Последние тренировки и записи'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VisitHistoryScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),

            // Выход
            OutlinedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Выйти', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: Colors.red),
              ),
              onPressed: () async {
                await _auth.signOut();
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _genderToString(String? gender) {
    switch (gender) {
      case 'male':
        return 'Мужской';
      case 'female':
        return 'Женский';
      case 'other':
        return 'Другой';
      default:
        return '—';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[700], size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}