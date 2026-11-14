// lib/models/collaborator.dart

class CollaboratorModel {
  final String collabId;
  final String tripId;
  final String? userId;
  final String? personId;
  final String? personName;
  final String? phoneNumber;
  final String? fullName;
  final String role; // OWNER, MEMBER, VIEWER
  final String status;
  final DateTime joinedAt;

  CollaboratorModel({
    required this.collabId,
    required this.tripId,
    this.userId,
    this.personId,
    this.personName,
    this.phoneNumber,
    this.fullName,
    this.role = 'MEMBER',
    this.status = 'ACCEPTED',
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
        'collabId': collabId,
        'tripId': tripId,
        'userId': userId,
        'personId': personId,
        'personName': personName,
        'phoneNumber': phoneNumber,
        'fullName': fullName,
        'role': role,
        'status': status,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory CollaboratorModel.fromJson(Map<String, dynamic> json) =>
      CollaboratorModel(
        collabId: json['collabId'] ?? '',
        tripId: json['tripId'] ?? '',
        userId: json['userId'],
        personId: json['personId'],
        personName: json['personName'],
        phoneNumber: json['phoneNumber'],
        fullName: json['fullName'],
        role: json['role'] ?? 'MEMBER',
        status: json['status'] ?? 'ACCEPTED',
        joinedAt: json['joinedAt'] != null
            ? DateTime.parse(json['joinedAt'])
            : DateTime.now(),
      );
}

