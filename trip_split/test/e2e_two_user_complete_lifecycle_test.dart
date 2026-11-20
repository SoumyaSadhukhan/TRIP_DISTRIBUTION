import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = RealHttpOverrides();
  });

  const baseUrl = 'http://127.0.0.1:5262/api';
  late String tokenA;
  late String tokenB;
  late String userIdA;
  late String userIdB;
  late String tripId;

  Map<String, String> authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  group('E2E Complete 2-User Journey & Verification', () {
    test('1. Authentication: Login User A and User B', () async {
      print('\n======================================================');
      print('STEP 1: AUTHENTICATING USER A AND USER B');
      print('======================================================');

      // 1.1 Login User A
      final resA = await http.post(
        Uri.parse('$baseUrl/Auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': '9800000001',
          'email': 'testuser1@example.com',
          'password': 'Test@12345',
        }),
      );
      expect(resA.statusCode, 200, reason: 'User A login failed: ${resA.body}');
      final dataA = jsonDecode(resA.body)['data'];
      tokenA = dataA['token'];
      userIdA = dataA['userId'];
      expect(tokenA.isNotEmpty, isTrue);
      print('[PASS] User A authenticated (UserId: $userIdA).');

      // 1.2 Login User B
      final resB = await http.post(
        Uri.parse('$baseUrl/Auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': '9800000002',
          'email': 'testuser2@example.com',
          'password': 'Test@12345',
        }),
      );
      expect(resB.statusCode, 200, reason: 'User B login failed: ${resB.body}');
      final dataB = jsonDecode(resB.body)['data'];
      tokenB = dataB['token'];
      userIdB = dataB['userId'];
      expect(tokenB.isNotEmpty, isTrue);
      print('[PASS] User B authenticated (UserId: $userIdB).');
    });

    test('2. Friend Management: Search, Request, Notification, and Verify Friendship', () async {
      print('\n======================================================');
      print('STEP 2: FRIEND LIFECYCLE (SEARCH -> INVITE -> ACCEPT)');
      print('======================================================');

      // 2.1 User A searches for User B by phone number
      final searchRes = await http.post(
        Uri.parse('$baseUrl/Friends/search'),
        headers: authHeaders(tokenA),
        body: jsonEncode({'phone': '9800000002'}),
      );
      expect(searchRes.statusCode, 200);
      final searchData = jsonDecode(searchRes.body)['data'] as List;
      expect(searchData.isNotEmpty, isTrue);
      print('[PASS] User A searched and found User B (${searchData.first['fullName'] ?? searchData.first['phone']}).');

      // 2.2 User A sends friend request to User B (or checks existing connection)
      final inviteRes = await http.post(
        Uri.parse('$baseUrl/Friends'),
        headers: authHeaders(tokenA),
        body: jsonEncode({
          'friendPhone': '9800000002',
          'friendName': 'User 2',
          'dietType': 1,
        }),
      );
      expect(inviteRes.statusCode == 200 || inviteRes.statusCode == 400, isTrue);

      if (inviteRes.statusCode == 200) {
        final inviteData = jsonDecode(inviteRes.body)['data'];
        final connectionId = inviteData['connectionId'] ?? inviteData['id'];
        print('[PASS] User A sent friend request to User B (ConnectionId: $connectionId).');

        // User B accepts
        if (connectionId != null && connectionId.toString().isNotEmpty) {
          final acceptRes = await http.put(
            Uri.parse('$baseUrl/Friends/$connectionId/status'),
            headers: authHeaders(tokenB),
            body: jsonEncode({'status': 'ACCEPTED'}),
          );
          expect(acceptRes.statusCode, 200);
          print('[PASS] User B accepted friend request with HTTP 200.');
        }
      } else {
        print('[INFO] User A and User B are already connected friends in DB.');
      }

      // 2.3 Verify active friendship
      final friendsRes = await http.get(
        Uri.parse('$baseUrl/Friends'),
        headers: authHeaders(tokenA),
      );
      expect(friendsRes.statusCode, 200);
      final friendsList = jsonDecode(friendsRes.body)['data'] as List;
      final friendB = friendsList.firstWhere(
        (f) => (f['friendPhone'] as String).contains('9800000002'),
        orElse: () => null,
      );
      expect(friendB, isNotNull);
      print('[PASS] Active friend connection verified between User A and User B (Status: ${friendB['status']}).');
    });

    test('3. Trip Management: Create Trip and Invite Friend User B', () async {
      print('\n======================================================');
      print('STEP 3: TRIP CREATION & FRIEND TRIP INVITATION');
      print('======================================================');

      // 3.1 User A creates Trip
      final tripRes = await http.post(
        Uri.parse('$baseUrl/Trips'),
        headers: authHeaders(tokenA),
        body: jsonEncode({
          'name': 'E2E Lifecycle Shimla 2026',
          'description': 'End-to-End automated lifecycle trip',
          'currencyCode': 'INR',
        }),
      );
      expect(tripRes.statusCode, 201);
      final tripData = jsonDecode(tripRes.body)['data'];
      tripId = tripData['tripId'] ?? tripData['id'];
      expect(tripId.isNotEmpty, isTrue);
      print('[PASS] User A created Trip "E2E Lifecycle Shimla 2026" (TripId: $tripId).');

      // 3.2 User A adds friend User B to the trip (creates Person & Pending Collaborator & Sends Invite Notification)
      final addPersonRes = await http.post(
        Uri.parse('$baseUrl/Persons'),
        headers: authHeaders(tokenA),
        body: jsonEncode({
          'tripId': tripId,
          'name': 'User 2',
          'phoneNumber': '9800000002',
          'dietType': 1,
        }),
      );
      expect(addPersonRes.statusCode, 200);
      print('[PASS] User A added friend User B to trip; pending invitation generated.');

      // 3.3 User B verifies trip invite notification
      final notifResB = await http.get(
        Uri.parse('$baseUrl/Notifications'),
        headers: authHeaders(tokenB),
      );
      expect(notifResB.statusCode, 200);
      final notifsB = jsonDecode(notifResB.body)['data'] as List;
      final tripInviteNotif = notifsB.firstWhere(
        (n) => (n['tripId'] == tripId) || ((n['message'] as String).contains('E2E Lifecycle Shimla 2026')),
        orElse: () => null,
      );
      expect(tripInviteNotif, isNotNull);
      print('[PASS] User B received trip invitation notification: "${tripInviteNotif['message']}".');

      // 3.4 User B accepts trip invite
      final acceptTripRes = await http.post(
        Uri.parse('$baseUrl/Trips/$tripId/accept-invite'),
        headers: authHeaders(tokenB),
      );
      expect(acceptTripRes.statusCode, 200);
      print('[PASS] User B accepted trip invite via POST /api/Trips/$tripId/accept-invite.');

      // 3.5 User A checks notifications for acceptance notice
      final notifResA = await http.get(
        Uri.parse('$baseUrl/Notifications'),
        headers: authHeaders(tokenA),
      );
      expect(notifResA.statusCode, 200);
      final notifsA = jsonDecode(notifResA.body)['data'] as List;
      final acceptedNotice = notifsA.firstWhere(
        (n) => (n['tripId'] == tripId) || ((n['message'] as String).contains('accepted the trip request')),
        orElse: () => null,
      );
      expect(acceptedNotice, isNotNull);
      print('[PASS] User A received notification: "${acceptedNotice['message']}".');
    });

    test('4. Expenses & Balances: Add Shared Expense, Balances, and Zero-Sum Settlement', () async {
      print('\n======================================================');
      print('STEP 4: SHARED EXPENSE & ZERO-SUM SETTLEMENT');
      print('======================================================');

      // 4.1 Get Persons in the Trip
      final personsRes = await http.get(
        Uri.parse('$baseUrl/Persons/trip/$tripId'),
        headers: authHeaders(tokenA),
      );
      expect(personsRes.statusCode, 200);
      final persons = jsonDecode(personsRes.body)['data'] as List;
      expect(persons.length >= 2, isTrue);

      final personA = persons.firstWhere((p) => p['userId'] == userIdA || (p['name'] as String).contains('User 1'));
      final personB = persons.firstWhere((p) => p['userId'] == userIdB || (p['name'] as String).contains('User 2'));
      final personAId = personA['personId'] ?? personA['id'];
      final personBId = personB['personId'] ?? personB['id'];

      // 4.2 User A adds an expense of INR 2,400 split 50/50
      final expRes = await http.post(
        Uri.parse('$baseUrl/Expenses'),
        headers: authHeaders(tokenA),
        body: jsonEncode({
          'tripId': tripId,
          'description': 'Mountain Cottage Stay',
          'amount': 2400.0,
          'currencyCode': 'INR',
          'categoryIndex': 1,
          'categoryName': 'Accommodation',
          'paidByPersonId': personAId,
          'splitType': 'EQUAL',
          'splits': [
            {'personId': personAId, 'amount': 1200.0},
            {'personId': personBId, 'amount': 1200.0},
          ],
        }),
      );
      expect(expRes.statusCode, 201);
      print('[PASS] Shared expense "Mountain Cottage Stay" created for ₹2,400.00 (Split: 1200/1200).');

      // 4.3 Verify Persons net balances
      final updatedPersonsRes = await http.get(
        Uri.parse('$baseUrl/Persons/trip/$tripId'),
        headers: authHeaders(tokenA),
      );
      expect(updatedPersonsRes.statusCode, 200);
      final updatedPersons = jsonDecode(updatedPersonsRes.body)['data'] as List;

      final uPersonA = updatedPersons.firstWhere((p) => (p['personId'] ?? p['id']) == personAId);
      final uPersonB = updatedPersons.firstWhere((p) => (p['personId'] ?? p['id']) == personBId);

      print('  User A Balance: Paid = ₹${uPersonA['paidAmount']}, Share = ₹${uPersonA['owedAmount']}, Net = ₹${uPersonA['balance']}');
      print('  User B Balance: Paid = ₹${uPersonB['paidAmount']}, Share = ₹${uPersonB['owedAmount']}, Net = ₹${uPersonB['balance']}');

      // User A paid 2400, owes 1200 => Net = +1200
      // User B paid 0, owes 1200 => Net = -1200
      expect((uPersonA['balance'] as num).toDouble(), 1200.0);
      expect((uPersonB['balance'] as num).toDouble(), -1200.0);
      print('[PASS] Person balances accurately computed (+₹1200.00 and -₹1200.00).');

      // 4.4 User B settles up ₹1,200 to User A
      print('\n[TEST] User B proposing settlement of ₹1,200.00 to User A...');
      final settleRes = await http.post(
        Uri.parse('$baseUrl/Settlements'),
        headers: authHeaders(tokenB),
        body: jsonEncode({
          'tripId': tripId,
          'fromPersonId': personBId,
          'toPersonId': personAId,
          'amount': 1200.0,
        }),
      );
      expect(settleRes.statusCode, 201);
      final settleData = jsonDecode(settleRes.body)['data'];
      final settlementId = settleData['settlementId'] ?? settleData['id'];
      print('[PASS] Settlement of ₹1,200.00 proposed (SettlementId: $settlementId).');

      // 4.5 User A accepts the settlement
      if (settlementId != null && settlementId.toString().isNotEmpty) {
        final updateSettleRes = await http.put(
          Uri.parse('$baseUrl/Settlements/$settlementId/status'),
          headers: authHeaders(tokenA),
          body: jsonEncode({'status': 'ACCEPTED'}),
        );
        expect(updateSettleRes.statusCode, 200);
        print('[PASS] User A accepted settlement.');
      }

      // 4.6 Verify Zero-Sum Invariant
      final finalPersonsRes = await http.get(
        Uri.parse('$baseUrl/Persons/trip/$tripId'),
        headers: authHeaders(tokenA),
      );
      final finalPersons = jsonDecode(finalPersonsRes.body)['data'] as List;
      double netSum = 0.0;
      for (final p in finalPersons) {
        netSum += (p['balance'] as num).toDouble();
      }
      expect(netSum.abs() < 0.01, isTrue);
      print('[PASS] Zero-Sum Financial Invariant Verified: Final net sum = ₹$netSum.');
    });

    test('5. Cleanup Test Trip', () async {
      print('\n======================================================');
      print('STEP 5: DATABASE TEARDOWN OF TEMPORARY TEST TRIP');
      print('======================================================');

      if (tripId.isNotEmpty) {
        final delRes = await http.delete(
          Uri.parse('$baseUrl/Trips/$tripId'),
          headers: authHeaders(tokenA),
        );
        expect(delRes.statusCode, 200);
        print('[PASS] Temporary test trip $tripId deleted cleanly. Production records preserved.');
      }
    });
  });
}
