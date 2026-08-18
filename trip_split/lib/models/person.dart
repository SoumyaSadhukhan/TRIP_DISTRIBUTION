// lib/models/person.dart
import 'enums.dart';

class Person {
  final String id;
  String name;
  DietType dietType;
  double paidAmount;
  double owedAmount;
  double balance;

  Person({
    required this.id,
    required this.name,
    required this.dietType,
    this.paidAmount = 0.0,
    this.owedAmount = 0.0,
    this.balance = 0.0,
  });

  Person copyWith({
    String? name,
    DietType? dietType,
    double? paidAmount,
    double? owedAmount,
    double? balance,
  }) {
    return Person(
      id: id,
      name: name ?? this.name,
      dietType: dietType ?? this.dietType,
      paidAmount: paidAmount ?? this.paidAmount,
      owedAmount: owedAmount ?? this.owedAmount,
      balance: balance ?? this.balance,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dietType': dietType.index,
        'paidAmount': paidAmount,
        'owedAmount': owedAmount,
        'balance': balance,
      };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'],
        name: json['name'],
        dietType: DietType.values[json['dietType']],
        paidAmount: json['paidAmount']?.toDouble() ?? 0.0,
        owedAmount: json['owedAmount']?.toDouble() ?? 0.0,
        balance: json['balance']?.toDouble() ?? 0.0,
      );
}