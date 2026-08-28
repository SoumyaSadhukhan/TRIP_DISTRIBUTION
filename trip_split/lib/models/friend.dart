// lib/models/friend.dart
import 'enums.dart';

class FriendModel {
  final String id;
  final String userId;
  final String? friendUserId;
  final String phone;
  final String name;
  final int dietType;
  final String dietName;
  final String status;
  final DateTime? createdAt;

  FriendModel({
    required this.id,
    required this.userId,
    this.friendUserId,
    required this.phone,
    required this.name,
    this.dietType = 0,
    String? dietName,
    this.status = 'CONNECTED',
    this.createdAt,
  }) : dietName = dietName ?? (dietType == 1 ? 'Non-Vegetarian' : (dietType == 2 ? 'Non-Veg + Alcohol' : 'Vegetarian'));

  DietType get dietEnum => DietType.values[dietType.clamp(0, DietType.values.length - 1)];

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'friendUserId': friendUserId,
        'phone': phone,
        'name': name,
        'dietType': dietType,
        'dietName': dietName,
        'status': status,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory FriendModel.fromJson(Map<String, dynamic> json) => FriendModel(
        id: json['id'] ?? '',
        userId: json['userId'] ?? '',
        friendUserId: json['friendUserId'],
        phone: json['phone'] ?? '',
        name: json['name'] ?? 'Friend',
        dietType: json['dietType'] ?? 0,
        dietName: json['dietName'],
        status: json['status'] ?? 'CONNECTED',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
      );
}
