// lib/services/storage_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

/// Secure session credentials storage (JWT auth token, phone, biometric preferences).
/// All trip, group, expense, and settlement data are stored and fetched directly from SQL Server via APIs.
class StorageService {
  SharedPreferences? _prefs;

  StorageService({String? baseDirPath, SharedPreferences? prefs}) : _prefs = prefs;

  static const String _tokenKey = 'saved_auth_token';
  static const String _phoneKey = 'saved_user_phone';
  static const String _userIdKey = 'saved_user_id';
  static const String _biometricPrefKey = 'saved_biometric_enabled';
  static const String _userNameKey = 'saved_user_name';

  /// Ensures that the SharedPreferences instance is initialized
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // --- Session Token Management ---

  Future<void> saveAuthToken(String token, {String? phone, String? userId, String? fullName}) async {
    await init();
    await _prefs?.setString(_tokenKey, token);
    if (phone != null) await _prefs?.setString(_phoneKey, phone);
    if (userId != null) await _prefs?.setString(_userIdKey, userId);
    if (fullName != null) await _prefs?.setString(_userNameKey, fullName);
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

  Future<String?> getSavedUserName() async {
    await init();
    return _prefs?.getString(_userNameKey);
  }

  Future<void> clearAuthToken() async {
    await init();
    await _prefs?.remove(_tokenKey);
    await _prefs?.remove(_phoneKey);
    await _prefs?.remove(_userIdKey);
    await _prefs?.remove(_userNameKey);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await init();
    await _prefs?.setBool(_biometricPrefKey, enabled);
  }

  Future<bool> isBiometricEnabled() async {
    await init();
    return _prefs?.getBool(_biometricPrefKey) ?? false;
  }

  // --- Backward Compatibility Placeholders (No-op local storage for trip data) ---

  Future<void> saveCachedUser(UserModel user) async {
    // Only persist session credentials, never write data records locally
    if (user.token != null && user.token!.isNotEmpty) {
      await saveAuthToken(
        user.token!,
        phone: user.phone,
        userId: user.id,
        fullName: user.fullName,
      );
    }
  }

  Future<UserModel?> loadCachedUser([String? identifier]) async {
    return null; // Forces direct API fetch from SQL Server database
  }

  Future<bool> userExists(String username) async {
    await init();
    return false;
  }

  Future<List<UserModel>> getAllUsers() async {
    return [];
  }

  Future<void> saveUser(UserModel user) => saveCachedUser(user);
  Future<UserModel?> loadUser(String username) => loadCachedUser(username);
}
