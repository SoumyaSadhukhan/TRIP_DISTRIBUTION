// lib/models/user.dart
import 'enums.dart';
import 'trip.dart';

class UserModel {
  final String id;
  final String username;
  final String phone;
  final String fullName;
  final String password;
  final String? token;
  final int dietType; // 0: vegetarian, 1: nonVegetarian, 2: nonVegAlcoholic
  final String dietName;
  final bool isBiometricEnabled;
  final DateTime createdAt;
  DateTime lastLoginAt;
  List<Trip> trips;

  UserModel({
    required this.id,
    String? username,
    String? phone,
    String? fullName,
    this.password = '',
    this.token,
    this.dietType = 0,
    String? dietName,
    this.isBiometricEnabled = false,
    required this.createdAt,
    required this.lastLoginAt,
    List<Trip>? trips,
  })  : username = username ?? phone ?? '',
        phone = phone ?? username ?? '',
        fullName = fullName ?? username ?? 'User',
        dietName = dietName ?? (dietType == 1 ? 'Non-Vegetarian' : (dietType == 2 ? 'Non-Veg + Alcohol' : 'Vegetarian')),
        trips = trips ?? [];

  DietType get dietEnum => DietType.values[dietType.clamp(0, DietType.values.length - 1)];

  UserModel copyWith({
    String? id,
    String? username,
    String? phone,
    String? fullName,
    String? password,
    String? token,
    int? dietType,
    String? dietName,
    bool? isBiometricEnabled,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    List<Trip>? trips,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      fullName: fullName ?? this.fullName,
      password: password ?? this.password,
      token: token ?? this.token,
      dietType: dietType ?? this.dietType,
      dietName: dietName ?? this.dietName,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      trips: trips ?? List.from(this.trips),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'phone': phone,
        'fullName': fullName,
        'password': password,
        'token': token,
        'dietType': dietType,
        'dietName': dietName,
        'isBiometricEnabled': isBiometricEnabled,
        'createdAt': createdAt.toIso8601String(),
        'lastLoginAt': lastLoginAt.toIso8601String(),
        'trips': trips.map((t) => t.toJson()).toList(),
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] ?? '',
        username: json['username'] ?? json['phone'] ?? '',
        phone: json['phone'] ?? json['username'] ?? '',
        fullName: json['fullName'] ?? json['username'] ?? 'User',
        password: json['password'] ?? '',
        token: json['token'],
        dietType: json['dietType'] ?? 0,
        dietName: json['dietName'],
        isBiometricEnabled: json['isBiometricEnabled'] == true || json['isBiometricEnabled'] == 1,
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
