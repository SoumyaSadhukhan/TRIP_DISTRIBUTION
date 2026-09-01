// test/settlement_statement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_split/models/settlement_proposal.dart';
import 'package:trip_split/models/notification.dart';

void main() {
  group('Settlement Statement & Proposal Tests', () {
    test('SettlementProposal serialization and copyWith updates amount', () {
      final proposal = SettlementProposal(
        settlementId: 'st-12345',
        tripId: 'trip-999',
        tripName: 'Goa Holiday',
        fromPersonId: 'p-1',
        fromPersonName: 'Alice',
        toPersonId: 'p-2',
        toPersonName: 'Bob',
        amount: 1500.00,
        status: 'PENDING',
        settledAt: DateTime.parse('2026-09-01T12:00:00Z'),
        isPayer: true,
      );

      expect(proposal.amount, 1500.00);
      expect(proposal.isPayer, true);

      // Test copyWith when user edits settlement amount
      final updated = proposal.copyWith(amount: 1200.50);
      expect(updated.amount, 1200.50);
      expect(updated.settlementId, 'st-12345');
      expect(updated.tripName, 'Goa Holiday');

      // Test JSON conversion
      final json = updated.toJson();
      expect(json['settlementId'], 'st-12345');
      expect(json['amount'], 1200.50);

      final fromJson = SettlementProposal.fromJson(json);
      expect(fromJson.amount, 1200.50);
      expect(fromJson.fromPersonName, 'Alice');
      expect(fromJson.toPersonName, 'Bob');
    });

    test('NotificationModel parses settlementId and statement info', () {
      final notifJson = {
        'notification_id': 'notif-777',
        'user_id': 'u-bob',
        'trip_id': 'trip-999',
        'trip_name': 'Goa Holiday',
        'settlement_id': 'st-12345',
        'title': '💳 Settlement Statement - ₹1,200.50',
        'message': 'Alice sent a settlement statement of ₹1,200.50 for Goa Holiday.',
        'type': 'SETTLEMENT_PROPOSAL',
        'amount': 1200.50,
        'is_read': 0,
        'created_at': '2026-09-01T12:05:00.000Z',
      };

      final notif = NotificationModel.fromJson(notifJson);
      expect(notif.id, 'notif-777');
      expect(notif.settlementId, 'st-12345');
      expect(notif.amount, 1200.50);
      expect(notif.type, 'SETTLEMENT_PROPOSAL');
      expect(notif.isRead, false);
    });
  });
}
