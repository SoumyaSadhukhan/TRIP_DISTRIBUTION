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

  factory Expense.fromJson(Map<String, dynamic> json) {
    List<String> splits = [];
    if (json['splitAmongIds'] != null) {
      splits = List<String>.from(json['splitAmongIds']);
    } else if (json['splits'] is List) {
      splits = (json['splits'] as List)
          .map((s) => (s['personId'] ?? s['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }

    final catVal = json['category'] ?? json['categoryIndex'];
    final catIndex = (catVal is int ? catVal : (int.tryParse(catVal?.toString() ?? '0') ?? 0))
        .clamp(0, ExpenseCategory.values.length - 1);

    return Expense(
      id: (json['id'] ?? json['expenseId'] ?? '').toString(),
      description: json['description']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      category: ExpenseCategory.values[catIndex],
      paidById: (json['paidById'] ?? json['paidByPersonId'] ?? '').toString(),
      date: json['date'] != null
          ? (DateTime.tryParse(json['date'].toString()) ?? DateTime.now())
          : (json['expenseDate'] != null ? (DateTime.tryParse(json['expenseDate'].toString()) ?? DateTime.now()) : DateTime.now()),
      splitAmongIds: splits,
    );
  }
}