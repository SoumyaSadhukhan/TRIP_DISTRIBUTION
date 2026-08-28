// lib/models/trip.dart
import 'package:trip_split/models/person.dart';

import 'group.dart';
import 'expense.dart';

class Trip {
  final String id;
  String? userId;
  bool isOwner;
  String name;
  String? description;
  DateTime createdAt;
  List<Group> groups;
  List<Expense> expenses;

  Trip({
    required this.id,
    this.userId,
    this.isOwner = true,
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
        'userId': userId,
        'isOwner': isOwner,
        'name': name,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'groups': groups.map((e) => e.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
      };

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'],
        userId: json['userId'],
        isOwner: json['isOwner'] == true,
        name: json['name'],
        description: json['description'],
        createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
        groups: (json['groups'] as List).map((e) => Group.fromJson(e)).toList(),
        expenses: (json['expenses'] as List).map((e) => Expense.fromJson(e)).toList(),
      );
}