// lib/models/expense.dart
import 'enums.dart';

class ExpenseSplit {
  final String personId;
  final double amount;

  ExpenseSplit({required this.personId, required this.amount});

  Map<String, dynamic> toJson() => {
        'personId': personId,
        'amount': amount,
      };

  factory ExpenseSplit.fromJson(Map<String, dynamic> json) => ExpenseSplit(
        personId: json['personId'],
        amount: json['amount'].toDouble(),
      );
}

class Expense {
  final String id;
  String description;
  double amount;
  ExpenseCategory category;
  String paidById;
  DateTime date;
  List<String> splitAmongIds;

  Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.paidById,
    required this.date,
    required this.splitAmongIds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'amount': amount,
        'category': category.index,
        'paidById': paidById,
        'date': date.toIso8601String(),
        'splitAmongIds': splitAmongIds,
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'],
        description: json['description'],
        amount: json['amount'].toDouble(),
        category: ExpenseCategory.values[json['category']],
        paidById: json['paidById'],
        date: DateTime.parse(json['date']),
        splitAmongIds: List<String>.from(json['splitAmongIds']),
      );
}