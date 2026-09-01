// lib/models/notification.dart
class NotificationModel {
  final String id;
  final String userId;
  final String? tripId;
  final String? tripName;
  final String? settlementId;
  final String title;
  final String message;
  final String type;
  final double amount;
  bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    this.tripId,
    this.tripName,
    this.settlementId,
    required this.title,
    required this.message,
    required this.type,
    this.amount = 0.0,
    this.isRead = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'tripId': tripId,
        'tripName': tripName,
        'settlementId': settlementId,
        'title': title,
        'message': message,
        'type': type,
        'amount': amount,
        'isRead': isRead,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
        id: json['id'] ?? json['notification_id'] ?? '',
        userId: json['userId'] ?? json['user_id'] ?? '',
        tripId: json['tripId'] ?? json['trip_id'],
        tripName: json['tripName'] ?? json['trip_name'],
        settlementId: json['settlementId'] ?? json['settlement_id'],
        title: json['title'] ?? 'Notification',
        message: json['message'] ?? '',
        type: json['type'] ?? 'EXPENSE_ADDED',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        isRead: json['isRead'] == true || json['is_read'] == 1 || json['is_read'] == true,
        createdAt: json['createdAt'] != null
            ? (DateTime.tryParse(json['createdAt']) ?? DateTime.now())
            : (json['created_at'] != null ? DateTime.tryParse(json['created_at']) ?? DateTime.now() : DateTime.now()),
      );
}

