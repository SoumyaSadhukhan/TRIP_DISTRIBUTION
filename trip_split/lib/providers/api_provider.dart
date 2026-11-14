import 'package:flutter/foundation.dart';
import '../models/activity_log.dart';
import '../models/collaborator.dart';
import '../models/friend.dart';
import '../models/notification.dart';
import '../models/settlement_proposal.dart';
import '../models/trip.dart';
import '../services/api_service.dart';

class ApiProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  String? _error;

  List<Trip> _userTrips = [];
  List<FriendModel> _userFriends = [];
  List<CollaboratorModel> _tripCollaborators = [];
  List<ActivityLogModel> _tripActivityLogs = [];
  List<SettlementProposal> _tripSettlements = [];
  List<NotificationModel> _notifications = [];
  int _unreadNotificationCount = 0;

  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Trip> get userTrips => _userTrips;
  List<FriendModel> get userFriends => _userFriends;
  List<CollaboratorModel> get tripCollaborators => _tripCollaborators;
  List<ActivityLogModel> get tripActivityLogs => _tripActivityLogs;
  List<SettlementProposal> get tripSettlements => _tripSettlements;
  List<NotificationModel> get notifications => _notifications;
  int get unreadNotificationCount => _unreadNotificationCount;

  ApiService get apiService => _apiService;

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? err) {
    _error = err;
    notifyListeners();
  }

  // ==========================================
  // 1. AUTH METHODS
  // ==========================================

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

  // ==========================================
  // 2. TRIPS METHODS (APIs 12-17)
  // ==========================================

  Future<void> fetchUserTrips({String? userId, String? token}) async {
    setLoading(true);
    try {
      _userTrips = await _apiService.getTrips(userId: userId, token: token);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<Map<String, dynamic>> createTrip(Trip trip, {String? token}) async {
    return await _apiService.createTrip(trip: trip, token: token);
  }

  Future<Map<String, dynamic>> updateTrip(String tripId, String name, {String? description, String? token}) async {
    return await _apiService.updateTrip(tripId: tripId, name: name, description: description, token: token);
  }

  Future<bool> deleteTrip(String tripId, {String? token}) async {
    final success = await _apiService.deleteTrip(tripId, token: token);
    if (success) {
      _userTrips.removeWhere((t) => t.id == tripId);
      notifyListeners();
    }
    return success;
  }

  // ==========================================
  // 3. EXPENSES METHODS (APIs 18-23)
  // ==========================================

  Future<List<Map<String, dynamic>>> fetchExpenses(String tripId, {String? token}) async {
    return await _apiService.getExpensesByTrip(tripId, token: token);
  }

  Future<Map<String, dynamic>> createExpense(Map<String, dynamic> dto, {String? token}) async {
    return await _apiService.createExpense(dto, token: token);
  }

  Future<Map<String, dynamic>> updateExpense(String expenseId, Map<String, dynamic> dto, {String? token}) async {
    return await _apiService.updateExpense(expenseId, dto, token: token);
  }

  Future<bool> deleteExpense(String expenseId, {String? token}) async {
    return await _apiService.deleteExpense(expenseId, token: token);
  }

  Future<Map<String, dynamic>> calculateDietarySplit(String tripId, double amount, int categoryIndex, {List<String>? personIds, String? token}) async {
    return await _apiService.calculateDietarySplit(tripId: tripId, totalAmount: amount, categoryIndex: categoryIndex, personIds: personIds, token: token);
  }

  // ==========================================
  // 4. GROUPS METHODS (APIs 24-27)
  // ==========================================

  Future<List<Map<String, dynamic>>> fetchGroups(String tripId, {String? token}) async {
    return await _apiService.getGroupsByTrip(tripId, token: token);
  }

  Future<Map<String, dynamic>> createGroup(String tripId, String name, {String? token}) async {
    return await _apiService.createGroup(tripId: tripId, name: name, token: token);
  }

  Future<Map<String, dynamic>> updateGroup(String groupId, String name, {String? token}) async {
    return await _apiService.updateGroup(groupId: groupId, name: name, token: token);
  }

  Future<bool> deleteGroup(String groupId, {String? token}) async {
    return await _apiService.deleteGroup(groupId, token: token);
  }

  // ==========================================
  // 5. PERSONS METHODS (APIs 28-33)
  // ==========================================

  Future<List<Map<String, dynamic>>> fetchPersons(String tripId, {String? token}) async {
    return await _apiService.getPersonsByTrip(tripId, token: token);
  }

  Future<Map<String, dynamic>> createPerson({
    required String tripId,
    required String groupId,
    required String name,
    String? phone,
    String? userId,
    int dietType = 0,
    String? token,
  }) async {
    return await _apiService.createPerson(
      tripId: tripId,
      groupId: groupId,
      name: name,
      phone: phone,
      userId: userId,
      dietType: dietType,
      token: token,
    );
  }

  Future<Map<String, dynamic>> updatePerson({
    required String personId,
    required String name,
    String? phone,
    int? dietType,
    String? token,
  }) async {
    return await _apiService.updatePerson(
      personId: personId,
      name: name,
      phoneNumber: phone,
      dietType: dietType,
      token: token,
    );
  }

  Future<bool> deletePerson(String personId, {String? token}) async {
    return await _apiService.deletePerson(personId, token: token);
  }

  Future<Map<String, dynamic>> recalculateTrip(String tripId, {String? token}) async {
    return await _apiService.recalculateTrip(tripId, token: token);
  }

  // ==========================================
  // 6. SETTLEMENTS METHODS (APIs 34-38)
  // ==========================================

  Future<void> fetchSettlements(String tripId, {String? token}) async {
    setLoading(true);
    try {
      _tripSettlements = await _apiService.getSettlementsByTrip(tripId, token: token);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<Map<String, dynamic>> proposeSettlement({
    required String tripId,
    required String fromPersonId,
    required String toPersonId,
    required double amount,
    String? notes,
    String? token,
  }) async {
    return await _apiService.proposeSettlement(
      tripId: tripId,
      fromPersonId: fromPersonId,
      toPersonId: toPersonId,
      amount: amount,
      notes: notes,
      token: token,
    );
  }

  Future<Map<String, dynamic>> updateSettlementStatus(String settlementId, String status, {String? token}) async {
    return await _apiService.updateSettlementStatus(settlementId: settlementId, status: status, token: token);
  }

  Future<bool> deleteSettlement(String settlementId, {String? token}) async {
    return await _apiService.deleteSettlement(settlementId, token: token);
  }

  // ==========================================
  // 7. FRIENDS METHODS (APIs 39-45)
  // ==========================================

  Future<void> fetchFriends({String? userId, String? token}) async {
    setLoading(true);
    try {
      _userFriends = await _apiService.getFriends(userId: userId, token: token);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<List<Map<String, dynamic>>> checkContacts(List<String> phoneNumbers, {String? token}) async {
    return await _apiService.checkContacts(phoneNumbers, token: token);
  }

  Future<Map<String, dynamic>> addFriend({String? friendPhone, String? friendName, int? dietType, String? token}) async {
    return await _apiService.addFriend(friendPhone: friendPhone, friendName: friendName, dietType: dietType, token: token);
  }

  Future<List<Map<String, dynamic>>> searchUsers(String phone, {String? token}) async {
    return await _apiService.searchUsers(phone, token: token);
  }

  Future<List<Map<String, dynamic>>> fetchFriendRequests({String type = 'all', String? token}) async {
    return await _apiService.getFriendRequests(type: type, token: token);
  }

  Future<Map<String, dynamic>> updateFriendStatus(String connectionId, String status, {String? token}) async {
    return await _apiService.updateFriendStatus(connectionId: connectionId, status: status, token: token);
  }

  Future<bool> deleteFriend(String connectionId, {String? token}) async {
    return await _apiService.deleteFriend(connectionId, token: token);
  }

  // ==========================================
  // 8. COLLABORATORS METHODS (APIs 46-49)
  // ==========================================

  Future<void> fetchCollaborators(String tripId, {String? token}) async {
    setLoading(true);
    try {
      _tripCollaborators = await _apiService.getCollaborators(tripId, token: token);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<Map<String, dynamic>> inviteCollaborator({
    required String tripId,
    String? userId,
    String? phoneNumber,
    String role = 'MEMBER',
    String? token,
  }) async {
    return await _apiService.inviteCollaborator(
      tripId: tripId,
      userId: userId,
      phoneNumber: phoneNumber,
      role: role,
      token: token,
    );
  }

  Future<Map<String, dynamic>> updateCollaboratorRole(String collabId, String role, {String? token}) async {
    return await _apiService.updateCollaboratorRole(collabId: collabId, role: role, token: token);
  }

  Future<bool> removeCollaborator(String collabId, {String? token}) async {
    return await _apiService.removeCollaborator(collabId, token: token);
  }

  // ==========================================
  // 9. NOTIFICATIONS METHODS (APIs 50-53)
  // ==========================================

  Future<void> fetchNotifications({String? token}) async {
    setLoading(true);
    try {
      _notifications = await _apiService.getNotifications(token: token);
      _unreadNotificationCount = await _apiService.getUnreadNotificationCount(token: token);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<bool> markNotificationsRead({List<String>? notificationIds, String? token}) async {
    final success = await _apiService.markNotificationsRead(notificationIds: notificationIds, token: token);
    if (success) {
      _unreadNotificationCount = 0;
      notifyListeners();
    }
    return success;
  }

  Future<Map<String, dynamic>> sendNotification({
    required String toUserId,
    required String message,
    String? tripId,
    String? token,
  }) async {
    return await _apiService.sendNotification(toUserId: toUserId, message: message, tripId: tripId, token: token);
  }

  // ==========================================
  // 10. ACTIVITY LOGS METHODS (API 54)
  // ==========================================

  Future<void> fetchActivityLogs(String tripId, {String? token}) async {
    setLoading(true);
    try {
      _tripActivityLogs = await _apiService.getActivityLogs(tripId, token: token);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }
}
