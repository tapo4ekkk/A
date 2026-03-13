// lib/screens/subscriptions_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitness/models/subscription.dart'; // предполагается, что модель лежит здесь

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Войдите в аккаунт")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Абонементы')),
      body: Column(
        children: [
          // Текущие активные абонементы
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('subscriptions')
                  .where('status', isEqualTo: 'active')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Нет активных абонементов'));
                }

                final subs = snapshot.data!.docs
                    .map((doc) => Subscription.fromFirestore(doc))
                    .toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: subs.length,
                  itemBuilder: (ctx, i) {
                    final s = subs[i];
                    String title;
                    if (s.type == 'visits') {
                      title = '${s.visitsRemaining ?? 0} из ${s.visitsTotal ?? 0} посещений';
                    } else {
                      final start = s.startDate != null
                          ? DateTime(s.startDate!.year, s.startDate!.month, s.startDate!.day)
                              .toString()
                              .substring(0, 10)
                          : '—';
                      final end = s.endDate != null
                          ? DateTime(s.endDate!.year, s.endDate!.month, s.endDate!.day)
                              .toString()
                              .substring(0, 10)
                          : '—';
                      title = '$start — $end';
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: ListTile(
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(s.comment ?? 'Без комментария'),
                        trailing: Text('${s.price} ₽', style: const TextStyle(fontSize: 16)),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Блок покупки
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TariffButton(
                  label: '8 посещений',
                  price: 1800,
                  onPressed: () => _buySubscription(
                    context,
                    type: 'visits',
                    visits: 8,
                    price: 1800,
                    comment: '8 посещений',
                  ),
                ),
                const SizedBox(height: 12),
                _TariffButton(
                  label: 'Безлимит 30 дней',
                  price: 3200,
                  onPressed: () => _buySubscription(
                    context,
                    type: 'period',
                    visits: null,
                    price: 3200,
                    comment: '30 дней безлимит',
                    days: 30,
                  ),
                ),
                const SizedBox(height: 12),
                _TariffButton(
                  label: '12 посещений',
                  price: 2500,
                  onPressed: () => _buySubscription(
                    context,
                    type: 'visits',
                    visits: 12,
                    price: 2500,
                    comment: '12 посещений',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

Future<void> _buySubscription(
  BuildContext context, {
  required String type,
  required int? visits,
  required num price,
  required String comment,
  int? days,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

  try {
    // 1. Читаем баланс (не в транзакции)
    final userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw 'Профиль пользователя не найден';
    }
    final currentBalance = (userSnap.data()?['balance'] as num?)?.toDouble() ?? 0.0;

    if (currentBalance < price) {
      throw 'Недостаточно средств. Требуется $price ₽, на балансе ${currentBalance.toStringAsFixed(0)} ₽';
    }

    // 2. Списываем деньги
    await userRef.update({
      'balance': FieldValue.increment(-price),
    });

    // 3. Добавляем абонемент
    final now = Timestamp.now();
    DateTime? endDate;
    if (days != null) {
      endDate = DateTime.now().add(Duration(days: days));
    }

    await userRef.collection('subscriptions').add({
      'type': type,
      'visitsTotal': visits,
      'visitsRemaining': visits,
      'startDate': type == 'period' ? now : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate) : null,
      'purchasedAt': now,
      'status': 'active',
      'price': price,
      'comment': comment,
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Абонемент «$comment» успешно приобретён'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;

    String errorMessage = e.toString()
        .replaceAll('Exception: ', '')
        .replaceAll('FirebaseException: ', '');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ошибка: $errorMessage'),
        backgroundColor: Colors.red,
      ),
    );
  }
}}

// Вспомогательный виджет для красивых кнопок
class _TariffButton extends StatelessWidget {
  final String label;
  final num price;
  final VoidCallback onPressed;

  const _TariffButton({
    required this.label,
    required this.price,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            '$price ₽',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}