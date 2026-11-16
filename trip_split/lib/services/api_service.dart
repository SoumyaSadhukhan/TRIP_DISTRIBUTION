// lib/services/api_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_log.dart';
import '../models/collaborator.dart';
import '../models/friend.dart';
import '../models/notification.dart';
import '../models/settlement_proposal.dart';
import '../models/trip.dart';
import '../models/user.dart';

/// Complete, production-grade API Client covering all 54 endpoints across all 10 controllers
/// in the TripDistribution API backend (.NET 9 / SQL Server SPLIT_BILL_DB).
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  ApiService.test();

  String? _cachedActiveBaseUrl;
  String? _cachedToken;
  static const String _customIpKey = 'custom_server_ip';

  void setAuthToken(String? token) {
    _cachedToken = token;
  }

  String? get activeToken => _cachedToken;

  List<String> get candidateUrls {
    return [
      'http://127.0.0.1:5262/api',
      'http://localhost:5262/api',
    ];
  }

  Future<void> setCustomServerIp(String ipOrHostAndPort) async {
    String input = ipOrHostAndPort
        .trim()
        .replaceAll('http://', '')
        .replaceAll('https://', '')
        .replaceAll('/api', '');

    if (input.isNotEmpty) {
      if (!input.contains(':')) {
        input = '$input:5262';
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
    final effectiveToken = token ?? _cachedToken;
    final headers = {'Content-Type': 'application/json'};
    if (effectiveToken != null && effectiveToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $effectiveToken';
    }
    return headers;
  }

  String _normalizeEndpoint(String base, String endpoint) {
    var b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    var ep = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    if (b.toLowerCase().endsWith('/api') && ep.toLowerCase().startsWith('/api/')) {
      ep = ep.substring(4);
    }
    return '$b$ep';
  }

  Future<http.Response> _smartPost(String endpoint, dynamic body, [String? token]) async {
    final urlsToTry = _cachedActiveBaseUrl != null
        ? [_cachedActiveBaseUrl!, ...candidateUrls.where((u) => u != _cachedActiveBaseUrl)]
        : candidateUrls;

    Exception? lastError;
    for (final base in urlsToTry) {
      try {
        final fullUrl = _normalizeEndpoint(base, endpoint);
        debugPrint('[API] POST $fullUrl');
        final response = await http
            .post(
              Uri.parse(fullUrl),
              headers: _headers(token),
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(const Duration(seconds: 5));

        debugPrint('[API] POST $fullUrl => Status ${response.statusCode}');
        _cachedActiveBaseUrl = base;
        return response;
      } catch (e) {
        debugPrint('[API ERR] POST $base$endpoint => $e');
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Could not reach any server URL');
  }

  Future<http.Response> _smartPut(String endpoint, dynamic body, [String? token]) async {
    final urlsToTry = _cachedActiveBaseUrl != null
        ? [_cachedActiveBaseUrl!, ...candidateUrls.where((u) => u != _cachedActiveBaseUrl)]
        : candidateUrls;

    Exception? lastError;
    for (final base in urlsToTry) {
      try {
        final fullUrl = _normalizeEndpoint(base, endpoint);
        debugPrint('[API] PUT $fullUrl');
        final response = await http
            .put(
              Uri.parse(fullUrl),
              headers: _headers(token),
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(const Duration(seconds: 5));

        debugPrint('[API] PUT $fullUrl => Status ${response.statusCode}');
        _cachedActiveBaseUrl = base;
        return response;
      } catch (e) {
        debugPrint('[API ERR] PUT $base$endpoint => $e');
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Could not reach any server URL');
  }

  Future<http.Response> _smartGet(String endpoint, [String? token]) async {
    final urlsToTry = _cachedActiveBaseUrl != null
        ? [_cachedActiveBaseUrl!, ...candidateUrls.where((u) => u != _cachedActiveBaseUrl)]
        : candidateUrls;

    Exception? lastError;
    for (final base in urlsToTry) {
      try {
        final fullUrl = _normalizeEndpoint(base, endpoint);
        debugPrint('[API] GET $fullUrl');
        final response = await http
            .get(
              Uri.parse(fullUrl),
              headers: _headers(token),
            )
            .timeout(const Duration(seconds: 5));

        debugPrint('[API] GET $fullUrl => Status ${response.statusCode}');
        _cachedActiveBaseUrl = base;
        return response;
      } catch (e) {
        debugPrint('[API ERR] GET $base$endpoint => $e');
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Could not reach server');
  }

  Future<http.Response> _smartDelete(String endpoint, [String? token]) async {
    final urlsToTry = _cachedActiveBaseUrl != null
        ? [_cachedActiveBaseUrl!, ...candidateUrls.where((u) => u != _cachedActiveBaseUrl)]
        : candidateUrls;

    Exception? lastError;
    for (final base in urlsToTry) {
      try {
        final fullUrl = _normalizeEndpoint(base, endpoint);
        debugPrint('[API] DELETE $fullUrl');
        final response = await http
            .delete(
              Uri.parse(fullUrl),
              headers: _headers(token),
            )
            .timeout(const Duration(seconds: 5));

        debugPrint('[API] DELETE $fullUrl => Status ${response.statusCode}');
        _cachedActiveBaseUrl = base;
        return response;
      } catch (e) {
        debugPrint('[API ERR] DELETE $base$endpoint => $e');
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('Could not reach server');
  }

  // =========================================================================
  // 1. AUTH CONTROLLER (APIs 1-11)
  // =========================================================================

  /// API 1: POST /api/Auth/register
  Future<Map<String, dynamic>> register({
    required String phone,
    required String fullName,
    required String password,
    String? username,
    String? email,
    String? otp,
    int dietType = 0,
    String? dietName,
  }) async {
    try {
      final response = await _smartPost('/Auth/register', {
        'phone': phone,
        'fullName': fullName,
        'username': username ?? phone,
        'email': email ?? '${username ?? phone}@tripdistribution.app',
        'password': password,
        'otpCode': otp ?? '',
        'dietType': dietType,
        'dietName': dietName ?? (dietType == 1 ? 'Non-Vegetarian' : (dietType == 2 ? 'Non-Veg + Alcohol' : 'Vegetarian')),
      });

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final resData = data['data'] ?? data;
        final token = resData['token'];
        if (token != null) setAuthToken(token);
        final user = UserModel(
          id: resData['userId'] ?? 'usr_${DateTime.now().millisecondsSinceEpoch}',
          username: resData['username'] ?? username ?? phone,
          phone: resData['phone'] ?? phone,
          fullName: resData['fullName'] ?? fullName,
          token: token,
          dietType: resData['dietType'] as int? ?? dietType,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
        );
        return {'success': true, 'user': user, 'token': token};
      }
      return {'success': false, 'message': data['message'] ?? 'Registration failed.'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// API 2: POST /api/Auth/login
  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
    String? email,
    String? username,
  }) async {
    try {
      final response = await _smartPost('/Auth/login', {
        'phone': phone,
        if (email != null) 'email': email,
        if (username != null) 'username': username,
        'password': password,
      });

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final resData = data['data'] ?? data;
        final token = resData['token'];
        if (token != null) setAuthToken(token);
        final user = UserModel(
          id: resData['userId'] ?? 'usr_${DateTime.now().millisecondsSinceEpoch}',
          username: resData['username'] ?? username ?? phone,
          phone: resData['phone'] ?? phone,
          fullName: resData['fullName'] ?? 'User',
          token: token,
          dietType: resData['dietType'] as int? ?? 0,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
        );
        return {'success': true, 'user': user, 'token': token};
      }
      return {'success': false, 'message': data['message'] ?? 'Invalid credentials.'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// API 3: POST /api/Auth/biometric-login
  Future<Map<String, dynamic>> biometricLogin({
    required String userId,
    required String authToken,
  }) async {
    try {
      final response = await _smartPost('/Auth/biometric-login', {
        'userId': userId,
        'authToken': authToken,
      });

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final resData = data['data'] ?? data;
        final newToken = resData['token'];
        if (newToken != null) setAuthToken(newToken);
        return {'success': true, 'token': newToken, 'data': resData};
      }
      return {'success': false, 'message': data['message'] ?? 'Biometric login failed.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 4: POST /api/Auth/send-otp
  Future<Map<String, dynamic>> sendOtp({
    String? phone,
    String? email,
    String? userId,
    String purpose = 'REGISTER',
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Auth/send-otp',
        {
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
          if (userId != null && userId.isNotEmpty) 'userId': userId,
          'purpose': purpose,
        },
        token,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final resData = data['data'] ?? data;
        return {
          'success': true,
          'message': data['message'] ?? 'OTP sent successfully',
          'otp': resData['otpCode'] ?? resData['otp'],
        };
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to send OTP.'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// API 5: POST /api/Auth/verify-otp
  Future<Map<String, dynamic>> verifyOtp({
    String? phone,
    String? email,
    String? userId,
    required String otp,
    String purpose = 'REGISTER',
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Auth/verify-otp',
        {
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
          if (userId != null && userId.isNotEmpty) 'userId': userId,
          'otpCode': otp,
          'purpose': purpose,
        },
        token,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'message': data['message'] ?? 'OTP verification failed.'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// API 6: POST /api/Auth/reset-password
  Future<Map<String, dynamic>> resetPassword({
    required String phone,
    required String otp,
    required String newPassword,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Auth/reset-password',
        {
          'phone': phone,
          'otpCode': otp,
          'newPassword': newPassword,
        },
        token,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'message': data['message'] ?? 'Password reset failed.'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// API 7: GET /api/Auth/profile
  Future<Map<String, dynamic>> getProfile({String? token}) async {
    try {
      final response = await _smartGet('/Auth/profile', token);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'profile': data['data'] ?? data};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to fetch profile.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 8: PUT /api/Auth/profile
  Future<Map<String, dynamic>> updateProfile({
    String? userId,
    String? fullName,
    String? avatarColor,
    bool? isBiometricEnabled,
    int? dietType,
    String? dietName,
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Auth/profile',
        {
          if (fullName != null) 'fullName': fullName,
          if (avatarColor != null) 'avatarColor': avatarColor,
          if (isBiometricEnabled != null) 'isBiometricEnabled': isBiometricEnabled,
          if (dietType != null) 'dietType': dietType,
          if (dietName != null) 'dietName': dietName,
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 9: PUT /api/Auth/diet
  Future<Map<String, dynamic>> updateDiet({
    required int dietType,
    String? dietName,
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Auth/diet',
        {
          'dietType': dietType,
          'dietName': dietName ?? (dietType == 1 ? 'Non-Vegetarian' : (dietType == 2 ? 'Non-Veg + Alcohol' : 'Vegetarian')),
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 10: POST /api/Auth/verify-token
  Future<Map<String, dynamic>> verifyToken({
    required String token,
    String? phone,
  }) async {
    try {
      final response = await _smartPost(
        '/Auth/verify-token',
        {'token': token, if (phone != null) 'phone': phone},
        token,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && (data['valid'] == true || data['success'] == true)) {
        final uData = data['data'] ?? data['user'] ?? {};
        final user = UserModel(
          id: uData['userId'] ?? uData['id'] ?? '',
          phone: uData['phone'] ?? uData['phoneNumber'] ?? phone ?? '',
          fullName: uData['fullName'] ?? 'User',
          dietType: uData['dietType'] as int? ?? 0,
          token: token,
          createdAt: DateTime.tryParse(uData['createdAt'] ?? '') ?? DateTime.now(),
          lastLoginAt: DateTime.tryParse(uData['lastLoginAt'] ?? '') ?? DateTime.now(),
        );
        return {'valid': true, 'user': user};
      }
      return {'valid': false, 'message': data['message'] ?? 'Token invalid.'};
    } catch (e) {
      return {'valid': false, 'message': 'Token check error: $e'};
    }
  }

  /// API 11: POST /api/Auth/logout
  Future<bool> logout([String? token]) async {
    try {
      final t = token ?? _cachedToken;
      if (t != null) {
        await _smartPost('/Auth/logout', {'token': t}, t);
      }
      _cachedToken = null;
      return true;
    } catch (_) {
      _cachedToken = null;
      return false;
    }
  }

  // --- Biometric helper for backwards compatibility ---
  Future<bool> toggleBiometric({required String userId, required bool enabled, String? token}) async {
    try {
      final res = await updateProfile(isBiometricEnabled: enabled, token: token);
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/Auth/change-password
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Auth/change-password',
        {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
        token,
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && (data['success'] == true || data['success'] == null),
        'message': data['message'] ?? (response.statusCode == 200 ? 'Password changed successfully.' : 'Failed to change password.'),
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // =========================================================================
  // 2. TRIPS CONTROLLER (APIs 12-17)
  // =========================================================================

  /// API 12: GET /api/Trips
  Future<List<Trip>> getTrips({String? userId, String? phone, String? token}) async {
    try {
      final response = await _smartGet('/Trips', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? data['trips'] ?? (data is List ? data : []);
        if (list is List) {
          final tripSummaries = list;
          final detailedTrips = await Future.wait(
            tripSummaries.map((s) async {
              final tripId = (s['tripId'] ?? s['id'] ?? '').toString();
              if (tripId.isNotEmpty) {
                final detail = await getTripById(tripId, token: token);
                if (detail['success'] == true && detail['trip'] != null) {
                  return Trip.fromJson(detail['trip']);
                }
              }
              return Trip.fromJson(s);
            }),
          );
          return detailedTrips;
        }
      }
      return [];
    } catch (e) {
      debugPrint('getTrips error: $e');
      return [];
    }
  }

  /// API 13: GET /api/Trips/{id}
  Future<Map<String, dynamic>> getTripById(String tripId, {String? token}) async {
    try {
      final response = await _smartGet('/Trips/$tripId', token);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'trip': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'Trip not found.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 14: POST /api/Trips
  Future<Map<String, dynamic>> createTrip({
    required Trip trip,
    String? currencyCode,
    String? token,
    String? userId,
  }) async {
    try {
      final response = await _smartPost('/Trips', {
        'name': trip.name,
        'description': trip.description ?? '',
        'currencyCode': currencyCode ?? 'INR',
      }, token);

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 || response.statusCode == 201, 'data': data['data'] ?? data, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 15: POST /api/Trips/sync
  Future<bool> syncTrips({
    required String userId,
    required List<Trip> trips,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Trips/sync',
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

  /// API 16: PUT /api/Trips/{id}
  Future<Map<String, dynamic>> updateTrip({
    required String tripId,
    required String name,
    String? description,
    String? currencyCode,
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Trips/$tripId',
        {
          'name': name,
          if (description != null) 'description': description,
          if (currencyCode != null) 'currencyCode': currencyCode,
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 17: DELETE /api/Trips/{id}
  Future<bool> deleteTrip(String tripId, {String? token, String? userId}) async {
    try {
      final response = await _smartDelete('/Trips/$tripId', token);
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // =========================================================================
  // 3. EXPENSES CONTROLLER (APIs 18-23)
  // =========================================================================

  /// API 18: GET /api/Expenses/trip/{tripId}
  Future<List<Map<String, dynamic>>> getExpensesByTrip(String tripId, {String? token}) async {
    try {
      final response = await _smartGet('/Expenses/trip/$tripId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? [];
        if (list is List) return List<Map<String, dynamic>>.from(list);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// API 19: GET /api/Expenses/{id}
  Future<Map<String, dynamic>> getExpenseById(String expenseId, {String? token}) async {
    try {
      final response = await _smartGet('/Expenses/$expenseId', token);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'expense': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'Expense not found.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 20: POST /api/Expenses
  Future<Map<String, dynamic>> createExpense(Map<String, dynamic> expenseDto, {String? token}) async {
    try {
      final response = await _smartPost('/Expenses', expenseDto, token);
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'data': data['data'] ?? data,
        'message': data['message'],
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 21: PUT /api/Expenses/{id}
  Future<Map<String, dynamic>> updateExpense(String expenseId, Map<String, dynamic> expenseDto, {String? token}) async {
    try {
      final response = await _smartPut('/Expenses/$expenseId', expenseDto, token);
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'data': data['data'],
        'message': data['message'],
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 22: DELETE /api/Expenses/{id}
  Future<bool> deleteExpense(String expenseId, {String? token}) async {
    try {
      final response = await _smartDelete('/Expenses/$expenseId', token);
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// API 23: POST /api/Expenses/calculate-dietary-split/{tripId}
  Future<Map<String, dynamic>> calculateDietarySplit({
    required String tripId,
    required double totalAmount,
    required int categoryIndex,
    List<String>? personIds,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Expenses/calculate-dietary-split/$tripId',
        {
          'totalAmount': totalAmount,
          'categoryIndex': categoryIndex,
          if (personIds != null) 'personIds': personIds,
        },
        token,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'splits': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to calculate split.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // =========================================================================
  // 4. GROUPS CONTROLLER (APIs 24-27)
  // =========================================================================

  /// API 24: GET /api/Groups/trip/{tripId}
  Future<List<Map<String, dynamic>>> getGroupsByTrip(String tripId, {String? token}) async {
    try {
      final response = await _smartGet('/Groups/trip/$tripId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? [];
        if (list is List) return List<Map<String, dynamic>>.from(list);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 25: POST /api/Groups
  Future<Map<String, dynamic>> createGroup({
    required String tripId,
    required String name,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Groups',
        {'tripId': tripId, 'name': name},
        token,
      );
      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 || response.statusCode == 201, 'data': data['data'] ?? data, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 26: PUT /api/Groups/{id}
  Future<Map<String, dynamic>> updateGroup({
    required String groupId,
    required String name,
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Groups/$groupId',
        {'name': name},
        token,
      );
      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 27: DELETE /api/Groups/{id}
  Future<bool> deleteGroup(String groupId, {String? token}) async {
    try {
      final response = await _smartDelete('/Groups/$groupId', token);
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // =========================================================================
  // 5. PERSONS CONTROLLER (APIs 28-33)
  // =========================================================================

  /// API 28: GET /api/Persons/trip/{tripId}
  Future<List<Map<String, dynamic>>> getPersonsByTrip(String tripId, {String? token}) async {
    try {
      final response = await _smartGet('/Persons/trip/$tripId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? [];
        if (list is List) return List<Map<String, dynamic>>.from(list);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 29: GET /api/Persons/{id}
  Future<Map<String, dynamic>> getPersonById(String personId, {String? token}) async {
    try {
      final response = await _smartGet('/Persons/$personId', token);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'person': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'Person not found.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 30: POST /api/Persons
  Future<Map<String, dynamic>> createPerson({
    required String tripId,
    required String groupId,
    required String name,
    String? phone,
    String? userId,
    int dietType = 0,
    String? dietName,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Persons',
        {
          'tripId': tripId,
          'groupId': groupId,
          'name': name,
          if (phone != null) 'phoneNumber': phone,
          if (phone != null) 'phone': phone,
          if (userId != null) 'userId': userId,
          'dietType': dietType,
          'dietName': dietName ?? (dietType == 1 ? 'NonVeg' : (dietType == 2 ? 'Alcohol' : 'Veg')),
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 || response.statusCode == 201, 'data': data['data'] ?? data, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 31: PUT /api/Persons/{id}
  Future<Map<String, dynamic>> updatePerson({
    required String personId,
    required String name,
    String? phoneNumber,
    int? dietType,
    String? dietName,
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Persons/$personId',
        {
          'name': name,
          if (phoneNumber != null) 'phoneNumber': phoneNumber,
          if (dietType != null) 'dietType': dietType,
          if (dietName != null) 'dietName': dietName,
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 32: DELETE /api/Persons/{id}
  Future<bool> deletePerson(String personId, {String? token}) async {
    try {
      final response = await _smartDelete('/Persons/$personId', token);
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// API 33: POST /api/Persons/recalculate/{tripId}
  Future<Map<String, dynamic>> recalculateTrip(String tripId, {String? token}) async {
    try {
      final response = await _smartPost('/Persons/recalculate/$tripId', null, token);
      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // =========================================================================
  // 6. SETTLEMENTS CONTROLLER (APIs 34-38)
  // =========================================================================

  /// API 34: GET /api/Settlements/trip/{tripId}
  Future<List<SettlementProposal>> getSettlementsByTrip(String tripId, {String? token}) async {
    try {
      final response = await _smartGet('/Settlements/trip/$tripId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? [];
        if (list is List) {
          return list.map((s) => SettlementProposal.fromJson(s)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 35: GET /api/Settlements/{id}
  Future<Map<String, dynamic>> getSettlementById(String settlementId, {String? token}) async {
    try {
      final response = await _smartGet('/Settlements/$settlementId', token);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'settlement': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'Settlement not found.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 36: POST /api/Settlements
  Future<Map<String, dynamic>> proposeSettlement({
    required String tripId,
    required String fromPersonId,
    required String toPersonId,
    required double amount,
    String? notes,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Settlements',
        {
          'tripId': tripId,
          'fromPersonId': fromPersonId,
          'toPersonId': toPersonId,
          'amount': amount,
          if (notes != null) 'notes': notes,
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'data': data['data'] ?? data,
        'message': data['message'],
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Legacy helper for screen compatibility
  Future<bool> recordSettlementRequest({
    required String tripId,
    required String fromPersonId,
    required String toPersonId,
    required double amount,
    String? createdByUserId,
    String? token,
  }) async {
    final res = await proposeSettlement(
      tripId: tripId,
      fromPersonId: fromPersonId,
      toPersonId: toPersonId,
      amount: amount,
      notes: createdByUserId != null ? 'Created by $createdByUserId' : null,
      token: token,
    );
    return res['success'] == true;
  }

  /// Legacy helper for screen compatibility
  Future<List<SettlementProposal>> getPendingSettlements({
    required String userId,
    String? phone,
    String? token,
  }) async {
    return []; // Handled by getSettlementsByTrip
  }

  /// API 37: PUT /api/Settlements/{id}/status
  Future<Map<String, dynamic>> updateSettlementStatus({
    required String settlementId,
    required String status, // PENDING, ACCEPTED, REJECTED, COMPLETED
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Settlements/$settlementId/status',
        {'status': status},
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> acceptSettlementRequest({required String settlementId, required String userId, String? token}) async {
    final res = await updateSettlementStatus(settlementId: settlementId, status: 'ACCEPTED', token: token);
    return res['success'] == true;
  }

  Future<bool> declineSettlementRequest({required String settlementId, String? userId, String? token}) async {
    final res = await updateSettlementStatus(settlementId: settlementId, status: 'REJECTED', token: token);
    return res['success'] == true;
  }

  /// API 37: PUT /api/Settlements/{id}
  Future<bool> updateSettlementAmount({
    required String settlementId,
    required double amount,
    String? userId,
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Settlements/$settlementId',
        {'amount': amount},
        token,
      );
      final data = jsonDecode(response.body);
      return (response.statusCode == 200 || response.statusCode == 204) && (data['success'] == true || data['success'] == null);
    } catch (_) {
      return false;
    }
  }

  /// API 38: DELETE /api/Settlements/{id}
  Future<bool> deleteSettlement(String settlementId, {String? token}) async {
    try {
      final response = await _smartDelete('/Settlements/$settlementId', token);
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // =========================================================================
  // 7. FRIENDS CONTROLLER (APIs 39-45)
  // =========================================================================

  /// API 39: GET /api/Friends
  Future<List<FriendModel>> getFriends({String? userId, String? token}) async {
    try {
      final endpoint = userId != null ? '/Friends?userId=$userId' : '/Friends';
      final response = await _smartGet(endpoint, token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? data['friends'] ?? (data is List ? data : []);
        if (list is List) {
          return list.map((f) => FriendModel.fromJson(f)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 40: POST /api/Friends/check-contacts
  Future<List<Map<String, dynamic>>> checkContacts(List<String> phoneNumbers, {String? token}) async {
    try {
      final response = await _smartPost(
        '/Friends/check-contacts',
        {'contacts': phoneNumbers},
        token,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? data['registeredUsers'] ?? [];
        if (list is List) return List<Map<String, dynamic>>.from(list);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 41: POST /api/Friends
  Future<Map<String, dynamic>> addFriend({
    String? friendPhone,
    String? friendName,
    int? dietType,
    String? friendUserId,
    String? userId,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Friends',
        {
          if (friendPhone != null) 'friendPhone': friendPhone,
          if (friendName != null) 'friendName': friendName,
          if (dietType != null) 'dietType': dietType,
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 || response.statusCode == 201, 'data': data['data'] ?? data, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 42: POST /api/Friends/search
  Future<List<Map<String, dynamic>>> searchUsers(String phone, {String? token}) async {
    try {
      final response = await _smartPost(
        '/Friends/search',
        {'phone': phone},
        token,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? data['users'] ?? [];
        if (list is List) return List<Map<String, dynamic>>.from(list);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 43: GET /api/Friends/requests
  Future<List<Map<String, dynamic>>> getFriendRequests({String? userId, String? type, String? token}) async {
    try {
      final endpoint = userId != null ? '/Friends/requests?userId=$userId' : '/Friends/requests';
      final response = await _smartGet(endpoint, token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? data['requests'] ?? [];
        if (list is List) return List<Map<String, dynamic>>.from(list);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 44: PUT /api/Friends/{id}/status
  Future<Map<String, dynamic>> updateFriendStatus({
    required String connectionId,
    required String status, // ACCEPTED, REJECTED
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Friends/$connectionId/status',
        {'status': status},
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> acceptFriendRequest({
    required String connectionId,
    required String userId,
    String? token,
  }) => updateFriendStatus(connectionId: connectionId, status: 'ACCEPTED', token: token);

  Future<Map<String, dynamic>> declineFriendRequest({
    required String connectionId,
    String? token,
  }) => updateFriendStatus(connectionId: connectionId, status: 'REJECTED', token: token);

  /// API 45: DELETE /api/Friends/{id}
  Future<bool> deleteFriend(String connectionId, {String? userId, String? token}) async {
    try {
      final response = await _smartDelete('/Friends/$connectionId', token);
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // =========================================================================
  // 8. COLLABORATORS CONTROLLER (APIs 46-49)
  // =========================================================================

  /// API 46: GET /api/Collaborators/trip/{tripId}
  Future<List<CollaboratorModel>> getCollaborators(String tripId, {String? token}) async {
    try {
      final response = await _smartGet('/Collaborators/trip/$tripId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? [];
        if (list is List) {
          return list.map((c) => CollaboratorModel.fromJson(c)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 47: POST /api/Collaborators
  Future<Map<String, dynamic>> inviteCollaborator({
    required String tripId,
    String? userId,
    String? phoneNumber,
    String role = 'MEMBER', // OWNER, MEMBER, VIEWER
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Collaborators',
        {
          'tripId': tripId,
          if (userId != null) 'userId': userId,
          if (phoneNumber != null) 'phoneNumber': phoneNumber,
          'role': role,
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 || response.statusCode == 201, 'data': data['data'] ?? data, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 48: PUT /api/Collaborators/{id}/role
  Future<Map<String, dynamic>> updateCollaboratorRole({
    required String collabId,
    required String role, // OWNER, MEMBER, VIEWER
    String? token,
  }) async {
    try {
      final response = await _smartPut(
        '/Collaborators/$collabId/role',
        {'role': role},
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// API 49: DELETE /api/Collaborators/{id}
  Future<bool> removeCollaborator(String collabId, {String? token}) async {
    try {
      final response = await _smartDelete('/Collaborators/$collabId', token);
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // =========================================================================
  // 9. NOTIFICATIONS CONTROLLER (APIs 50-53)
  // =========================================================================

  /// API 50: GET /api/Notifications
  Future<List<NotificationModel>> getNotifications({String? userId, String? token}) async {
    try {
      final response = await _smartGet('/Notifications', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? data['notifications'] ?? (data is List ? data : []);
        if (list is List) {
          return list.map((n) => NotificationModel.fromJson(n)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// API 51: GET /api/Notifications/unread-count
  Future<int> getUnreadNotificationCount({String? userId, String? token}) async {
    try {
      final response = await _smartGet('/Notifications/unread-count', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']?['unreadCount'] ?? data['count'] ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// API 52: POST /api/Notifications/mark-read
  Future<bool> markNotificationsRead({String? notificationId, String? userId, List<String>? notificationIds, String? token}) async {
    try {
      final ids = notificationIds ?? (notificationId != null ? [notificationId] : []);
      final response = await _smartPost(
        '/Notifications/mark-read',
        {'notificationIds': ids},
        token,
      );
      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// API 53: POST /api/Notifications/send
  Future<Map<String, dynamic>> sendNotification({
    required String toUserId,
    required String message,
    String? tripId,
    String? token,
  }) async {
    try {
      final response = await _smartPost(
        '/Notifications/send',
        {
          'toUserId': toUserId,
          'message': message,
          if (tripId != null) 'tripId': tripId,
        },
        token,
      );

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200 && data['success'] == true, 'data': data['data'], 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // =========================================================================
  // 10. ACTIVITY LOGS CONTROLLER (API 54)
  // =========================================================================

  /// API 54: GET /api/ActivityLogs/trip/{tripId}
  Future<List<ActivityLogModel>> getActivityLogs(String tripId, {String? token}) async {
    try {
      final response = await _smartGet('/ActivityLogs/trip/$tripId', token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? [];
        if (list is List) {
          return list.map((l) => ActivityLogModel.fromJson(l)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // --- Health Check Helper ---
  Future<bool> checkLiveConnection() async {
    try {
      final res = await _smartGet('/Trips');
      return res.statusCode == 200 || res.statusCode == 401;
    } catch (_) {
      return false;
    }
  }

  Future<bool> testConnection(String ipOrHostAndPort) async {
    try {
      String fullUrl = ipOrHostAndPort.trim();
      if (!fullUrl.startsWith('http://') && !fullUrl.startsWith('https://')) {
        fullUrl = 'http://$fullUrl';
      }
      final cleanHost = fullUrl.replaceAll('http://', '').replaceAll('https://', '');
      if (!cleanHost.contains(':')) {
        fullUrl += ':5262';
      }
      if (!fullUrl.endsWith('/api')) {
        fullUrl += '/api';
      }

      final res = await http.get(Uri.parse('$fullUrl/Trips')).timeout(const Duration(milliseconds: 2500));
      if (res.statusCode == 200 || res.statusCode == 401) {
        _cachedActiveBaseUrl = fullUrl;
        return true;
      }
    } catch (_) {}
    return false;
  }
}
