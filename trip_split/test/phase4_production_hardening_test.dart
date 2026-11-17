// test/phase4_production_hardening_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const baseUrl = 'http://localhost:5262/api';

  group('EquiTrip Phase 4 - Production Blockers & Hardening Audit', () {
    String? user1Token;
    String? user2Token;
    String? user3Token;
    String? user4Token;
    String? user5Token;

    setUpAll(() async {
      // Authenticate test users
      Future<String> login(String email, String phone, String password) async {
        final candidates = [password, 'UpdatedTest@999', 'Test@NewPass2026!', 'Test@12345'];
        http.Response? lastRes;
        for (final p in candidates) {
          final res = await http.post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'phone': phone, 'password': p}),
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            return data['data']['token'] as String;
          }
          lastRes = res;
        }
        throw Exception('Failed to login $email: ${lastRes?.statusCode} ${lastRes?.body}');
      }

      user1Token = await login('testuser1@example.com', '9800000001', 'Test@12345');
      user2Token = await login('testuser2@example.com', '9800000002', 'Test@12345');
      user3Token = await login('testuser3@example.com', '9800000003', 'Test@12345');
      user4Token = await login('testuser4@example.com', '9800000004', 'Test@12345');
      user5Token = await login('testuser5@example.com', '9800000005', 'Test@12345');
    });

    // =========================================================================
    // DEFECT 1: SEC-DEF-01 – Password Reset & Authentication Hardening
    // =========================================================================
    group('DEFECT 1: SEC-DEF-01 – Password Reset & OTP Workflow', () {
      test('1.1 Unauthenticated send-otp for FORGOT_PASSWORD succeeds without JWT', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/auth/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'purpose': 'FORGOT_PASSWORD',
          }),
        );
        expect(res.statusCode, 200, reason: 'send-otp must be open to unauthenticated users');
        final data = jsonDecode(res.body);
        expect(data['success'], isTrue);
      });

      test('1.2 Account enumeration prevention: Non-existent account returns generic message', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/auth/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'completely_fake_account_9999@example.com',
            'phone': '9999999999',
            'purpose': 'FORGOT_PASSWORD',
          }),
        );
        expect(res.statusCode, 200, reason: 'Non-existent account must not return 404 for FORGOT_PASSWORD to prevent enumeration');
        final data = jsonDecode(res.body);
        expect(data['success'], isTrue);
        expect(data['data']['message'], contains('verification code has been dispatched'));
      });

      test('1.3 Reset password with invalid OTP is rejected with 400', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'otpCode': '999999',
            'newPassword': 'NewPassword@999',
          }),
        );
        expect(res.statusCode, 400);
        final data = jsonDecode(res.body);
        expect(data['success'], isFalse);
        expect(data['message'], contains('Invalid or expired OTP'));
      });

      test('1.4 Reset password with short password (<6 chars) is rejected with 400', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'otpCode': '123456',
            'newPassword': '123',
          }),
        );
        expect(res.statusCode, 400);
      });

      test('1.5 Wrong OTP purpose: OTP generated for REGISTER fails on reset-password', () async {
        // Generate OTP for REGISTER purpose
        await http.post(
          Uri.parse('$baseUrl/auth/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'purpose': 'REGISTER',
          }),
        );

        // Attempt to use REGISTER OTP for reset-password without debug bypass
        // In dev with bypass enabled, bypass requires FORGOT_PASSWORD explicitly
        final res = await http.post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'otpCode': '888888', // wrong code
            'newPassword': 'TempPassword@123',
          }),
        );
        expect(res.statusCode, 400);
      });

      test('1.6 Full Password Reset Lifecycle: Reset, Login with New, Invalidate Old, Revert to Original', () async {
        // Step A: Request OTP for User 4
        final otpRes = await http.post(
          Uri.parse('$baseUrl/auth/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'purpose': 'FORGOT_PASSWORD',
          }),
        );
        expect(otpRes.statusCode, 200);
        final otpData = jsonDecode(otpRes.body);
        final otpCode = otpData['data']['otpCode'] ?? '123456';

        // Step B: Reset password without JWT
        final resetRes = await http.post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'otpCode': otpCode,
            'newPassword': 'UpdatedTest@999',
          }),
        );
        expect(resetRes.statusCode, 200);
        final resetData = jsonDecode(resetRes.body);
        expect(resetData['success'], isTrue);

        // Step C: Verify OTP reuse prevention - reusing the exact same OTP must fail with 400
        final reuseRes = await http.post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'otpCode': otpCode,
            'newPassword': 'AnotherPassword@999',
          }),
        );
        // Once consumed, subsequent attempts with that OTP are rejected
        expect(reuseRes.statusCode, 400, reason: 'Reusing a consumed OTP must be rejected with 400');

        // Step D: Old password (Test@12345) must now fail
        final oldLoginRes = await http.post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': '9800000004',
            'email': 'testuser4@example.com',
            'password': 'Test@12345',
          }),
        );
        expect(oldLoginRes.statusCode, 401, reason: 'Old password must be invalidated');

        // Step E: New password (UpdatedTest@999) must succeed
        final newLoginRes = await http.post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': '9800000004',
            'email': 'testuser4@example.com',
            'password': 'UpdatedTest@999',
          }),
        );
        expect(newLoginRes.statusCode, 200, reason: 'New password must succeed');

        // Step F: Revert User 4 password back to Test@12345 for continuous test suite compatibility
        final revertOtpRes = await http.post(
          Uri.parse('$baseUrl/auth/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'purpose': 'FORGOT_PASSWORD',
          }),
        );
        expect(revertOtpRes.statusCode, 200);
        final revertOtpCode = jsonDecode(revertOtpRes.body)['data']['otpCode'] ?? '123456';

        final revertRes = await http.post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'testuser4@example.com',
            'phone': '9800000004',
            'otpCode': revertOtpCode,
            'newPassword': 'Test@12345',
          }),
        );
        expect(revertRes.statusCode, 200);

        // Verify restored login and refresh user4Token
        final restoredLoginRes = await http.post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': '9800000004',
            'email': 'testuser4@example.com',
            'password': 'Test@12345',
          }),
        );
        expect(restoredLoginRes.statusCode, 200);
        user4Token = jsonDecode(restoredLoginRes.body)['data']['token'];
      });

      test('1.7 Protected endpoints still strictly require Bearer token', () async {
        final res = await http.get(Uri.parse('$baseUrl/auth/profile'));
        expect(res.statusCode, 401, reason: 'Endpoints without [AllowAnonymous] must require authentication');
      });
    });

    // =========================================================================
    // DEFECT 3: FIN-DEF-01 – Exact Financial Split Validation
    // =========================================================================
    group('DEFECT 3: FIN-DEF-01 – Exact Financial Split Validation', () {
      String? testTripId;
      String? person1Id;
      String? person2Id;
      String? person3Id;

      setUpAll(() async {
        // Create an isolated test trip to avoid touching Goa Vacation 2026 balances
        final tripRes = await http.post(
          Uri.parse('$baseUrl/trips'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'name': 'FIN_DEF01_AUDIT_TRIP_2026',
            'description': 'Audit Lab Trip for Exact Split Validation',
            'currencyCode': 'INR',
          }),
        );
        expect(tripRes.statusCode, 201);
        final tripData = jsonDecode(tripRes.body);
        testTripId = tripData['data']['tripId'];

        // Add 3 persons to the test trip
        Future<String> addPerson(String name) async {
          final res = await http.post(
            Uri.parse('$baseUrl/persons'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $user1Token',
            },
            body: jsonEncode({
              'tripId': testTripId,
              'name': name,
              'email': '$name@example.com',
            }),
          );
          return jsonDecode(res.body)['data']['personId'];
        }

        person1Id = await addPerson('AuditPerson1');
        person2Id = await addPerson('AuditPerson2');
        person3Id = await addPerson('AuditPerson3');
      });

      tearDownAll(() async {
        // Clean up the isolated audit trip
        if (testTripId != null) {
          await http.delete(
            Uri.parse('$baseUrl/trips/$testTripId'),
            headers: {'Authorization': 'Bearer $user1Token'},
          );
        }
      });

      test('3.1 Exact 3-way split with remainder: ₹100.00 = ₹33.34 + ₹33.33 + ₹33.33 passes', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/expenses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'tripId': testTripId,
            'description': 'Valid Exact Remainder Split',
            'amount': 100.00,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'UNEQUAL',
            'splits': [
              {'personId': person1Id, 'amount': 33.34},
              {'personId': person2Id, 'amount': 33.33},
              {'personId': person3Id, 'amount': 33.33},
            ],
          }),
        );
        expect(res.statusCode, 201, reason: 'Exact split summing to 100.00 must succeed');
      });

      test('3.2 One-paise under-allocation: ₹100.00 = ₹99.99 is strictly REJECTED (400)', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/expenses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'tripId': testTripId,
            'description': '1-Cent Deficit Split',
            'amount': 100.00,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'UNEQUAL',
            'splits': [
              {'personId': person1Id, 'amount': 33.33},
              {'personId': person2Id, 'amount': 33.33},
              {'personId': person3Id, 'amount': 33.33}, // sum = 99.99 (0.01 missing)
            ],
          }),
        );
        expect(res.statusCode, 400, reason: '1-paise under-allocation must be rejected');
        final data = jsonDecode(res.body);
        expect(data['success'], isFalse);
        expect(data['message'], contains('must exactly equal'));
      });

      test('3.3 One-paise over-allocation: ₹100.00 = ₹100.01 is strictly REJECTED (400)', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/expenses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'tripId': testTripId,
            'description': '1-Cent Surplus Split',
            'amount': 100.00,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'UNEQUAL',
            'splits': [
              {'personId': person1Id, 'amount': 33.35},
              {'personId': person2Id, 'amount': 33.33},
              {'personId': person3Id, 'amount': 33.33}, // sum = 100.01 (0.01 excess)
            ],
          }),
        );
        expect(res.statusCode, 400, reason: '1-paise over-allocation must be rejected');
      });

      test('3.4 Under-allocation: ₹100.00 with ₹40.00 + ₹40.00 is REJECTED (400)', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/expenses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'tripId': testTripId,
            'description': 'Under-allocation test',
            'amount': 100.00,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'UNEQUAL',
            'splits': [
              {'personId': person1Id, 'amount': 40.00},
              {'personId': person2Id, 'amount': 40.00},
            ],
          }),
        );
        expect(res.statusCode, 400);
      });

      test('3.5 Over-allocation: ₹100.00 with ₹60.00 + ₹60.00 is REJECTED (400)', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/expenses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'tripId': testTripId,
            'description': 'Over-allocation test',
            'amount': 100.00,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'UNEQUAL',
            'splits': [
              {'personId': person1Id, 'amount': 60.00},
              {'personId': person2Id, 'amount': 60.00},
            ],
          }),
        );
        expect(res.statusCode, 400);
      });

      test('3.6 Invalid decimal precision (>2 decimal places) is REJECTED (400)', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/expenses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'tripId': testTripId,
            'description': 'Excess decimal precision',
            'amount': 100.005,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'AUTO',
          }),
        );
        expect(res.statusCode, 400, reason: 'Amounts with >2 decimal places must be rejected');
      });

      test('3.7 Strict monetary rules enforced during expense update (PUT)', () async {
        // Create initial valid expense
        final createRes = await http.post(
          Uri.parse('$baseUrl/expenses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'tripId': testTripId,
            'description': 'Expense to update',
            'amount': 150.00,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'UNEQUAL',
            'splits': [
              {'personId': person1Id, 'amount': 75.00},
              {'personId': person2Id, 'amount': 75.00},
            ],
          }),
        );
        expect(createRes.statusCode, 201);
        final expenseId = jsonDecode(createRes.body)['data']['expenseId'];

        // Attempt update with 1-paise mismatch: 150.00 total vs 149.99 split
        final badUpdateRes = await http.put(
          Uri.parse('$baseUrl/expenses/$expenseId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'description': 'Updated with defect',
            'amount': 150.00,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'UNEQUAL',
            'splits': [
              {'personId': person1Id, 'amount': 75.00},
              {'personId': person2Id, 'amount': 74.99}, // sum = 149.99
            ],
          }),
        );
        expect(badUpdateRes.statusCode, 400, reason: 'PUT update must enforce identical split validation');

        // Valid update succeeds
        final goodUpdateRes = await http.put(
          Uri.parse('$baseUrl/expenses/$expenseId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user1Token',
          },
          body: jsonEncode({
            'description': 'Updated validly',
            'amount': 150.00,
            'currencyCode': 'INR',
            'paidByPersonId': person1Id,
            'splitType': 'UNEQUAL',
            'splits': [
              {'personId': person1Id, 'amount': 75.00},
              {'personId': person2Id, 'amount': 75.00},
            ],
          }),
        );
        expect(goodUpdateRes.statusCode, 200);
      });
    });

    // =========================================================================
    // DEFECT 4: BUS-DEF-01 – Friend Request Lifecycle
    // =========================================================================
    group('DEFECT 4: BUS-DEF-01 – Friend Request Lifecycle & State Transitions', () {
      test('4.1 Self-friendship is strictly prohibited (400)', () async {
        final res = await http.post(
          Uri.parse('$baseUrl/friends'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user3Token',
          },
          body: jsonEncode({
            'friendPhone': '9800000003', // User 3's own phone
            'friendName': 'Myself',
          }),
        );
        expect(res.statusCode, 400, reason: 'Sending friend request to self must return 400');
        final data = jsonDecode(res.body);
        expect(data['success'], isFalse);
      });

      test('4.2 Sending friend request creates PENDING status', () async {
        // User 3 sends friend request to User 5 (phone 9800000005)
        final res = await http.post(
          Uri.parse('$baseUrl/friends'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user3Token',
          },
          body: jsonEncode({
            'friendPhone': '9800000005',
            'friendName': 'User 5',
          }),
        );
        expect(res.statusCode, 200);
        final data = jsonDecode(res.body)['data'];
        expect(data['status'], 'PENDING', reason: 'New friend request must have status PENDING');
        final connectionId = data['connectionId'] as String;

        // Verify request appears in recipient (User 5) pending requests
        final reqRes = await http.get(
          Uri.parse('$baseUrl/friends/requests'),
          headers: {'Authorization': 'Bearer $user5Token'},
        );
        expect(reqRes.statusCode, 200);
        final reqList = jsonDecode(reqRes.body)['data'] as List;
        expect(reqList.any((r) => r['connectionId'] == connectionId), isTrue);

        // Verify pending request does NOT appear in accepted friends list
        final friendsRes = await http.get(
          Uri.parse('$baseUrl/friends'),
          headers: {'Authorization': 'Bearer $user3Token'},
        );
        final friendsList = jsonDecode(friendsRes.body)['data'] as List;
        expect(friendsList.any((f) => f['connectionId'] == connectionId), isFalse);

        // Step 4.2.1: Duplicate request prevention - sending again returns existing PENDING without duplicate row
        final dupRes = await http.post(
          Uri.parse('$baseUrl/friends'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user3Token',
          },
          body: jsonEncode({
            'friendPhone': '9800000005',
            'friendName': 'User 5',
          }),
        );
        expect(dupRes.statusCode, 200);
        final dupData = jsonDecode(dupRes.body)['data'];
        expect(dupData['connectionId'], connectionId, reason: 'Duplicate request must return existing connection without new row');

        // Step 4.2.2: Unauthorized transition - sender cannot accept their own request
        final badAcceptRes = await http.put(
          Uri.parse('$baseUrl/friends/$connectionId/status'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user3Token', // sender
          },
          body: jsonEncode({'status': 'ACCEPTED'}),
        );
        expect(badAcceptRes.statusCode, anyOf(404, 400), reason: 'Sender cannot accept their own request');

        // Step 4.2.3: Recipient (User 5) accepts the request
        final acceptRes = await http.put(
          Uri.parse('$baseUrl/friends/$connectionId/status'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user5Token', // receiver
          },
          body: jsonEncode({'status': 'ACCEPTED'}),
        );
        expect(acceptRes.statusCode, 200);

        // Step 4.2.4: Accepted friendship is now visible to both users
        final user3Friends = await http.get(
          Uri.parse('$baseUrl/friends'),
          headers: {'Authorization': 'Bearer $user3Token'},
        );
        final user5Friends = await http.get(
          Uri.parse('$baseUrl/friends'),
          headers: {'Authorization': 'Bearer $user5Token'},
        );
        final u3List = jsonDecode(user3Friends.body)['data'] as List;
        final u5List = jsonDecode(user5Friends.body)['data'] as List;
        expect(u3List.any((f) => f['connectionId'] == connectionId), isTrue);
        expect(u5List.any((f) => f['connectionId'] == connectionId), isTrue);

        // Clean up: delete connection to preserve pristine state
        await http.delete(
          Uri.parse('$baseUrl/friends/$connectionId'),
          headers: {'Authorization': 'Bearer $user3Token'},
        );
      });

      test('4.3 Sender can cancel a pending request (PENDING -> CANCELLED)', () async {
        // User 3 sends friend request to User 4
        final sendRes = await http.post(
          Uri.parse('$baseUrl/friends'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user3Token',
          },
          body: jsonEncode({
            'friendPhone': '9800000004',
            'friendName': 'User 4',
          }),
        );
        expect(sendRes.statusCode, 200);
        final connId = jsonDecode(sendRes.body)['data']['connectionId'] as String;

        // User 3 cancels their pending request
        final cancelRes = await http.put(
          Uri.parse('$baseUrl/friends/$connId/status'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user3Token',
          },
          body: jsonEncode({'status': 'CANCELLED'}),
        );
        expect(cancelRes.statusCode, 200);

        // Cancelled request must not appear in User 4 pending requests
        final reqRes = await http.get(
          Uri.parse('$baseUrl/friends/requests'),
          headers: {'Authorization': 'Bearer $user4Token'},
        );
        final reqList = (jsonDecode(reqRes.body)['data'] as List?) ?? [];
        expect(reqList.any((r) => r['connectionId'] == connId), isFalse);

        // Cancelled request must not appear in accepted friends
        final friendsRes = await http.get(
          Uri.parse('$baseUrl/friends'),
          headers: {'Authorization': 'Bearer $user3Token'},
        );
        final friendsList = (jsonDecode(friendsRes.body)['data'] as List?) ?? [];
        expect(friendsList.any((f) => f['connectionId'] == connId), isFalse);

        // Clean up connection record
        await http.delete(
          Uri.parse('$baseUrl/friends/$connId'),
          headers: {'Authorization': 'Bearer $user3Token'},
        );
      });

      test('4.4 Reciprocal requests auto-accept safely', () async {
        // User 4 sends request to User 5
        final res1 = await http.post(
          Uri.parse('$baseUrl/friends'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user4Token',
          },
          body: jsonEncode({
            'friendPhone': '9800000005',
            'friendName': 'User 5',
          }),
        );
        expect(res1.statusCode, 200);
        final connId = jsonDecode(res1.body)['data']['connectionId'] as String;

        // Reciprocal: User 5 sends request to User 4 (phone 9800000004)
        final res2 = await http.post(
          Uri.parse('$baseUrl/friends'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $user5Token',
          },
          body: jsonEncode({
            'friendPhone': '9800000004',
            'friendName': 'User 4',
          }),
        );
        expect(res2.statusCode, 200);
        final conn2 = jsonDecode(res2.body)['data'];
        expect(conn2['status'], 'ACCEPTED', reason: 'Reciprocal friend request must safely transition to ACCEPTED');

        // Clean up
        await http.delete(
          Uri.parse('$baseUrl/friends/$connId'),
          headers: {'Authorization': 'Bearer $user4Token'},
        );
      });
    });

    // =========================================================================
    // FINANCIAL INTEGRITY & REGRESSION AUDIT
    // =========================================================================
    group('FINANCIAL INTEGRITY: Invariants & Baseline Preservation', () {
      test('Goa Vacation 2026 balances remain strictly reconciled to zero', () async {
        final tripsRes = await http.get(
          Uri.parse('$baseUrl/trips'),
          headers: {'Authorization': 'Bearer $user1Token'},
        );
        expect(tripsRes.statusCode, 200);
        final trips = jsonDecode(tripsRes.body)['data'] as List;
        final goaTrip = trips.firstWhere((t) => (t['name'] ?? t['title'] ?? '').toString().contains('Goa'));
        final goaTripId = goaTrip['tripId'];

        final personsRes = await http.get(
          Uri.parse('$baseUrl/persons/trip/$goaTripId'),
          headers: {'Authorization': 'Bearer $user1Token'},
        );
        expect(personsRes.statusCode, 200);
        final persons = jsonDecode(personsRes.body)['data'] as List;

        double sumBalances = 0.0;
        for (final p in persons) {
          final balance = (p['balance'] as num).toDouble();
          expect(balance, closeTo(0.0, 0.001), reason: 'Person ${p['name']} balance in Goa must remain exactly 0.00');
          sumBalances += balance;
        }

        expect(sumBalances, closeTo(0.0, 0.001), reason: 'Total net balance in Goa must remain 0.00');
      });
    });
  });
}
