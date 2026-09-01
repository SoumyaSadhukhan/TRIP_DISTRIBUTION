// lib/services/storage_service.dart
import 'dart:convert';
import 'dart:io' show Directory, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class StorageService {
  final String baseDirPath;
  SharedPreferences? _prefs;

  StorageService({this.baseDirPath = 'data/users', SharedPreferences? prefs})
      : _prefs = prefs;

  static const String _tokenKey = 'saved_auth_token';
  static const String _phoneKey = 'saved_user_phone';
  static const String _userIdKey = 'saved_user_id';
  static const String _biometricPrefKey = 'saved_biometric_enabled';
  static const String _lastActiveUserKey = 'last_active_user_data';

  /// Ensures that the storage and SharedPreferences instance are initialized
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();

    if (!kIsWeb) {
      try {
        final dir = Directory(baseDirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (_) {}
    }
  }

  // --- Session Token Management ---

  Future<void> saveAuthToken(String token, {String? phone, String? userId}) async {
    await init();
    await _prefs?.setString(_tokenKey, token);
    if (phone != null) await _prefs?.setString(_phoneKey, phone);
    if (userId != null) await _prefs?.setString(_userIdKey, userId);
  }

  Future<String?> getAuthToken() async {
    await init();
    return _prefs?.getString(_tokenKey);
  }

  Future<String?> getSavedPhone() async {
    await init();
    return _prefs?.getString(_phoneKey);
  }

  Future<String?> getSavedUserId() async {
    await init();
    return _prefs?.getString(_userIdKey);
  }

  Future<void> clearAuthToken() async {
    await init();
    await _prefs?.remove(_tokenKey);
    await _prefs?.remove(_phoneKey);
    await _prefs?.remove(_userIdKey);
    await _prefs?.remove(_lastActiveUserKey);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await init();
    await _prefs?.setBool(_biometricPrefKey, enabled);
  }

  Future<bool> isBiometricEnabled() async {
    await init();
    return _prefs?.getBool(_biometricPrefKey) ?? false;
  }

  // --- Cached User Profile & Trips ---

  String _sanitizeKey(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_\-]'), '_');
  }

  String _getPrefKey(String clean) => 'user_data_$clean';

  Future<void> saveCachedUser(UserModel user) async {
    await init();
    final clean = _sanitizeKey(user.phone.isNotEmpty ? user.phone : user.username);
    final jsonString = jsonEncode(user.toJson());

    await _prefs?.setString(_getPrefKey(clean), jsonString);
    await _prefs?.setString(_lastActiveUserKey, jsonString);

    if (!kIsWeb) {
      try {
        final file = File('$baseDirPath/$clean.json');
        await file.writeAsString(jsonString, flush: true);
      } catch (_) {}
    }
  }

  Future<UserModel?> loadCachedUser([String? identifier]) async {
    await init();

    if (identifier != null && identifier.isNotEmpty) {
      final clean = _sanitizeKey(identifier);
      final jsonStr = _prefs?.getString(_getPrefKey(clean));
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          return UserModel.fromJson(jsonDecode(jsonStr));
        } catch (_) {}
      }
    }

    final lastJson = _prefs?.getString(_lastActiveUserKey);
    if (lastJson != null && lastJson.isNotEmpty) {
      try {
        return UserModel.fromJson(jsonDecode(lastJson));
      } catch (_) {}
    }

    return null;
  }

  // Legacy compatibility helpers
  Future<bool> userExists(String username) async {
    await init();
    final clean = _sanitizeKey(username);
    return _prefs?.containsKey(_getPrefKey(clean)) ?? false;
  }

  Future<List<UserModel>> getAllUsers() async {
    await init();
    final users = <UserModel>[];
    if (!kIsWeb) {
      try {
        final dir = Directory(baseDirPath);
        if (await dir.exists()) {
          final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
          for (final file in files) {
            try {
              final content = await file.readAsString();
              users.add(UserModel.fromJson(jsonDecode(content)));
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return users;
  }

  Future<void> saveUser(UserModel user) => saveCachedUser(user);
  Future<UserModel?> loadUser(String username) => loadCachedUser(username);
}

