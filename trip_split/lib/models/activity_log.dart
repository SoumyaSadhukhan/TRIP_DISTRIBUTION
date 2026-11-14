// lib/models/activity_log.dart

class ActivityLogModel {
  final String logId;
  final String? userId;
  final String? tripId;
  final String action;
  final String details;
  final DateTime timestamp;

  ActivityLogModel({
    required this.logId,
    this.userId,
    this.tripId,
    required this.action,
    required this.details,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'logId': logId,
        'userId': userId,
        'tripId': tripId,
        'action': action,
        'details': details,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ActivityLogModel.fromJson(Map<String, dynamic> json) =>
      ActivityLogModel(
        logId: json['logId'] ?? '',
        userId: json['userId'],
        tripId: json['tripId'],
        action: json['action'] ?? '',
        details: json['details'] ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'])
            : DateTime.now(),
      );
}

