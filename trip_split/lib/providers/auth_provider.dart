// lib/providers/auth_provider.dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/trip.dart';
import '../models/user.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final StorageService _storageService;
  final Uuid _uuid = const Uuid();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider({StorageService? storageService})
      : _storageService = storageService ?? StorageService();

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  StorageService get storageService => _storageService;

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Registers a new user account with username and password
  Future<bool> register(String username, String password) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty) {
      _errorMessage = 'Username cannot be empty';
      notifyListeners();
      return false;
    }

    if (password.trim().isEmpty) {
      _errorMessage = 'Password cannot be empty';
      notifyListeners();
      return false;
    }

    if (password.length < 4) {
      _errorMessage = 'Password must be at least 4 characters long';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final exists = await _storageService.userExists(cleanUsername);
      if (exists) {
        _errorMessage = 'Username "$cleanUsername" is already taken. Please login.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final now = DateTime.now();
      final newUser = UserModel(
        id: _uuid.v4(),
        username: cleanUsername,
        password: password,
        createdAt: now,
        lastLoginAt: now,
        trips: [],
      );

      await _storageService.saveUser(newUser);
      _currentUser = newUser;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to register: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logs in an existing user with username and password
  Future<bool> login(String username, String password) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty) {
      _errorMessage = 'Please enter your username';
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

    try {
      final user = await _storageService.loadUser(cleanUsername);
      if (user == null) {
        _errorMessage = 'User "$cleanUsername" not found. Please create an account.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (user.password != password) {
        _errorMessage = 'Incorrect password. Please try again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Update last login timestamp
      user.lastLoginAt = DateTime.now();
      await _storageService.saveUser(user);

      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Saves the current user's updated trips back to their JSON file
  Future<void> saveCurrentUserData(List<Trip> trips) async {
    if (_currentUser == null) return;

    _currentUser!.trips = List.from(trips);
    await _storageService.saveUser(_currentUser!);
  }

  /// Logs out the current user and clears session
  void logout() {
    _currentUser = null;
    _errorMessage = null;
    notifyListeners();
  }
}
