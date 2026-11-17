// lib/providers/auth_provider.dart
import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final StorageService _storageService;
  final ApiService _apiService;
  final BiometricService _biometricService;

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isCheckingToken = true;
  bool _isBiometricLocked = false;
  String? _errorMessage;
  String? _successMessage;

  // Environment state (debug vs production)
  String _environment = 'debug';

  // OTP state helpers for UI
  String? _lastSentOtp;
  bool _isOtpSent = false;
  final int _otpCountdown = 0;

  AuthProvider({
    StorageService? storageService,
    ApiService? apiService,
    BiometricService? biometricService,
  })  : _storageService = storageService ?? StorageService(),
        _apiService = apiService ?? ApiService(),
        _biometricService = biometricService ?? BiometricService() {
    _initEnvironmentAndLogin();
  }

  Future<void> _initEnvironmentAndLogin() async {
    try {
      _environment = await _storageService.getAppEnvironment();
    } catch (_) {}
    checkPersistentLogin();
  }

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isBiometricLocked => _isBiometricLocked;
  bool get isLoading => _isLoading;
  bool get isCheckingToken => _isCheckingToken;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  String? get lastSentOtp => _lastSentOtp;
  bool get isOtpSent => _isOtpSent;
  int get otpCountdown => _otpCountdown;
  String get environment => _environment;
  bool get isDebugMode => _environment == 'debug';
  StorageService get storageService => _storageService;
  ApiService get apiService => _apiService;
  BiometricService get biometricService => _biometricService;

  Future<void> setEnvironment(String env) async {
    _environment = env;
    await _storageService.setAppEnvironment(env);
    notifyListeners();
  }

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Checks if a valid token is cached in memory/storage and verifies with DB.
  Future<bool> checkPersistentLogin() async {
    _isCheckingToken = true;
    notifyListeners();

    try {
      final token = await _storageService.getAuthToken();
      final phone = await _storageService.getSavedPhone();

      if (token != null && token.isNotEmpty) {
        _apiService.setAuthToken(token);
        final isBioEnabled = await _storageService.isBiometricEnabled();

        // Verify token with backend database
        final verifyResult = await _apiService.verifyToken(token: token, phone: phone);
        if (verifyResult['valid'] == true && verifyResult['user'] != null) {
          final serverUser = verifyResult['user'] as UserModel;

          // Fetch complete trips directly from SQL Server
          final remoteTrips = await _apiService.getTrips(userId: serverUser.id, phone: serverUser.phone, token: token);
          serverUser.trips = remoteTrips;

          _currentUser = serverUser;
          _isBiometricLocked = isBioEnabled;
          _isCheckingToken = false;
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Persistent login check error: $e');
    }

    _isCheckingToken = false;
    _isBiometricLocked = false;
    notifyListeners();
    return false;
  }

  /// Unlocks app when user completes fingerprint/PIN auth
  Future<bool> unlockWithBiometrics() async {
    final ok = await _biometricService.authenticate(
      reason: 'Scan fingerprint or phone PIN to unlock EquiTrip',
    );
    if (ok) {
      _isBiometricLocked = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Sends OTP to email or phone number for Registration or Forgot Password
  Future<bool> sendOtp(
    String? identifier, {
    String? email,
    String? phone,
    String purpose = 'REGISTER',
  }) async {
    final effectiveEmail = email ?? (identifier != null && identifier.contains('@') ? identifier.trim() : null);
    final effectivePhone = phone ?? (identifier != null && !identifier.contains('@') ? identifier.trim() : null);

    if ((effectiveEmail == null || effectiveEmail.isEmpty) && (effectivePhone == null || effectivePhone.isEmpty)) {
      _errorMessage = 'Please enter a valid email address';
      notifyListeners();
      return false;
    }

    if (effectiveEmail != null && effectiveEmail.isNotEmpty && (!effectiveEmail.contains('@') || !effectiveEmail.contains('.'))) {
      _errorMessage = 'Please enter a valid email address';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    final res = await _apiService.sendOtp(
      email: effectiveEmail,
      phone: effectivePhone,
      purpose: purpose,
      environment: _environment,
    );
    _isLoading = false;

    if (res['success'] == true) {
      _isOtpSent = true;
      _lastSentOtp = res['otp']; // Stored for display banner / auto-fill in testing (in debug mode)
      _successMessage = res['message'] ?? (isDebugMode && _lastSentOtp != null
          ? 'OTP: $_lastSentOtp'
          : 'Verification code sent to ${effectiveEmail ?? effectivePhone}. Please check your inbox.');
      notifyListeners();
      return true;
    } else {
      _errorMessage = res['message'] ?? 'Failed to send OTP';
      notifyListeners();
      return false;
    }
  }

  /// Verifies entered OTP
  Future<bool> verifyOtp(String phone, String otp, {String purpose = 'REGISTER'}) async {
    if (otp.trim().isEmpty) {
      _errorMessage = 'Please enter the 6-digit OTP';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final res = await _apiService.verifyOtp(phone: phone, otp: otp, purpose: purpose);
    _isLoading = false;

    if (res['success'] == true) {
      _successMessage = res['message'] ?? 'OTP verified successfully!';
      notifyListeners();
      return true;
    } else {
      _errorMessage = res['message'] ?? 'Invalid OTP code';
      notifyListeners();
      return false;
    }
  }

  /// Registers user after OTP verification
  Future<bool> register({
    required String phone,
    required String fullName,
    required String password,
    required String confirmPassword,
    String? email,
    String? username,
    String? otp,
    int dietType = 0,
  }) async {
    if (phone.trim().isEmpty && (email == null || email.trim().isEmpty)) {
      _errorMessage = 'Phone number or email is required';
      notifyListeners();
      return false;
    }
    if (fullName.trim().isEmpty) {
      _errorMessage = 'Full name is required';
      notifyListeners();
      return false;
    }
    if (password.length < 4) {
      _errorMessage = 'Password must be at least 4 characters';
      notifyListeners();
      return false;
    }
    if (password != confirmPassword) {
      _errorMessage = 'Passwords do not match';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final res = await _apiService.register(
      phone: phone.trim(),
      fullName: fullName.trim(),
      email: email?.trim(),
      username: username?.trim(),
      password: password,
      otp: otp,
      dietType: dietType,
    );

    _isLoading = false;

    if (res['success'] == true && res['user'] != null) {
      final user = res['user'] as UserModel;
      final token = res['token'] as String;

      _currentUser = user;
      _apiService.setAuthToken(token);
      await _storageService.saveAuthToken(token, phone: user.phone, userId: user.id);

      _successMessage = 'Account created successfully!';
      notifyListeners();
      return true;
    } else {
      _errorMessage = res['message'] ?? 'Registration failed';
      notifyListeners();
      return false;
    }
  }

  /// Logs in existing user with Phone or Email & Password
  Future<bool> login(String phone, String password, {String? email, String? username}) async {
    final cleanIdentifier = phone.trim();
    if (cleanIdentifier.isEmpty && (email == null || email.trim().isEmpty)) {
      _errorMessage = 'Please enter your email or phone number';
      notifyListeners();
      return false;
    }
    if (password.isEmpty) {
      _errorMessage = 'Please enter your password';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final isEmail = email != null || cleanIdentifier.contains('@');
    final res = await _apiService.login(
      phone: isEmail ? '' : cleanIdentifier,
      email: isEmail ? (email ?? cleanIdentifier) : null,
      username: username,
      password: password,
    );
    _isLoading = false;

    if (res['success'] == true && res['user'] != null) {
      final user = res['user'] as UserModel;
      final token = res['token'] as String;

      // Load user trips from SQL Server
      final trips = await _apiService.getTrips(userId: user.id, token: token);
      user.trips = trips;

      _currentUser = user;
      _apiService.setAuthToken(token);
      await _storageService.saveAuthToken(token, phone: user.phone, userId: user.id);
      await _storageService.setBiometricEnabled(user.isBiometricEnabled);

      notifyListeners();
      return true;
    } else {
      _errorMessage = res['message'] ?? 'Login failed. Please check credentials.';
      notifyListeners();
      return false;
    }
  }

  /// Triggers biometric login using cached token and device fingerprint / PIN
  Future<bool> loginWithBiometrics() async {
    final isAvailable = await _biometricService.isBiometricAvailable();
    if (!isAvailable) {
      _errorMessage = 'Biometric authentication is not available on this device';
      notifyListeners();
      return false;
    }

    final token = await _storageService.getAuthToken();
    final phone = await _storageService.getSavedPhone();

    if (token == null || token.isEmpty) {
      _errorMessage = 'No saved session found. Please log in with password first.';
      notifyListeners();
      return false;
    }

    final authenticated = await _biometricService.authenticate(
      reason: 'Scan fingerprint or enter phone PIN to sign in',
    );

    if (!authenticated) {
      _errorMessage = 'Biometric authentication canceled or failed';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    // Call API 3: POST /api/Auth/biometric-login if userId is known
    final savedUserId = await _storageService.getSavedUserId() ?? _currentUser?.id;
    String activeToken = token;
    if (savedUserId != null && savedUserId.isNotEmpty) {
      final bioRes = await _apiService.biometricLogin(userId: savedUserId, authToken: token);
      if (bioRes['success'] == true && bioRes['token'] != null) {
        activeToken = bioRes['token'] as String;
        await _storageService.saveAuthToken(activeToken, phone: phone, userId: savedUserId);
        _apiService.setAuthToken(activeToken);
      }
    }

    final res = await _apiService.verifyToken(token: activeToken, phone: phone);
    _isLoading = false;

    if (res['valid'] == true && res['user'] != null) {
      final user = res['user'] as UserModel;
      final trips = await _apiService.getTrips(userId: user.id, token: activeToken);
      user.trips = trips;

      _currentUser = user;
      _isBiometricLocked = false;
      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Session expired. Please log in with your password.';
      notifyListeners();
      return false;
    }
  }

  /// Updates current user's trips in memory (all persistence handled directly via SQL Server APIs)
  void saveCurrentUserData(List<Trip> trips) {
    if (_currentUser == null) return;
    _currentUser!.trips = List.from(trips);
  }

  /// Updates user profile name and dietary preference immediately across app and storage
  Future<bool> updateProfile({
    required String fullName,
    required int dietType,
  }) async {
    if (_currentUser == null) return false;

    final dietNames = ['Vegetarian', 'Non-Vegetarian', 'Non-Veg + Alcohol'];
    final dietName = dietNames[dietType.clamp(0, 2)];

    // 1. Immediately update in-memory user
    _currentUser = _currentUser!.copyWith(
      fullName: fullName.trim(),
      dietType: dietType,
      dietName: dietName,
    );
    notifyListeners();

    // 2. Sync to backend SQL Server database
    final token = await _storageService.getAuthToken();
    final res = await _apiService.updateProfile(
      userId: _currentUser!.id,
      fullName: fullName.trim(),
      dietType: dietType,
      token: token,
    );

    if (res['success'] == true && res['user'] != null) {
      final user = res['user'] as UserModel;
      _currentUser = _currentUser!.copyWith(
        fullName: user.fullName,
        dietType: user.dietType,
        dietName: user.dietName,
      );
      notifyListeners();
      return true;
    }

    return res['success'] == true;
  }

  /// Reset Password via verified OTP
  Future<bool> resetPassword({
    String? email,
    String? phone,
    required String otp,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final cleanEmail = email?.trim();
    final cleanPhone = phone?.trim();

    if ((cleanEmail == null || cleanEmail.isEmpty) && (cleanPhone == null || cleanPhone.isEmpty)) {
      _errorMessage = 'Please enter your registered email address';
      notifyListeners();
      return false;
    }
    if (newPassword.length < 4) {
      _errorMessage = 'Password must be at least 4 characters long';
      notifyListeners();
      return false;
    }
    if (newPassword != confirmPassword) {
      _errorMessage = 'Passwords do not match';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final res = await _apiService.resetPassword(
      email: cleanEmail,
      phone: cleanPhone,
      otp: otp.trim(),
      newPassword: newPassword,
    );

    _isLoading = false;

    if (res['success'] == true) {
      _successMessage = 'Password reset successfully! Please login with your new password.';
      notifyListeners();
      return true;
    } else {
      _errorMessage = res['message'] ?? 'Password reset failed';
      notifyListeners();
      return false;
    }
  }

  /// Toggles biometric setting
  Future<void> toggleBiometric(bool enabled) async {
    if (_currentUser == null) return;

    await _storageService.setBiometricEnabled(enabled);
    _currentUser = _currentUser!.copyWith(isBiometricEnabled: enabled);
    await _apiService.toggleBiometric(
      userId: _currentUser!.id,
      enabled: enabled,
      token: _currentUser!.token,
    );
    notifyListeners();
  }

  /// Logs out user, invalidating DB token and local cache
  Future<void> logout() async {
    final token = await _storageService.getAuthToken();
    if (token != null) {
      await _apiService.logout(token);
    }
    await _storageService.clearAuthToken();
    _currentUser = null;
    _errorMessage = null;
    _successMessage = null;
    _lastSentOtp = null;
    _isOtpSent = false;
    notifyListeners();
  }
}

