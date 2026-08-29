import 'package:flutter/foundation.dart';
import '../models/friend.dart';
import '../models/trip.dart';
import '../services/api_service.dart';

class ApiProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  String? _error;
  List<Trip> _userTrips = [];
  List<FriendModel> _userFriends = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Trip> get userTrips => _userTrips;
  List<FriendModel> get userFriends => _userFriends;
  ApiService get apiService => _apiService;

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? err) {
    _error = err;
    notifyListeners();
  }

  Future<bool> login(String phone, String password) async {
    setLoading(true);
    setError(null);
    try {
      final result = await _apiService.login(phone: phone, password: password);
      setLoading(false);
      if (result['success'] == true) {
        return true;
      } else {
        setError(result['message'] ?? 'Login failed');
        return false;
      }
    } catch (e) {
      setLoading(false);
      setError(e.toString());
      return false;
    }
  }

  Future<bool> register({
    required String phone,
    required String fullName,
    required String password,
    required int dietType,
  }) async {
    setLoading(true);
    setError(null);
    try {
      final result = await _apiService.register(
        phone: phone,
        fullName: fullName,
        password: password,
        dietType: dietType,
      );
      setLoading(false);
      if (result['success'] == true) {
        return true;
      } else {
        setError(result['message'] ?? 'Registration failed');
        return false;
      }
    } catch (e) {
      setLoading(false);
      setError(e.toString());
      return false;
    }
  }

  Future<void> fetchUserTrips(String userId) async {
    setLoading(true);
    try {
      _userTrips = await _apiService.getTrips(userId: userId);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<void> fetchFriends(String userId) async {
    setLoading(true);
    try {
      _userFriends = await _apiService.getFriends(userId);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }
}
