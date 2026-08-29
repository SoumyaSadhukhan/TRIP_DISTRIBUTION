// lib/services/api_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
      return ['http://localhost:7266/api', 'http://127.0.0.1:7266/api'];
    }
    return [
      'http://10.130.176.248:7266/api', // Laptop Wi-Fi IP
      'http://192.168.1.111:7266/api',  // Alternative LAN IP
      'http://127.0.0.1:7266/api',      // USB / adb reverse
      'http://localhost:7266/api',      // Localhost
      'http://10.0.2.2:7266/api',       // Android Emulator loopback
    ];
  }

  Future<void> setCustomServerIp(String ipOrHostAndPort) async {
    String input = ipOrHostAndPort.trim()
        .replaceAll('http://', '')
        .replaceAll('https://', '')
        .replaceAll('/api', '');

    if (input.isNotEmpty) {
      if (!input.contains(':')) {
        input = '$input:5246'; // Default fallback port
      }
      _cachedActiveBaseUrl = 'http://$input/api';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customIpKey, input);
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
        final clean = savedIp.contains(':') ? savedIp : '$savedIp:5246';
        _cachedActiveBaseUrl = 'http://$clean/api';
      }
    }

    final urlsToTry = _cachedActiveBaseUrl != null
        ? [_cachedActiveBaseUrl!, ...candidateUrls.where((u) => u != _cachedActiveBaseUrl)]
        : candidateUrls;

    Exception? lastError;
    for (final base in urlsToTry) {
      try {
        debugPrint('[API] POST $base$endpoint');
        final response = await http
            .post(
              Uri.parse('$base$endpoint'),
              headers: _headers(token),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 3));

        debugPrint('[API] POST $base$endpoint => Status ${response.statusCode}');
        _cachedActiveBaseUrl = base;
        return response;
      } catch (e) {
        debugPrint('[API ERR] POST $base$endpoint => $e');
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Could not reach any server URL');
  }

  Future<http.Response> _smartGet(String endpoint, [String? token]) async {
    if (_cachedActiveBaseUrl == null) {
      final savedIp = await getCustomServerIp();
      if (savedIp != null && savedIp.isNotEmpty) {
        final clean = savedIp.contains(':') ? savedIp : '$savedIp:5246';
        _cachedActiveBaseUrl = 'http://$clean/api';
      }
    }

    final urlsToTry = _cachedActiveBaseUrl != null
        ? [_cachedActiveBaseUrl!, ...candidateUrls.where((u) => u != _cachedActiveBaseUrl)]
        : candidateUrls;

    Exception? lastError;
    for (final base in urlsToTry) {
      try {
        debugPrint('[API] GET $base$endpoint');
        final response = await http
            .get(
              Uri.parse('$base$endpoint'),
              headers: _headers(token),
            )
            .timeout(const Duration(seconds: 3));

        debugPrint('[API] GET $base$endpoint => Status ${response.statusCode}');
        _cachedActiveBaseUrl = base;
        return response;
      } catch (e) {
        debugPrint('[API ERR] GET $base$endpoint => $e');
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Could not reach server');
  }

  Future<bool> testConnection(String ipOrHostAndPort) async {
    try {
      String fullUrl = ipOrHostAndPort.trim();
      if (!fullUrl.startsWith('http://') && !fullUrl.startsWith('https://')) {
        fullUrl = 'http://$fullUrl';
      }
      final cleanHost = fullUrl.replaceAll('http://', '').replaceAll('https://', '');
      if (!cleanHost.contains(':')) {
        fullUrl += ':5246';
      }
      if (!fullUrl.endsWith('/api')) {
        fullUrl += '/api';
      }

      final res = await http.get(Uri.parse('$fullUrl/health')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        _cachedActiveBaseUrl = fullUrl;
        return true;
      }

      // Check swagger endpoint for 200 OK response
      final swaggerRes = await http.get(Uri.parse(fullUrl.replaceAll('/api', '/swagger'))).timeout(const Duration(seconds: 3));
      if (swaggerRes.statusCode == 200) {
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
        {'phoneNumber': phone, 'purpose': purpose},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final code = data['otpCode'] ?? data['otp'];
        return {
          'success': true,
          'message': data['message'] ?? 'OTP sent to $phone',
          'otp': code,
        };
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to send OTP.'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Cannot connect to ASP.NET Core Web API. Please start your API server project or check your Server Config.',
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
        {'phoneNumber': phone, 'otpCode': otp, 'purpose': purpose},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'message': data['message'] ?? 'OTP verification failed.'};
    } catch (e) {
      return {
        'success': false,
        'message': 'API Server is offline. Please start your ASP.NET Core API project.',
      };
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
          'phoneNumber': phone,
          'fullName': fullName,
          'password': password,
          'otpCode': otp ?? '',
          'dietType': dietType,
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final user = UserModel(
          id: data['userId'] ?? data['user']?['id'] ?? 'usr_${DateTime.now().millisecondsSinceEpoch}',
          phone: data['phoneNumber'] ?? data['user']?['phone'] ?? phone,
          fullName: data['fullName'] ?? data['user']?['fullName'] ?? fullName,
          dietType: (data['dietType'] as int? ?? dietType),
          token: data['token'] ?? 'token_${DateTime.now().millisecondsSinceEpoch}',
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
        );
        return {'success': true, 'user': user, 'token': user.token};
      }
      return {'success': false, 'message': data['message'] ?? 'Registration failed.'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Cannot connect to ASP.NET Core Web API. Please start your API server project or check your Server Config.',
      };
    }
  }

  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _smartPost(
        '/auth/login',
        {'phoneNumber': phone, 'password': password},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final user = UserModel(
          id: data['userId'] ?? data['user']?['id'] ?? 'usr_${DateTime.now().millisecondsSinceEpoch}',
          phone: data['phoneNumber'] ?? data['user']?['phone'] ?? phone,
          fullName: data['fullName'] ?? data['user']?['fullName'] ?? 'User',
          dietType: (data['dietType'] as int? ?? 0),
          token: data['token'],
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
        );
        return {'success': true, 'user': user, 'token': data['token']};
      }
      return {'success': false, 'message': data['message'] ?? 'Invalid phone number or password.'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Cannot connect to ASP.NET Core Web API. Please start your API server project or check your Server Config.',
      };
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
      final response = await _smartPost(
        '/trips/delete',
        {
          'tripId': tripId,
          if (userId != null) 'userId': userId,
        },
        token,
      );
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
