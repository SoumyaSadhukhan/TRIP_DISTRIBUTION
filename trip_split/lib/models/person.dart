// lib/models/person.dart
import 'enums.dart';

class Person {
  final String id;
  final String? userId;
  final String? phone;
  String name;
  DietType dietType;
  double paidAmount;
  double owedAmount;
  double balance;

  Person({
    required this.id,
    this.userId,
    this.phone,
    required this.name,
    required this.dietType,
    this.paidAmount = 0.0,
    this.owedAmount = 0.0,
    this.balance = 0.0,
  });

  Person copyWith({
    String? id,
    String? userId,
    String? phone,
    String? name,
    DietType? dietType,
    double? paidAmount,
    double? owedAmount,
    double? balance,
  }) {
    return Person(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      dietType: dietType ?? this.dietType,
      paidAmount: paidAmount ?? this.paidAmount,
      owedAmount: owedAmount ?? this.owedAmount,
      balance: balance ?? this.balance,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'phone': phone,
        'name': name,
        'dietType': dietType.index,
        'paidAmount': paidAmount,
        'owedAmount': owedAmount,
        'balance': balance,
      };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'],
        userId: json['userId'],
        phone: json['phone'],
        name: json['name'],
        dietType: DietType.values[json['dietType'] ?? 0],
        paidAmount: json['paidAmount']?.toDouble() ?? 0.0,
        owedAmount: json['owedAmount']?.toDouble() ?? 0.0,
        balance: json['balance']?.toDouble() ?? 0.0,
      );
}