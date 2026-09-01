// lib/models/settlement_proposal.dart

class SettlementProposal {
  final String settlementId;
  final String tripId;
  final String tripName;
  final String fromPersonId;
  final String fromPersonName;
  final String? fromPhone;
  final String toPersonId;
  final String toPersonName;
  final String? toPhone;
  final double amount;
  final String status;
  final String? createdByUserId;
  final DateTime settledAt;
  final bool isPayer;
  final bool isPayee;

  SettlementProposal({
    required this.settlementId,
    required this.tripId,
    required this.tripName,
    required this.fromPersonId,
    required this.fromPersonName,
    this.fromPhone,
    required this.toPersonId,
    required this.toPersonName,
    this.toPhone,
    required this.amount,
    required this.status,
    this.createdByUserId,
    required this.settledAt,
    this.isPayer = false,
    this.isPayee = false,
  });

  Map<String, dynamic> toJson() => {
        'settlementId': settlementId,
        'tripId': tripId,
        'tripName': tripName,
        'fromPersonId': fromPersonId,
        'fromPersonName': fromPersonName,
        'fromPhone': fromPhone,
        'toPersonId': toPersonId,
        'toPersonName': toPersonName,
        'toPhone': toPhone,
        'amount': amount,
        'status': status,
        'createdByUserId': createdByUserId,
        'settledAt': settledAt.toIso8601String(),
        'isPayer': isPayer,
        'isPayee': isPayee,
      };

  factory SettlementProposal.fromJson(Map<String, dynamic> json) => SettlementProposal(
        settlementId: json['settlementId'] ?? json['settlement_id'] ?? '',
        tripId: json['tripId'] ?? json['trip_id'] ?? '',
        tripName: json['tripName'] ?? json['trip_name'] ?? 'Trip',
        fromPersonId: json['fromPersonId'] ?? json['from_person_id'] ?? '',
        fromPersonName: json['fromPersonName'] ?? json['from_person_name'] ?? 'Member',
        fromPhone: json['fromPhone'] ?? json['from_phone'],
        toPersonId: json['toPersonId'] ?? json['to_person_id'] ?? '',
        toPersonName: json['toPersonName'] ?? json['to_person_name'] ?? 'Member',
        toPhone: json['toPhone'] ?? json['to_phone'],
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        status: json['status'] ?? 'PENDING',
        createdByUserId: json['createdByUserId'] ?? json['created_by_user_id'],
        settledAt: json['settledAt'] != null
            ? DateTime.tryParse(json['settledAt']) ?? DateTime.now()
            : (json['settled_at'] != null ? DateTime.tryParse(json['settled_at']) ?? DateTime.now() : DateTime.now()),
        isPayer: json['isPayer'] == true,
        isPayee: json['isPayee'] == true,
      );

  SettlementProposal copyWith({
    String? settlementId,
    String? tripId,
    String? tripName,
    String? fromPersonId,
    String? fromPersonName,
    String? fromPhone,
    String? toPersonId,
    String? toPersonName,
    String? toPhone,
    double? amount,
    String? status,
    String? createdByUserId,
    DateTime? settledAt,
    bool? isPayer,
    bool? isPayee,
  }) {
    return SettlementProposal(
      settlementId: settlementId ?? this.settlementId,
      tripId: tripId ?? this.tripId,
      tripName: tripName ?? this.tripName,
      fromPersonId: fromPersonId ?? this.fromPersonId,
      fromPersonName: fromPersonName ?? this.fromPersonName,
      fromPhone: fromPhone ?? this.fromPhone,
      toPersonId: toPersonId ?? this.toPersonId,
      toPersonName: toPersonName ?? this.toPersonName,
      toPhone: toPhone ?? this.toPhone,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      settledAt: settledAt ?? this.settledAt,
      isPayer: isPayer ?? this.isPayer,
      isPayee: isPayee ?? this.isPayee,
    );
  }
}
