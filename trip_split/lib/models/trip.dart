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

  factory Trip.fromJson(Map<String, dynamic> json) {
    final tripId = (json['id'] ?? json['tripId'] ?? '').toString();
    final rawGroups = json['groups'] as List? ?? [];
    final rawPersons = json['persons'] as List? ?? [];
    final allPersons = rawPersons.map((p) => Person.fromJson(p as Map<String, dynamic>)).toList();

    List<Group> groupsList = [];
    if (rawGroups.isNotEmpty) {
      groupsList = rawGroups.map((g) {
        final groupMap = g as Map<String, dynamic>;
        final group = Group.fromJson(groupMap);
        if (group.members.isEmpty && allPersons.isNotEmpty) {
          final gid = (groupMap['groupId'] ?? groupMap['id'] ?? '').toString();
          final matchingPersons = allPersons.where((p) => p.groupId == gid).toList();
          if (matchingPersons.isNotEmpty) {
            return group.copyWith(members: matchingPersons);
          }
        }
        return group;
      }).toList();
    }

    if (groupsList.isEmpty && allPersons.isNotEmpty) {
      groupsList = [
        Group(id: 'default', name: 'Members', members: allPersons)
      ];
    }

    final rawExpenses = json['expenses'] as List? ?? [];
    final expensesList = rawExpenses.map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();

    return Trip(
      id: tripId,
      userId: json['userId']?.toString(),
      isOwner: json['isOwner'] == true || json['role'] == 'OWNER',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
      groups: groupsList,
      expenses: expensesList,
    );
  }
}