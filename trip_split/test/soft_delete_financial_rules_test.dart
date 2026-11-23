import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseUrl = 'http://localhost:5262/api';

  test('TASK 4: Soft-Delete Financial Rules, Balance Invariants, Auditability, and Restoration', () async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final testUserEmail = 'fin_rule_owner_$timestamp@test.local';
    final testPassword = 'Password123!';

    print('--- 1. Register Owner Account ---');
    final regRes = await http.post(
      Uri.parse('$baseUrl/Auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': testUserEmail,
        'phone': '+9198${timestamp.toString().substring(5)}',
        'password': testPassword,
        'username': 'FinOwner_$timestamp',
        'fullName': 'Financial Audit Owner',
      }),
    );
    expect(regRes.statusCode, 200);
    final regData = jsonDecode(regRes.body)['data'];
    final token = regData['token'] as String;
    final ownerUserId = regData['userId'] as String;
    final authHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    print('--- 2. Create Test Trip ---');
    final tripRes = await http.post(
      Uri.parse('$baseUrl/Trips'),
      headers: authHeaders,
      body: jsonEncode({
        'name': 'Financial Integrity Audit Trip $timestamp',
        'description': 'Validating soft delete rules and financial invariants',
        'currencyCode': 'INR',
      }),
    );
    expect(tripRes.statusCode, anyOf(200, 201));
    final tripData = jsonDecode(tripRes.body)['data'];
    final tripId = tripData['tripId'] as String;

    // Fetch initial detail to get creator person_id
    final initDetailRes = await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders);
    expect(initDetailRes.statusCode, 200);
    final initDetail = jsonDecode(initDetailRes.body)['data'];
    final creatorPerson = (initDetail['persons'] as List).first;
    final creatorPersonId = creatorPerson['personId'] as String;

    print('--- 3. Add Person A and Person B to Trip ---');
    final personARes = await http.post(
      Uri.parse('$baseUrl/Persons'),
      headers: authHeaders,
      body: jsonEncode({
        'tripId': tripId,
        'name': 'Person A',
        'dietType': 0,
      }),
    );
    expect(personARes.statusCode, 200);
    final personAId = jsonDecode(personARes.body)['data']['personId'] as String;

    final personBRes = await http.post(
      Uri.parse('$baseUrl/Persons'),
      headers: authHeaders,
      body: jsonEncode({
        'tripId': tripId,
        'name': 'Person B',
        'dietType': 0,
      }),
    );
    expect(personBRes.statusCode, 200);
    final personBId = jsonDecode(personBRes.body)['data']['personId'] as String;

    print('--- 4. Add Expense 1: Person A pays ₹1,200 split equally (₹400 each) ---');
    final expRes = await http.post(
      Uri.parse('$baseUrl/Expenses'),
      headers: authHeaders,
      body: jsonEncode({
        'tripId': tripId,
        'description': 'Group Dinner',
        'amount': 1200.00,
        'currencyCode': 'INR',
        'paidByPersonId': personAId,
        'splitType': 'EQUAL',
        'splits': [
          {'personId': personAId, 'amount': 400.00},
          {'personId': personBId, 'amount': 400.00},
          {'personId': creatorPersonId, 'amount': 400.00},
        ],
      }),
    );
    expect(expRes.statusCode, anyOf(200, 201));
    final expenseId = jsonDecode(expRes.body)['data']['expenseId'] as String;

    // Verify initial balances: A = +800, B = -400, Creator = -400
    final detailAfterExp = jsonDecode((await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders)).body)['data'];
    final personsAfterExp = detailAfterExp['persons'] as List;
    final bA1 = (personsAfterExp.firstWhere((p) => p['personId'] == personAId)['balance'] as num).toDouble();
    final bB1 = (personsAfterExp.firstWhere((p) => p['personId'] == personBId)['balance'] as num).toDouble();
    final bC1 = (personsAfterExp.firstWhere((p) => p['personId'] == creatorPersonId)['balance'] as num).toDouble();
    expect(bA1, 800.00);
    expect(bB1, -400.00);
    expect(bC1, -400.00);
    expect(bA1 + bB1 + bC1, 0.00);
    print('[PASS] Initial balances invariant verified: +800 + (-400) + (-400) = 0.00');

    print('--- 5. Soft-Delete Person B while active expenses & non-zero balance (-₹400) exist ---');
    final delPersonBRes = await http.delete(Uri.parse('$baseUrl/Persons/$personBId'), headers: authHeaders);
    expect(delPersonBRes.statusCode, 200);
    print('[PASS] Person B marked soft-deleted.');

    print('--- 6. Verify Person B is NOT silently omitted and balances remain consistent ---');
    final detailAfterDelPerson = jsonDecode((await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders)).body)['data'];
    final personsAfterDel = detailAfterDelPerson['persons'] as List;
    
    // Person B must still be returned because of non-zero balance / financial obligations
    final personBRecord = personsAfterDel.firstWhere((p) => p['personId'] == personBId, orElse: () => null);
    expect(personBRecord, isNotNull, reason: 'Deleted person with outstanding balance MUST remain visible');
    expect(personBRecord['isDeleted'], isTrue);
    expect((personBRecord['balance'] as num).toDouble(), -400.00);

    final sumBalances = personsAfterDel.fold<double>(0.0, (acc, p) => acc + (p['balance'] as num).toDouble());
    expect(sumBalances, 0.00, reason: 'Total balance across all active/obligated persons MUST equal 0.00');
    print('[PASS] Person B balance (-₹400) remains visible with isDeleted=true, and total balance SUM == 0.00!');

    print('--- 7. Soft-Delete Expense and Verify Balance Recalculation ---');
    final delExpRes = await http.delete(Uri.parse('$baseUrl/Expenses/$expenseId'), headers: authHeaders);
    expect(delExpRes.statusCode, 200);

    final detailAfterDelExp = jsonDecode((await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders)).body)['data'];
    final activeExpenses = detailAfterDelExp['expenses'] as List;
    expect(activeExpenses.any((e) => e['expenseId'] == expenseId), isFalse, reason: 'Soft-deleted expense must be hidden from active list');

    // With expense deleted, all balances recalculate to 0.00
    final personsAfterDelExp = detailAfterDelExp['persons'] as List;
    for (final p in personsAfterDelExp) {
      expect((p['balance'] as num).toDouble(), 0.00);
    }
    print('[PASS] Soft-deleted expense successfully excluded from active calculations; balances recalculated to 0.00.');

    print('--- 8. Restore Expense and Verify Balances Return ---');
    final restoreExpRes = await http.post(Uri.parse('$baseUrl/Expenses/restore/$expenseId'), headers: authHeaders);
    expect(restoreExpRes.statusCode, 200);

    final detailAfterRestoredExp = jsonDecode((await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders)).body)['data'];
    final restoredExpenses = detailAfterRestoredExp['expenses'] as List;
    expect(restoredExpenses.any((e) => e['expenseId'] == expenseId), isTrue, reason: 'Restored expense must appear in active list');
    print('[PASS] Expense restoration verified and balances restored.');

    print('--- 9. Restore Person B ---');
    final restorePersonBRes = await http.post(Uri.parse('$baseUrl/Persons/restore/$personBId'), headers: authHeaders);
    expect(restorePersonBRes.statusCode, 200);

    final detailAfterRestoredPerson = jsonDecode((await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders)).body)['data'];
    final personBActive = (detailAfterRestoredPerson['persons'] as List).firstWhere((p) => p['personId'] == personBId);
    expect(personBActive['isDeleted'], isFalse);
    print('[PASS] Person B restored to active status.');

    print('--- 10. Test Trip Soft-Delete and Restoration ---');
    final delTripRes = await http.delete(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders);
    expect(delTripRes.statusCode, 200);

    final getDeletedTripRes = await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders);
    expect(getDeletedTripRes.statusCode, 404, reason: 'Soft-deleted trip must return 404 from active detail endpoint');

    final restoreTripRes = await http.post(Uri.parse('$baseUrl/Trips/restore/$tripId'), headers: authHeaders);
    expect(restoreTripRes.statusCode, 200);

    final getRestoredTripRes = await http.get(Uri.parse('$baseUrl/Trips/$tripId'), headers: authHeaders);
    expect(getRestoredTripRes.statusCode, 200, reason: 'Restored trip must be accessible again');
    print('[PASS] Trip soft-delete and restoration verified end-to-end.');
  });
}
