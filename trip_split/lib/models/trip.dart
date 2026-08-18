// lib/models/trip.dart
import 'package:trip_split/models/person.dart';

import 'group.dart';
import 'expense.dart';

class Trip {
  final String id;
  String name;
  String? description;
  DateTime createdAt;
  List<Group> groups;
  List<Expense> expenses;

  Trip({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.groups,
    required this.expenses,
  });

  List<Person> get allMembers {
    final members = <Person>[];
    final seenIds = <String>{};
    for (var group in groups) {
      for (var member in group.members) {
        if (seenIds.add(member.id)) {
          members.add(member);
        }
      }
    }
    return members;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'groups': groups.map((e) => e.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
      };

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'],
        name: json['name'],
        description: json['description'],
        createdAt: DateTime.parse(json['createdAt']),
        groups: (json['groups'] as List).map((e) => Group.fromJson(e)).toList(),
        expenses: (json['expenses'] as List).map((e) => Expense.fromJson(e)).toList(),
      );
}