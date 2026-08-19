// lib/models/user.dart
import 'trip.dart';

class UserModel {
  final String id;
  final String username;
  final String password;
  final DateTime createdAt;
  DateTime lastLoginAt;
  List<Trip> trips;

  UserModel({
    required this.id,
    required this.username,
    required this.password,
    required this.createdAt,
    required this.lastLoginAt,
    List<Trip>? trips,
  }) : trips = trips ?? [];

  UserModel copyWith({
    String? id,
    String? username,
    String? password,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    List<Trip>? trips,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      trips: trips ?? List.from(this.trips),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'password': password,
        'createdAt': createdAt.toIso8601String(),
        'lastLoginAt': lastLoginAt.toIso8601String(),
        'trips': trips.map((t) => t.toJson()).toList(),
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] ?? '',
        username: json['username'] ?? '',
        password: json['password'] ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
        lastLoginAt: json['lastLoginAt'] != null
            ? DateTime.parse(json['lastLoginAt'])
            : DateTime.now(),
        trips: json['trips'] != null
            ? (json['trips'] as List)
                .map((e) => Trip.fromJson(e as Map<String, dynamic>))
                .toList()
            : [],
      );
}
