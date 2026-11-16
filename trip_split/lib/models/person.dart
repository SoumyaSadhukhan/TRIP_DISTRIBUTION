// lib/models/person.dart
import 'enums.dart';

class Person {
  final String id;
  final String? groupId;
  final String? userId;
  final String? phone;
  String name;
  DietType dietType;
  double paidAmount;
  double owedAmount;
  double balance;

  Person({
    required this.id,
    this.groupId,
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
    String? groupId,
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
      groupId: groupId ?? this.groupId,
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
        'groupId': groupId,
        'userId': userId,
        'phone': phone,
        'name': name,
        'dietType': dietType.index,
        'paidAmount': paidAmount,
        'owedAmount': owedAmount,
        'balance': balance,
      };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: (json['id'] ?? json['personId'] ?? '').toString(),
        groupId: json['groupId']?.toString(),
        userId: json['userId']?.toString(),
        phone: json['phone']?.toString() ?? json['phoneNumber']?.toString(),
        name: json['name']?.toString() ?? '',
        dietType: DietType.values[((json['dietType'] is int ? json['dietType'] : int.tryParse(json['dietType']?.toString() ?? '0')) ?? 0).clamp(0, DietType.values.length - 1)],
        paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0.0,
        owedAmount: (json['owedAmount'] as num?)?.toDouble() ?? 0.0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      );
}