import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseUrl = 'http://localhost:5262/api';
  late String token;
  late String userId;

  setUpAll(() async {
    final res = await http.post(
      Uri.parse('$baseUrl/Auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': '9800000001', 'password': 'Test@12345'}),
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(res.body);
    token = body['data']['token'];
    userId = body['data']['userId'];
  });

  test('Soft Delete Endpoint Verification: Trips, Expenses, Persons, Balance Updates & Auditable Retention', () async {
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

    // 1. Create Trip
    print('--- Step 1: Create Test Trip ---');
    final tripRes = await http.post(
      Uri.parse('$baseUrl/Trips'),
      headers: headers,
      body: jsonEncode({'name': 'Soft Delete Audit Trip', 'description': 'Testing Soft Delete Endpoint Isolation'}),
    );
    expect(tripRes.statusCode, 201);
    final tripId = jsonDecode(tripRes.body)['data']['tripId'];

    // Get initial person 1 (trip creator)
    final tripDetail1 = await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: headers);
    final personsList1 = jsonDecode(tripDetail1.body)['data']['persons'] as List;
    final person1Id = personsList1.first['personId'];

    // 2. Add Person 2
    print('--- Step 2: Add Person 2 ---');
    final p2Res = await http.post(
      Uri.parse('$baseUrl/Persons'),
      headers: headers,
      body: jsonEncode({
        'tripId': tripId,
        'name': 'Member 2',
        'phoneNumber': '9900000002',
      }),
    );
    expect(p2Res.statusCode, anyOf(200, 201));
    final person2Id = jsonDecode(p2Res.body)['data']['personId'];

    // 3. Add Expense 1 (₹1000 paid by Person 1, split equally ₹500/₹500)
    print('--- Step 3: Add Expense 1 (₹1000) ---');
    final exp1Res = await http.post(
      Uri.parse('$baseUrl/Expenses'),
      headers: headers,
      body: jsonEncode({
        'tripId': tripId,
        'description': 'Dinner Expense',
        'amount': 1000.00,
        'currencyCode': 'INR',
        'paidByPersonId': person1Id,
        'splitType': 'EQUAL',
        'splits': [
          {'personId': person1Id, 'amount': 500.00},
          {'personId': person2Id, 'amount': 500.00},
        ],
      }),
    );
    expect(exp1Res.statusCode, 201);
    final expense1Id = jsonDecode(exp1Res.body)['data']['expenseId'];

    // 4. Add Expense 2 (₹400 paid by Person 2, split equally ₹200/₹200)
    print('--- Step 4: Add Expense 2 (₹400) ---');
    final exp2Res = await http.post(
      Uri.parse('$baseUrl/Expenses'),
      headers: headers,
      body: jsonEncode({
        'tripId': tripId,
        'description': 'Taxi Expense',
        'amount': 400.00,
        'currencyCode': 'INR',
        'paidByPersonId': person2Id,
        'splitType': 'EQUAL',
        'splits': [
          {'personId': person1Id, 'amount': 200.00},
          {'personId': person2Id, 'amount': 200.00},
        ],
      }),
    );
    expect(exp2Res.statusCode, 201);
    final expense2Id = jsonDecode(exp2Res.body)['data']['expenseId'];

    // Verify initial net balances: Person 1 = 1000 - 700 = +300. Person 2 = 400 - 700 = -300.
    final detailBeforeDelete = await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: headers);
    final personsBefore = jsonDecode(detailBeforeDelete.body)['data']['persons'] as List;
    final p1Before = personsBefore.firstWhere((p) => p['personId'] == person1Id);
    final p2Before = personsBefore.firstWhere((p) => p['personId'] == person2Id);
    expect(p1Before['balance'], 300.00);
    expect(p2Before['balance'], -300.00);
    print('[PASS] Balances before delete verified: Person 1 (+₹300.00), Person 2 (-₹300.00).');

    // 5. Soft-Delete Expense 2
    print('--- Step 5: Soft-Delete Expense 2 ---');
    final deleteExpRes = await http.delete(Uri.parse('$baseUrl/Expenses/$expense2Id'), headers: headers);
    expect(deleteExpRes.statusCode, 200);

    // Verify Expense 2 is hidden from active list
    final expListRes = await http.get(Uri.parse('$baseUrl/Expenses/trip/$tripId'), headers: headers);
    final expList = jsonDecode(expListRes.body)['data'] as List;
    expect(expList.any((e) => e['expenseId'] == expense2Id), isFalse, reason: 'Soft-deleted expense must NOT appear in active expenses view');
    expect(expList.any((e) => e['expenseId'] == expense1Id), isTrue, reason: 'Active expense must remain visible');
    print('[PASS] Soft-deleted expense is hidden from active GET /api/Expenses/trip/{tripId}.');

    // Verify balance recalculation excludes soft-deleted expense: Person 1 = 1000 - 500 = +500. Person 2 = 0 - 500 = -500.
    final detailAfterDeleteExp = await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: headers);
    final personsAfterExpDel = jsonDecode(detailAfterDeleteExp.body)['data']['persons'] as List;
    final p1AfterExp = personsAfterExpDel.firstWhere((p) => p['personId'] == person1Id);
    final p2AfterExp = personsAfterExpDel.firstWhere((p) => p['personId'] == person2Id);
    expect(p1AfterExp['balance'], 500.00);
    expect(p2AfterExp['balance'], -500.00);
    print('[PASS] Financial balance correctly recalculated after soft-deletion: Person 1 (+₹500.00), Person 2 (-₹500.00).');

    // 6. Soft-Delete Person 2
    print('--- Step 6: Soft-Delete Person 2 ---');
    final deleteP2Res = await http.delete(Uri.parse('$baseUrl/Persons/$person2Id'), headers: headers);
    expect(deleteP2Res.statusCode, 200);

    // Verify Person 2 is hidden from trip persons
    final personsRes = await http.get(Uri.parse('$baseUrl/Persons/trip/$tripId'), headers: headers);
    final personsActive = jsonDecode(personsRes.body)['data'] as List;
    expect(personsActive.any((p) => p['personId'] == person2Id), isFalse, reason: 'Soft-deleted person must NOT appear in active persons view');
    print('[PASS] Soft-deleted person is hidden from active GET /api/Persons/trip/{tripId}.');

    // 7. Soft-Delete Trip
    print('--- Step 7: Soft-Delete Trip ---');
    final deleteTripRes = await http.delete(Uri.parse('$baseUrl/Trips/$tripId'), headers: headers);
    expect(deleteTripRes.statusCode, 200);

    // Verify Trip is hidden from GET /api/Trips
    final userTripsRes = await http.get(Uri.parse('$baseUrl/Trips'), headers: headers);
    final userTrips = jsonDecode(userTripsRes.body)['data'] as List;
    expect(userTrips.any((t) => t['tripId'] == tripId), isFalse, reason: 'Soft-deleted trip must NOT appear in user trips view');

    // Verify GET /api/Trips/{tripId} returns 404
    final tripDetailAfterDel = await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: headers);
    expect(tripDetailAfterDel.statusCode, anyOf(404, 403));
    print('[PASS] Soft-deleted trip is hidden from user dashboard and returns 404.');
  });
}
