import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseUrl = 'http://localhost:5262/api';
  late Map<String, String> tokens;
  late Map<String, String> userIds;

  setUpAll(() async {
    tokens = {};
    userIds = {};

    final accounts = [
      {'key': 'u1', 'phone': '9800000001'},
      {'key': 'u2', 'phone': '9800000002'},
      {'key': 'u3', 'phone': '9800000003'},
      {'key': 'u4', 'phone': '9800000004'},
    ];

    for (var acc in accounts) {
      final res = await http.post(
        Uri.parse('$baseUrl/Auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': acc['phone'], 'password': 'Test@12345'}),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        tokens[acc['key']!] = body['data']['token'];
        userIds[acc['key']!] = body['data']['userId'];
      }
    }
  });

  test('BOLA Authorization: Verify Payer, Owner, Admin, Member, and Unrelated user access rules', () async {
    expect(tokens.containsKey('u1'), isTrue, reason: 'User 1 must be authenticated');
    expect(tokens.containsKey('u2'), isTrue, reason: 'User 2 must be authenticated');
    expect(tokens.containsKey('u3'), isTrue, reason: 'User 3 must be authenticated');
    expect(tokens.containsKey('u4'), isTrue, reason: 'User 4 must be authenticated');

    // Step 1: User 1 creates an isolated transient trip
    final tripRes = await http.post(
      Uri.parse('$baseUrl/Trips'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u1']}'},
      body: jsonEncode({'name': 'BOLA Isolation Test Trip', 'description': 'Testing BOLA Authorization Rules'}),
    );
    expect(tripRes.statusCode, 201);
    final tripId = jsonDecode(tripRes.body)['data']['tripId'];

    // Get persons in trip (User 1 is Person 1)
    final tripDetailRes = await http.get(
      Uri.parse('$baseUrl/Trips/$tripId'),
      headers: {'Authorization': 'Bearer ${tokens['u1']}'},
    );
    final tripData = jsonDecode(tripDetailRes.body)['data'];
    final List persons = tripData['persons'] ?? [];
    final person1Id = persons.firstWhere((p) => p['userId'] == userIds['u1'])['personId'];

    // Add User 2 and User 3 as Persons
    final p2Res = await http.post(
      Uri.parse('$baseUrl/Persons'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u1']}'},
      body: jsonEncode({
        'tripId': tripId,
        'name': 'User 2 (Admin)',
        'phoneNumber': '9800000002',
        'userId': userIds['u2'],
      }),
    );
    expect(p2Res.statusCode, anyOf(200, 201));
    final person2Id = jsonDecode(p2Res.body)['data']['personId'];

    final p3Res = await http.post(
      Uri.parse('$baseUrl/Persons'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u1']}'},
      body: jsonEncode({
        'tripId': tripId,
        'name': 'User 3 (Member)',
        'phoneNumber': '9800000003',
        'userId': userIds['u3'],
      }),
    );
    expect(p3Res.statusCode, anyOf(200, 201));
    final person3Id = jsonDecode(p3Res.body)['data']['personId'];

    // Invite User 2 as ADMIN collaborator and User 2 accepts
    final inviteRes = await http.post(
      Uri.parse('$baseUrl/Collaborators'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u1']}'},
      body: jsonEncode({'tripId': tripId, 'userId': userIds['u2'], 'phoneNumber': '9800000002', 'role': 'ADMIN'}),
    );
    expect(inviteRes.statusCode, 200, reason: 'Invite collaborator as ADMIN must succeed');

    final acceptRes = await http.post(
      Uri.parse('$baseUrl/Collaborators/trip/$tripId/accept'),
      headers: {'Authorization': 'Bearer ${tokens['u2']}'},
    );
    expect(acceptRes.statusCode, 200, reason: 'Accept trip invite must succeed');

    // Step 2: User 1 creates Expense 1 (Paid by User 1)
    final exp1Res = await http.post(
      Uri.parse('$baseUrl/Expenses'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u1']}'},
      body: jsonEncode({
        'tripId': tripId,
        'description': 'User 1 Expense',
        'amount': 300.00,
        'currencyCode': 'INR',
        'paidByPersonId': person1Id,
        'splitType': 'EQUAL',
        'splits': [
          {'personId': person1Id, 'amount': 100.00},
          {'personId': person2Id, 'amount': 100.00},
          {'personId': person3Id, 'amount': 100.00},
        ],
      }),
    );
    expect(exp1Res.statusCode, 201);
    final expense1Id = jsonDecode(exp1Res.body)['data']['expenseId'];

    // --- TEST 1: Payer (User 1) can update own expense -> MUST BE 200 OK ---
    final updateByPayer = await http.put(
      Uri.parse('$baseUrl/Expenses/$expense1Id'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u1']}'},
      body: jsonEncode({
        'description': 'User 1 Expense Updated By Payer',
        'amount': 300.00,
        'paidByPersonId': person1Id,
        'splitType': 'EQUAL',
        'splits': [
          {'personId': person1Id, 'amount': 100.00},
          {'personId': person2Id, 'amount': 100.00},
          {'personId': person3Id, 'amount': 100.00},
        ],
      }),
    );
    expect(updateByPayer.statusCode, 200, reason: 'Payer must be permitted to update expense.');
    print('[PASS] Payer update succeeded (HTTP 200).');

    // --- TEST 2: Ordinary Member (User 3) attempts to update User 1 expense -> MUST BE 403 FORBIDDEN ---
    final updateByMember = await http.put(
      Uri.parse('$baseUrl/Expenses/$expense1Id'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u3']}'},
      body: jsonEncode({
        'description': 'Tampered by Ordinary Member',
        'amount': 300.00,
        'paidByPersonId': person1Id,
        'splitType': 'EQUAL',
        'splits': [
          {'personId': person1Id, 'amount': 100.00},
          {'personId': person2Id, 'amount': 100.00},
          {'personId': person3Id, 'amount': 100.00},
        ],
      }),
    );
    expect(updateByMember.statusCode, 403, reason: 'Ordinary member must NOT be permitted to modify another user expense.');
    print('[PASS] Ordinary member unauthorized update BLOCKED with HTTP 403 Forbidden.');

    // --- TEST 3: Unrelated User (User 4) attempts to update User 1 expense -> MUST BE 403 FORBIDDEN ---
    final updateByUnrelated = await http.put(
      Uri.parse('$baseUrl/Expenses/$expense1Id'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u4']}'},
      body: jsonEncode({
        'description': 'Tampered by Unrelated User',
        'amount': 300.00,
        'paidByPersonId': person1Id,
        'splitType': 'EQUAL',
        'splits': [
          {'personId': person1Id, 'amount': 100.00},
          {'personId': person2Id, 'amount': 100.00},
          {'personId': person3Id, 'amount': 100.00},
        ],
      }),
    );
    expect(updateByUnrelated.statusCode, 403, reason: 'Unrelated user must NOT be permitted to modify expense.');
    print('[PASS] Unrelated user update BLOCKED with HTTP 403 Forbidden.');

    // --- TEST 4: Admin (User 2) can update User 1 expense -> MUST BE 200 OK ---
    final updateByAdmin = await http.put(
      Uri.parse('$baseUrl/Expenses/$expense1Id'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tokens['u2']}'},
      body: jsonEncode({
        'description': 'User 1 Expense Updated By Admin',
        'amount': 300.00,
        'paidByPersonId': person1Id,
        'splitType': 'EQUAL',
        'splits': [
          {'personId': person1Id, 'amount': 100.00},
          {'personId': person2Id, 'amount': 100.00},
          {'personId': person3Id, 'amount': 100.00},
        ],
      }),
    );
    expect(updateByAdmin.statusCode, 200, reason: 'Trip administrator must be permitted to update expense.');
    print('[PASS] Trip Admin update succeeded (HTTP 200).');

    // --- TEST 5: Ordinary Member (User 3) attempts to delete User 1 expense -> MUST BE 403 FORBIDDEN ---
    final deleteByMember = await http.delete(
      Uri.parse('$baseUrl/Expenses/$expense1Id'),
      headers: {'Authorization': 'Bearer ${tokens['u3']}'},
    );
    expect(deleteByMember.statusCode, 403, reason: 'Ordinary member must NOT be permitted to delete another user expense.');
    print('[PASS] Ordinary member unauthorized delete BLOCKED with HTTP 403 Forbidden.');

    // --- TEST 6: Owner (User 1) can delete expense -> MUST BE 200 OK ---
    final deleteByOwner = await http.delete(
      Uri.parse('$baseUrl/Expenses/$expense1Id'),
      headers: {'Authorization': 'Bearer ${tokens['u1']}'},
    );
    expect(deleteByOwner.statusCode, 200, reason: 'Trip owner must be permitted to delete expense.');
    print('[PASS] Trip Owner delete succeeded (HTTP 200).');

    // Clean up test trip
    await http.delete(
      Uri.parse('$baseUrl/Trips/$tripId'),
      headers: {'Authorization': 'Bearer ${tokens['u1']}'},
    );
    print('[PASS] Test trip cleaned up successfully.');
  });
}
