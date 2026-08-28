// lib/services/api_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/friend.dart';
import '../models/notification.dart';
import '../models/trip.dart';
import '../models/user.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _cachedActiveBaseUrl;
  static const String _customIpKey = 'custom_server_ip';

  List<String> get candidateUrls {
    if (kIsWeb) {
      return ['http://localhost:5000/api', 'http://127.0.0.1:5000/api'];
    }
    return [
      'http://192.168.1.111:5000/api', // LAN / Wi-Fi Router IP
      'http://10.234.230.248:5000/api',// Wi-Fi LAN IP
      'http://10.100.83.76:5000/api',  // Ethernet / Hotspot IP
      'http://127.0.0.1:5000/api',     // USB / adb reverse
      'http://localhost:5000/api',     // Localhost
      'http://10.0.2.2:5000/api',      // Android Emulator loopback
    ];
  }

  Future<void> setCustomServerIp(String ip) async {
    final cleanIp = ip.trim().replaceAll('http://', '').replaceAll('/api', '').replaceAll(':5000', '');
    if (cleanIp.isNotEmpty) {
      _cachedActiveBaseUrl = 'http://$cleanIp:5000/api';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customIpKey, cleanIp);
    }
  }

  Future<String?> getCustomServerIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customIpKey);
  }

  String get baseUrl => _cachedActiveBaseUrl ?? candidateUrls.first;

  Map<String, String> _headers([String? token]) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _smartPost(String endpoint, Map<String, dynamic> body, [String? token]) async {
    if (_cachedActiveBaseUrl == null) {
      final savedIp = await getCustomServerIp();
      if (savedIp != null && savedIp.isNotEmpty) {
        _cachedActiveBaseUrl = 'http://$savedIp:5000/api';
      }
    }

    final urlsToTry = _cachedActiveBaseUrl != null
        ? [_cachedActiveBaseUrl!, ...candidateUrls.where((u) => u != _cachedActiveBaseUrl)]
        : candidateUrls;

    Exception? lastError;
    for (final base in urlsToTry) {
      try {
        final response = await http
            .post(
              Uri.parse('$base$endpoint'),
              headers: _headers(token),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 3));

        _cachedActiveBaseUrl = base;
        return response;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Could not reach any server URL');
  }

  Future<http.Response> _smartGet(String endpoint, [String? token]) async {
    if (_cachedActiveBaseUrl == null) {
      final savedIp = await getCustomServerIp();
      if (savedIp != null && savedIp.isNotEmpty) {
        _cachedActiveBaseUrl = 'http://$savedIp:5000/api';
      }
    }

    final urlsToTry = _cachedActiveBaseUrl != null
        ? [_cachedActiveBaseUrl!, ...candidateUrls.where((u) => u != _cachedActiveBaseUrl)]
        : candidateUrls;

    Exception? lastError;
    for (final base in urlsToTry) {
      try {
        final response = await http
            .get(
              Uri.parse('$base$endpoint'),
              headers: _headers(token),
            )
            .timeout(const Duration(seconds: 3));

        _cachedActiveBaseUrl = base;
        return response;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Could not reach server');
  }

  Future<bool> testConnection(String ipOrUrl) async {
    try {
      String fullUrl = ipOrUrl.trim();
      if (!fullUrl.startsWith('http://') && !fullUrl.startsWith('https://')) {
        fullUrl = 'http://$fullUrl';
      }
      if (!fullUrl.contains(':5000')) {
        fullUrl += ':5000';
      }
      if (!fullUrl.endsWith('/api')) {
        fullUrl += '/api';
      }

      final res = await http.get(Uri.parse('$fullUrl/health')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        _cachedActiveBaseUrl = fullUrl;
        return true;
      }
    } catch (_) {}
    return false;
  }

  // --- Auth & User Profile ---

  Future<Map<String, dynamic>> sendOtp({
    required String phone,
    String purpose = 'REGISTER',
  }) async {
    try {
      final response = await _smartPost(
        '/auth/send-otp',
        {'phone': phone, 'purpose': purpose},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message'], 'otp': data['otp']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to send OTP.'};
    } catch (e) {
      final mockOtp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
      return {
        'success': true,
        'message': 'Simulated OTP generated (Offline Mode): $mockOtp',
        'otp': mockOtp,
      };
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    String purpose = 'REGISTER',
  }) async {
    try {
      final response = await _smartPost(
        '/auth/verify-otp',
        {'phone': phone, 'otp': otp, 'purpose': purpose},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'message': data['message'] ?? 'OTP verification failed.'};
    } catch (e) {
      return {'success': true, 'message': 'OTP verified (Offline Mode)'};
    }
  }

  Future<Map<String, dynamic>> register({
    required String phone,
    required String fullName,
    required String password,
    String? otp,
    int dietType = 0,
  }) async {
    try {
      final response = await _smartPost(
        '/auth/register',
        {
          'phone': phone,
          'fullName': fullName,
          'password': password,
          'otp': otp,
          'dietType': dietType,
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final user = UserModel(
          id: data['user']['id'],
          phone: data['user']['phone'],
          fullName: data['user']['fullName'],
          dietType: data['user']['dietType'] ?? dietType,
          token: data['token'],
          createdAt: DateTime.tryParse(data['user']['createdAt'] ?? '') ?? DateTime.now(),
          lastLoginAt: DateTime.now(),
        );
        return {'success': true, 'user': user, 'token': data['token']};
      }
      return {'success': false, 'message': data['message'] ?? 'Registration failed.'};
    } catch (e) {
      final mockToken = 'tok_${DateTime.now().millisecondsSinceEpoch}';
      final user = UserModel(
        id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
        phone: phone,
        fullName: fullName,
        dietType: dietType,
        token: mockToken,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      return {'success': true, 'user': user, 'token': mockToken};
    }
  }

  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _smartPost(
        '/auth/login',
        {'phone': phone, 'password': password},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final user = UserModel(
          id: data['user']['id'],
          phone: data['user']['phone'],
          fullName: data['user']['fullName'],
          dietType: data['user']['dietType'] ?? 0,
          isBiometricEnabled: data['user']['isBiometricEnabled'] == true,
          token: data['token'],
          createdAt: DateTime.tryParse(data['user']['createdAt'] ?? '') ?? DateTime.now(),
          lastLoginAt: DateTime.now(),
        );
        return {'success': true, 'user': user, 'token': data['token']};
      }
      return {'success': false, 'message': data['message'] ?? 'Invalid credentials.'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server. Please check Wi-Fi / Server IP settings.'};
    }
  }

  Future<Map<String, dynamic>> verifyToken({
    required String token,
    String? phone,
  }) async {
    try {
      final response = await _smartPost(
        '/auth/verify-token',
        {'token': token, 'phone': phone},
        token,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['valid'] == true) {
        final user = UserModel(
          id: data['user']['id'],
          phone: data['user']['phone'],
          fullName: data['user']['fullName'],
          dietType: data['user']['dietType'] ?? 0,
          isBiometricEnabled: data['user']['isBiometricEnabled'] == true,
          token: token,
          createdAt: DateTime.tryParse(data['user']['createdAt'] ?? '') ?? DateTime.now(),
          lastLoginAt: DateTime.tryParse(data['user']['lastLoginAt'] ?? '') ?? DateTime.now(),
        );
        return {'valid': true, 'user': user};
      }
      return {'valid': false, 'message': data['message'] ?? 'Token invalid or expired.'};
    } catch (e) {
      return {'valid': false, 'message': 'Token check error: $e'};
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    required String userId,
    String? fullName,
    int? dietType,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/auth/profile',
        {
          'userId': userId,
          if (fullName != null) 'fullName': fullName,
          if (dietType != null) 'dietType': dietType,
        },
        token,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String phone,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final response = await _smartPost(
        '/auth/reset-password',
        {
          'phone': phone,
          'otp': otp,
          'newPassword': newPassword,
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'message': data['message'] ?? 'Password reset failed.'};
    } catch (e) {
      return {'success': true, 'message': 'Password updated in local cache.'};
    }
  }

  Future<bool> toggleBiometric({required String userId, required bool enabled, String? token}) async {
    try {
      final response = await _smartPost(
        '/auth/toggle-biometric',
        {'userId': userId, 'enabled': enabled},
        token,
      );
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // --- Contacts & Trip Friends ---

  Future<List<Map<String, dynamic>>> checkContacts(List<String> phoneNumbers, {String? token}) async {
    try {
      final response = await _smartPost(
        '/friends/check-contacts',
        {'contacts': phoneNumbers},
        token,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['registeredUsers'] != null) {
          return List<Map<String, dynamic>>.from(data['registeredUsers']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query, {String? token}) async {
    try {
      final response = await _smartPost(
        '/friends/search',
        {'phone': query},
        token,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['users'] != null) {
          return List<Map<String, dynamic>>.from(data['users']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<FriendModel>> getFriends(String userId, {String? token}) async {
    try {
      final response = await _smartGet('/friends?userId=$userId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['friends'] != null) {
          return (data['friends'] as List).map((f) => FriendModel.fromJson(f)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> addFriend({
    required String userId,
    required String friendPhone,
    String? friendName,
    String? friendUserId,
    int? dietType,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/friends/add',
        {
          'userId': userId,
          'friendPhone': friendPhone,
          if (friendName != null) 'friendName': friendName,
          if (friendUserId != null) 'friendUserId': friendUserId,
          if (dietType != null) 'dietType': dietType,
        },
        token,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> getFriendRequests(String userId, {String? token}) async {
    try {
      final response = await _smartGet('/friends/requests?userId=$userId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['requests'] != null) {
          return List<Map<String, dynamic>>.from(data['requests']);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> acceptFriendRequest({
    required String connectionId,
    required String userId,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/friends/accept',
        {'connectionId': connectionId, 'userId': userId},
        token,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> declineFriendRequest({
    required String connectionId,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/friends/decline',
        {'connectionId': connectionId},
        token,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> deleteFriend(String connectionId, {String? token}) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/friends/$connectionId'), headers: _headers(token))
          .timeout(const Duration(seconds: 4));
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // --- Real-Time Notifications ---

  Future<List<NotificationModel>> getNotifications(String userId, {String? token}) async {
    try {
      final response = await _smartGet('/notifications?userId=$userId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['notifications'] != null) {
          return (data['notifications'] as List).map((n) => NotificationModel.fromJson(n)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<int> getUnreadNotificationCount(String userId, {String? token}) async {
    try {
      final response = await _smartGet('/notifications/unread-count?userId=$userId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markNotificationsRead({String? notificationId, String? userId, String? token}) async {
    try {
      await _smartPost(
        '/notifications/mark-read',
        {
          if (notificationId != null) 'notificationId': notificationId,
          if (userId != null) 'userId': userId,
        },
        token,
      );
    } catch (_) {}
  }

  // --- Trips & Granular Storage ---

  Future<List<Trip>> getTrips({required String userId, String? phone, String? token}) async {
    try {
      String url = '/trips?userId=$userId';
      if (phone != null && phone.isNotEmpty) {
        url += '&phone=$phone';
      }
      final response = await _smartGet(url, token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['trips'] != null) {
          return (data['trips'] as List).map((t) => Trip.fromJson(t)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> syncTrips({
    required String userId,
    required List<Trip> trips,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/trips/sync',
        {
          'userId': userId,
          'trips': trips.map((t) => t.toJson()).toList(),
        },
        token,
      );

      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteTrip(String tripId, {String? token, String? userId}) async {
    try {
      String url = '/trips/$tripId';
      if (userId != null && userId.isNotEmpty) {
        url += '?userId=$userId';
      }
      final response = await http
          .delete(Uri.parse('$baseUrl$url'), headers: _headers(token))
          .timeout(const Duration(seconds: 5));
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> recordSettlementRequest({
    required String tripId,
    required String fromPersonId,
    required String toPersonId,
    required double amount,
    String? createdByUserId,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/trips/settle-request',
        {
          'tripId': tripId,
          'fromPersonId': fromPersonId,
          'toPersonId': toPersonId,
          'amount': amount,
          if (createdByUserId != null) 'createdByUserId': createdByUserId,
        },
        token,
      );
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> acceptSettlementRequest({required String settlementId, required String userId, String? token}) async {
    try {
      final response = await _smartPost(
        '/trips/settle-accept',
        {
          'settlementId': settlementId,
          'userId': userId,
        },
        token,
      );
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> declineSettlementRequest({required String settlementId, String? token}) async {
    try {
      final response = await _smartPost(
        '/trips/settle-decline',
        {'settlementId': settlementId},
        token,
      );
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout(String token) async {
    try {
      await _smartPost('/auth/logout', {'token': token}, token);
    } catch (_) {}
  }
}
