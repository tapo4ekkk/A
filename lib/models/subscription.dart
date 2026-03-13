import 'package:cloud_firestore/cloud_firestore.dart';

class Subscription {
  final String id;
  final String type; // "visits" или "period"
  final int? visitsTotal;
  final int? visitsRemaining;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime purchasedAt;
  final String status;
  final num price;
  final String? comment;

  Subscription({
    required this.id,
    required this.type,
    this.visitsTotal,
    this.visitsRemaining,
    this.startDate,
    this.endDate,
    required this.purchasedAt,
    required this.status,
    required this.price,
    this.comment,
  });

  factory Subscription.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Subscription(
      id: doc.id,
      type: data['type'] ?? 'unknown',
      visitsTotal: data['visitsTotal'],
      visitsRemaining: data['visitsRemaining'],
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      purchasedAt: (data['purchasedAt'] as Timestamp).toDate(),
      status: data['status'] ?? 'unknown',
      price: data['price'] ?? 0,
      comment: data['comment'],
    );
  }

  bool get isActive {
    if (status != 'active') return false;

    if (type == 'period' && endDate != null) {
      return DateTime.now().isBefore(endDate!);
    }
    if (type == 'visits' && visitsRemaining != null) {
      return visitsRemaining! > 0;
    }
    return true;
  }

  bool get canVisit => isActive && (type != 'visits' || (visitsRemaining ?? 0) > 0);
}