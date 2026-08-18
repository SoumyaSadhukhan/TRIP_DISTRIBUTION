// lib/models/group.dart
import 'person.dart';

class Group {
  final String id;
  String name;
  List<Person> members;

  Group({
    required this.id,
    required this.name,
    required this.members,
  });

  Group copyWith({
    String? name,
    List<Person>? members,
  }) {
    return Group(
      id: id,
      name: name ?? this.name,
      members: members ?? this.members,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'members': members.map((e) => e.toJson()).toList(),
      };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'],
        name: json['name'],
        members: (json['members'] as List).map((e) => Person.fromJson(e)).toList(),
      );
}