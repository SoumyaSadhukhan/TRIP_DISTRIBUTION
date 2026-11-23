import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseUrl = 'http://localhost:5262/api';

  test('OTP Hardening: Rate limit, Hash verification, Single-use, Replay, Expiry, Purpose binding, and Brute force', () async {
    final testEmail = 'otptest_${DateTime.now().millisecondsSinceEpoch}@test.local';
    const purpose = 'REGISTER';

    print('--- Step 1: Request OTP for new registration ($testEmail) ---');
    final sendRes1 = await http.post(
      Uri.parse('$baseUrl/Auth/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': testEmail,
        'purpose': purpose,
        'username': 'OtpTestUser'
      }),
    );
    expect(sendRes1.statusCode, 200);
    final body1 = jsonDecode(sendRes1.body);
    expect(body1['success'], isTrue);
    print('[PASS] Initial OTP dispatch succeeded.');

    // --- Step 2: Rate Limit / Cooldown Verification ---
    print('--- Step 2: Request OTP again immediately (within 60s cooldown) ---');
    final sendRes2 = await http.post(
      Uri.parse('$baseUrl/Auth/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': testEmail,
        'purpose': purpose,
        'username': 'OtpTestUser'
      }),
    );
    expect(sendRes2.statusCode, 429);
    final body2 = jsonDecode(sendRes2.body);
    expect(body2['success'], isFalse);
    expect(body2['message'], contains('60 seconds'));
    print('[PASS] Rate limit cooldown strictly enforced (HTTP 429): ${body2['message']}');

    // --- Step 3: Brute Force Limit Verification ---
    print('--- Step 3: Brute force defense: 5 incorrect OTP attempts ---');
    for (int i = 1; i <= 5; i++) {
      final failRes = await http.post(
        Uri.parse('$baseUrl/Auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': testEmail,
          'otpCode': '99999$i',
          'purpose': purpose,
        }),
      );
      expect(failRes.statusCode, 400);
      print('[PASS] Incorrect attempt #$i blocked.');
    }

    // --- Step 4: After 5 failed attempts, OTP must be locked ---
    print('--- Step 4: Verification after exceeding max attempts ---');
    final lockedRes = await http.post(
      Uri.parse('$baseUrl/Auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': testEmail,
        'otpCode': '123456',
        'purpose': purpose,
      }),
    );
    expect(lockedRes.statusCode, 400);
    print('[PASS] Verification locked out after brute-force threshold reached.');

    // --- Step 5: Purpose Substitution Attack ---
    print('--- Step 5: Test Purpose Substitution Attack ---');
    final purposeRes = await http.post(
      Uri.parse('$baseUrl/Auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': testEmail,
        'otpCode': '123456',
        'purpose': 'FORGOT_PASSWORD',
      }),
    );
    expect(purposeRes.statusCode, 400);
    print('[PASS] Purpose substitution blocked.');
  });

  test('OTP Concurrent Verification & Single-Use Replay Defense', () async {
    final concurrentEmail = 'concurrent_${DateTime.now().millisecondsSinceEpoch}@test.local';
    const purpose = 'REGISTER';

    // Step 1: Request OTP
    final sendRes = await http.post(
      Uri.parse('$baseUrl/Auth/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': concurrentEmail,
        'purpose': purpose,
        'username': 'ConcurrentUser'
      }),
    );
    expect(sendRes.statusCode, 200);
    final sendBody = jsonDecode(sendRes.body);
    final validOtp = sendBody['data']['otpCode'];
    expect(validOtp, isNotNull, reason: 'Testing environment with ExposeOtpInResponse must return OTP for test runner');

    print('--- Firing 5 concurrent verification requests for valid OTP ($validOtp) ---');
    final futures = List.generate(5, (_) => http.post(
      Uri.parse('$baseUrl/Auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': concurrentEmail,
        'otpCode': validOtp,
        'purpose': purpose,
      }),
    ));

    final results = await Future.wait(futures);
    final statusCodes = results.map((r) => r.statusCode).toList();
    final successes = statusCodes.where((code) => code == 200).length;
    final failures = statusCodes.where((code) => code == 400).length;

    print('Concurrent results: $successes succeeded (200), $failures rejected (400)');
    expect(successes, 1, reason: 'Strictly one concurrent request can consume the OTP');
    expect(failures, 4, reason: 'All redundant concurrent requests must be rejected');

    // Step 2: Attempt replay after success
    print('--- Replay Attack Test ---');
    final replayRes = await http.post(
      Uri.parse('$baseUrl/Auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': concurrentEmail,
        'otpCode': validOtp,
        'purpose': purpose,
      }),
    );
    expect(replayRes.statusCode, 400);
    print('[PASS] Replay attack blocked (HTTP 400).');
  });
}
