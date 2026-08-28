// lib/models/notification.dart
class NotificationModel {
  final String id;
  final String userId;
  final String? tripId;
  final String? tripName;
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
        'title': title,
        'message': message,
        'type': type,
        'amount': amount,
        'isRead': isRead,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
        id: json['id'] ?? '',
        userId: json['userId'] ?? '',
        tripId: json['tripId'],
        tripName: json['tripName'],
        title: json['title'] ?? 'Notification',
        message: json['message'] ?? '',
        type: json['type'] ?? 'EXPENSE_ADDED',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        isRead: json['isRead'] == true,
        createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      );
}
