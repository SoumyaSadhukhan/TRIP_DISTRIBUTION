import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const baseUrl = 'http://localhost:5262/api';
  late String user1Token;
  late String user2Token;

  setUpAll(() async {
    // Authenticate test user 1
    final login1Res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': '9800000001',
        'email': 'testuser1@example.com',
        'password': 'Test@12345',
      }),
    );
    expect(login1Res.statusCode, 200);
    user1Token = jsonDecode(login1Res.body)['data']['token'];

    // Authenticate test user 2
    final login2Res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': '9800000002',
        'email': 'testuser2@example.com',
        'password': 'Test@12345',
      }),
    );
    expect(login2Res.statusCode, 200);
    user2Token = jsonDecode(login2Res.body)['data']['token'];
  });

  group('1. Email vs Phone Separation for Auth and Friends', () {
    test('1.1 Registration OTP targets Email strictly; Phone is optional', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': 'verify_email_separation@example.com',
          'purpose': 'REGISTER',
          'environment': 'debug',
        }),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body);
      expect(body['success'], true);
      expect(body['data']['email'], 'verify_email_separation@example.com');
      expect(body['data']['otpCode'], isNotNull);
      expect(body['data']['message'], contains('email'));
    });

    test('1.2 Forgot Password OTP targets Email strictly', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': 'testuser1@example.com',
          'purpose': 'FORGOT_PASSWORD',
          'environment': 'debug',
        }),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body);
      expect(body['success'], true);
      expect(body['data']['email'], 'testuser1@example.com');
      expect(body['data']['otpCode'], '123456');
    });

    test('1.3 Production environment mode hides OTP code from response', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': 'testuser2@example.com',
          'purpose': 'FORGOT_PASSWORD',
          'environment': 'production',
        }),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body);
      expect(body['success'], true);
      // In production mode, otpCode MUST be null (never exposed to UI or network packet)
      expect(body['data']['otpCode'], isNull);
    });
  });

  group('2. Friend Section User Name Display', () {
    test('2.1 Friends list returns actual user name instead of generic "Friend"', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/friends'),
        headers: {'Authorization': 'Bearer $user1Token'},
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body);
      final List friends = body['data'];
      expect(friends.isNotEmpty, true);

      for (final f in friends) {
        final friendName = f['friendName'];
        expect(friendName, isNotNull);
        expect(friendName, isNot(equals('Friend')));
        expect(friendName, contains('User'));
      }
    });

    test('2.2 Reciprocal friend query returns User 1 name for User 2', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/friends'),
        headers: {'Authorization': 'Bearer $user2Token'},
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body);
      final List friends = body['data'];
      expect(friends.isNotEmpty, true);

      final friendItem = friends.firstWhere((f) => f['friendPhone'] == '9800000001');
      expect(friendItem['friendName'], 'User 1');
      expect(friendItem['friendName'], isNot(equals('Friend')));
    });

    test('2.3 Friend request search by phone connects users without exposing auth OTPs', () async {
      // User 1 searches or invites User 3 by phone number 9800000003
      final searchRes = await http.post(
        Uri.parse('$baseUrl/friends/search'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $user1Token',
        },
        body: jsonEncode({'phone': '9800000003'}),
      );
      expect(searchRes.statusCode, 200);
      final body = jsonDecode(searchRes.body);
      expect(body['success'], true);
      final List matches = body['data'];
      expect(matches.isNotEmpty, true);
      final match = matches.first;
      final matchedName = match['fullName'] ?? match['name'];
      expect(matchedName, 'User 3');
      expect(matchedName, isNot(equals('Friend')));
    });
  });
}
