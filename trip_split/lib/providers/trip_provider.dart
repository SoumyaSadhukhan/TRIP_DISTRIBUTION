// lib/providers/trip_provider.dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/enums.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/person.dart';
import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/calculation_service.dart';

class TripProvider extends ChangeNotifier {
  final ApiService _apiService;
  final _uuid = const Uuid();
  List<Trip> _trips = [];
  String? _token;

  TripProvider({ApiService? apiService}) : _apiService = apiService ?? ApiService();

  List<Trip> get trips => List.unmodifiable(_trips);
  bool get hasPendingSync => false; // Direct API writes ensure zero pending offline lag

  void markPendingSync() {
    notifyListeners();
  }

  void clearPendingSync() {
    notifyListeners();
  }

  /// Sets the active auth token for API calls
  void setToken(String? token) {
    _token = token;
  }

  /// Initializes the provider with user trips fetched from SQL Server database
  void loadUserTrips(List<Trip> trips, {Future<void> Function(List<Trip>)? onSave, String? token}) {
    _trips = List.from(trips);
    if (token != null) _token = token;
    notifyListeners();
  }

  /// Updates trips from remote database state
  void updateFromRemote(List<Trip> remoteTrips) {
    _trips = List.from(remoteTrips);
    notifyListeners();
  }

  /// Clears all loaded trips (used on logout)
  void clearTrips() {
    _trips = [];
    _token = null;
    notifyListeners();
  }

  Trip? getTrip(String tripId) {
    try {
      return _trips.firstWhere((t) => t.id == tripId);
    } catch (_) {
      return null;
    }
  }

  /// Directly creates trip in SQL Server database via POST /api/Trips
  Future<Trip?> addTrip(String name, {String? description, String? token}) async {
    final tempId = _uuid.v4();
    final localTrip = Trip(
      id: tempId,
      name: name,
      description: description,
      createdAt: DateTime.now(),
      groups: [],
      expenses: [],
    );
    _trips.add(localTrip);
    notifyListeners();

    try {
      final res = await _apiService.createTrip(
        trip: localTrip,
        token: token ?? _token,
      );
      if (res['success'] == true) {
        final data = res['data'] ?? {};
        final backendTripId = (data['tripId'] ?? data['id'] ?? '').toString();
        if (backendTripId.isNotEmpty) {
          // Fetch full trip details from database so auto-generated group & person are populated
          final detailRes = await _apiService.getTripById(backendTripId, token: token ?? _token);
          if (detailRes['success'] == true && detailRes['trip'] != null) {
            final dbTrip = Trip.fromJson(detailRes['trip']);
            final idx = _trips.indexWhere((t) => t.id == tempId || t.id == backendTripId);
            if (idx != -1) {
              _trips[idx] = dbTrip;
            } else {
              _trips.add(dbTrip);
            }
            notifyListeners();
            return dbTrip;
          }
        }
      }
    } catch (e) {
      debugPrint('[TripProvider] addTrip API error: $e');
    }
    return localTrip;
  }

  /// Directly updates trip in SQL Server database via PUT /api/Trips/{id}
  Future<bool> editTrip(String tripId, String newName, {String? newDescription, String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    trip.name = newName;
    trip.description = newDescription;
    notifyListeners();

    try {
      final res = await _apiService.updateTrip(
        tripId: tripId,
        name: newName,
        description: newDescription,
        token: token ?? _token,
      );
      return res['success'] == true;
    } catch (e) {
      debugPrint('[TripProvider] editTrip API error: $e');
      return false;
    }
  }

  /// Directly deletes trip in SQL Server database via DELETE /api/Trips/{id}
  Future<bool> deleteTrip(String tripId, {String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    // RULE: Admin CANNOT delete trip if members exist (excluding trip creator/owner alone)
    if (trip.allMembers.length > 1) {
      return false; // Deletion blocked because members are present
    }

    _trips.removeWhere((t) => t.id == tripId);
    notifyListeners();

    try {
      return await _apiService.deleteTrip(tripId, token: token ?? _token);
    } catch (e) {
      debugPrint('[TripProvider] deleteTrip API error: $e');
      return false;
    }
  }

  /// Directly creates group in SQL Server database via POST /api/Groups
  Future<Group?> addGroup(String tripId, String groupName, {String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return null;

    final tempGroupId = _uuid.v4();
    final newGroup = Group(
      id: tempGroupId,
      name: groupName,
      members: [],
    );
    trip.groups.add(newGroup);
    notifyListeners();

    try {
      final res = await _apiService.createGroup(
        tripId: tripId,
        name: groupName,
        token: token ?? _token,
      );
      if (res['success'] == true && res['data'] != null) {
        final data = res['data'];
        final backendGroupId = (data['groupId'] ?? data['id'] ?? '').toString();
        if (backendGroupId.isNotEmpty && backendGroupId != tempGroupId) {
          final idx = trip.groups.indexWhere((g) => g.id == tempGroupId);
          if (idx != -1) {
            trip.groups[idx] = trip.groups[idx].copyWith(id: backendGroupId);
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[TripProvider] addGroup API error: $e');
    }
    return newGroup;
  }

  /// Directly updates group in SQL Server database via PUT /api/Groups/{id}
  Future<bool> editGroup(String tripId, String groupId, String newName, {String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    final groupIndex = trip.groups.indexWhere((g) => g.id == groupId);
    if (groupIndex != -1) {
      trip.groups[groupIndex] = trip.groups[groupIndex].copyWith(name: newName);
      notifyListeners();

      try {
        final res = await _apiService.updateGroup(
          groupId: groupId,
          name: newName,
          token: token ?? _token,
        );
        return res['success'] == true;
      } catch (e) {
        debugPrint('[TripProvider] editGroup API error: $e');
      }
    }
    return false;
  }

  /// Directly deletes group in SQL Server database via DELETE /api/Groups/{id}
  Future<bool> deleteGroup(String tripId, String groupId, {String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    trip.groups.removeWhere((g) => g.id == groupId);
    notifyListeners();

    try {
      return await _apiService.deleteGroup(groupId, token: token ?? _token);
    } catch (e) {
      debugPrint('[TripProvider] deleteGroup API error: $e');
      return false;
    }
  }

  /// Directly adds member to SQL Server database via POST /api/Persons
  Future<bool> addPerson(
    String tripId,
    String groupId,
    String name,
    DietType dietType, {
    String? userId,
    String? phone,
    String? token,
  }) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    // Unique Member & Phone Validation across all groups in the trip
    final cleanName = name.trim().toLowerCase();
    final cleanPhone = phone?.replaceAll(RegExp(r'[^0-9]'), '').toLowerCase() ?? '';

    for (var member in trip.allMembers) {
      if (member.name.trim().toLowerCase() == cleanName) {
        return false; // Duplicate name
      }
      if (cleanPhone.isNotEmpty && member.phone != null) {
        final memberPhone = member.phone!.replaceAll(RegExp(r'[^0-9]'), '').toLowerCase();
        if (memberPhone.isNotEmpty && memberPhone == cleanPhone) {
          return false; // Duplicate phone
        }
      }
    }

    final groupIndex = trip.groups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) return false;

    final tempPersonId = _uuid.v4();
    final person = Person(
      id: tempPersonId,
      groupId: groupId,
      userId: userId,
      phone: phone,
      name: name.trim(),
      dietType: dietType,
    );
    trip.groups[groupIndex].members.add(person);
    notifyListeners();

    try {
      final res = await _apiService.createPerson(
        tripId: tripId,
        groupId: groupId,
        name: name.trim(),
        dietType: dietType.index,
        phone: phone,
        userId: userId,
        token: token ?? _token,
      );
      if (res['success'] == true && res['data'] != null) {
        final data = res['data'];
        final backendPersonId = (data['personId'] ?? data['id'] ?? '').toString();
        if (backendPersonId.isNotEmpty && backendPersonId != tempPersonId) {
          final mIdx = trip.groups[groupIndex].members.indexWhere((m) => m.id == tempPersonId);
          if (mIdx != -1) {
            trip.groups[groupIndex].members[mIdx] = Person(
              id: backendPersonId,
              groupId: groupId,
              userId: userId,
              phone: phone,
              name: name.trim(),
              dietType: dietType,
            );
            notifyListeners();
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('[TripProvider] addPerson API error: $e');
      return true;
    }
  }

  /// Directly updates member in SQL Server database via PUT /api/Persons/{id}
  Future<bool> editPerson(
    String tripId,
    String groupId,
    String personId,
    String newName,
    DietType newDietType, {
    String? userId,
    String? phone,
    String? token,
  }) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    try {
      final group = trip.groups.firstWhere((g) => g.id == groupId);
      final memberIndex = group.members.indexWhere((m) => m.id == personId);
      if (memberIndex != -1) {
        group.members[memberIndex] = Person(
          id: personId,
          groupId: groupId,
          userId: userId ?? group.members[memberIndex].userId,
          phone: phone ?? group.members[memberIndex].phone,
          name: newName,
          dietType: newDietType,
          paidAmount: group.members[memberIndex].paidAmount,
          owedAmount: group.members[memberIndex].owedAmount,
          balance: group.members[memberIndex].balance,
        );
        notifyListeners();

        try {
          await _apiService.updatePerson(
            personId: personId,
            name: newName,
            phoneNumber: phone,
            dietType: newDietType.index,
            token: token ?? _token,
          );
        } catch (e) {
          debugPrint('[TripProvider] editPerson API error: $e');
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Directly deletes member in SQL Server database via DELETE /api/Persons/{id}
  Future<bool> deletePerson(String tripId, String groupId, String personId, {String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    try {
      final group = trip.groups.firstWhere((g) => g.id == groupId);
      group.members.removeWhere((m) => m.id == personId);

      // Automatically remove expenses paid by deleted member
      trip.expenses.removeWhere((exp) => exp.paidById == personId);

      // For remaining expenses, remove member from split lists
      for (var expense in trip.expenses) {
        expense.splitAmongIds.remove(personId);
      }

      // Remove any expenses that have no split members left
      trip.expenses.removeWhere((exp) => exp.splitAmongIds.isEmpty);

      // Recalculate member balances
      CalculationService.calculateBalances(trip);
      notifyListeners();

      try {
        await _apiService.deletePerson(personId, token: token ?? _token);
      } catch (e) {
        debugPrint('[TripProvider] deletePerson API error: $e');
      }
      return true;
    } catch (_) {}
    return false;
  }

  /// Directly adds expense to SQL Server database via POST /api/Expenses with calculated splits
  Future<Expense?> addExpense(String tripId, Expense expense, {String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return null;

    final tempExpenseId = expense.id.isNotEmpty ? expense.id : _uuid.v4();
    final localExpense = Expense(
      id: tempExpenseId,
      description: expense.description,
      amount: expense.amount,
      category: expense.category,
      paidById: expense.paidById,
      date: expense.date,
      splitAmongIds: List.from(expense.splitAmongIds),
    );
    trip.expenses.add(localExpense);
    CalculationService.calculateBalances(trip);
    notifyListeners();

    // Prepare splits guaranteeing sum equals amount to 2 decimal places (DEF-01 invariant)
    final splitIds = localExpense.splitAmongIds.isNotEmpty
        ? localExpense.splitAmongIds
        : [localExpense.paidById];
    final count = splitIds.length;
    final totalAmount = localExpense.amount;
    final baseSplit = (totalAmount / count * 100).floor() / 100.0;
    var currentSum = 0.0;
    final splits = <Map<String, dynamic>>[];
    for (int i = 0; i < count; i++) {
      double splitAmt;
      if (i == count - 1) {
        splitAmt = double.parse((totalAmount - currentSum).toStringAsFixed(2));
      } else {
        splitAmt = baseSplit;
        currentSum += splitAmt;
      }
      splits.add({'personId': splitIds[i], 'amount': splitAmt});
    }

    try {
      final res = await _apiService.createExpense({
        'tripId': tripId,
        'description': localExpense.description,
        'amount': localExpense.amount,
        'currencyCode': 'INR',
        'categoryIndex': localExpense.category.index,
        'categoryName': localExpense.category.name,
        'paidByPersonId': localExpense.paidById,
        'splitType': 'EQUAL',
        'expenseDate': localExpense.date.toIso8601String(),
        'splits': splits,
      }, token: token ?? _token);

      if (res['success'] == true && res['data'] != null) {
        final data = res['data'];
        final backendExpenseId = (data['expenseId'] ?? data['id'] ?? '').toString();
        if (backendExpenseId.isNotEmpty && backendExpenseId != tempExpenseId) {
          final idx = trip.expenses.indexWhere((e) => e.id == tempExpenseId);
          if (idx != -1) {
            trip.expenses[idx] = Expense(
              id: backendExpenseId,
              description: localExpense.description,
              amount: localExpense.amount,
              category: localExpense.category,
              paidById: localExpense.paidById,
              date: localExpense.date,
              splitAmongIds: localExpense.splitAmongIds,
            );
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[TripProvider] addExpense API error: $e');
    }
    return localExpense;
  }

  /// Directly updates expense in SQL Server database via PUT /api/Expenses/{id}
  Future<bool> editExpense(String tripId, Expense updatedExpense, {String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    final index = trip.expenses.indexWhere((e) => e.id == updatedExpense.id);
    if (index != -1) {
      trip.expenses[index] = updatedExpense;
      CalculationService.calculateBalances(trip);
      notifyListeners();

      final splitIds = updatedExpense.splitAmongIds.isNotEmpty
          ? updatedExpense.splitAmongIds
          : [updatedExpense.paidById];
      final count = splitIds.length;
      final totalAmount = updatedExpense.amount;
      final baseSplit = (totalAmount / count * 100).floor() / 100.0;
      var currentSum = 0.0;
      final splits = <Map<String, dynamic>>[];
      for (int i = 0; i < count; i++) {
        double splitAmt;
        if (i == count - 1) {
          splitAmt = double.parse((totalAmount - currentSum).toStringAsFixed(2));
        } else {
          splitAmt = baseSplit;
          currentSum += splitAmt;
        }
        splits.add({'personId': splitIds[i], 'amount': splitAmt});
      }

      try {
        final res = await _apiService.updateExpense(
          updatedExpense.id,
          {
            'description': updatedExpense.description,
            'amount': updatedExpense.amount,
            'currencyCode': 'INR',
            'categoryIndex': updatedExpense.category.index,
            'categoryName': updatedExpense.category.name,
            'paidByPersonId': updatedExpense.paidById,
            'splitType': 'EQUAL',
            'expenseDate': updatedExpense.date.toIso8601String(),
            'splits': splits,
          },
          token: token ?? _token,
        );
        return res['success'] == true;
      } catch (e) {
        debugPrint('[TripProvider] editExpense API error: $e');
      }
    }
    return false;
  }

  /// Directly deletes expense in SQL Server database via DELETE /api/Expenses/{id}
  Future<bool> deleteExpense(String tripId, String expenseId, {String? token}) async {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    trip.expenses.removeWhere((e) => e.id == expenseId);
    CalculationService.calculateBalances(trip);
    notifyListeners();

    try {
      return await _apiService.deleteExpense(expenseId, token: token ?? _token);
    } catch (e) {
      debugPrint('[TripProvider] deleteExpense API error: $e');
      return false;
    }
  }

  /// Refreshes trip data directly from SQL Server database
  Future<void> refreshTripFromRemote(String tripId, {String? token}) async {
    try {
      final res = await _apiService.getTripById(tripId, token: token ?? _token);
      if (res['success'] == true && res['trip'] != null) {
        final refreshedTrip = Trip.fromJson(res['trip']);
        final idx = _trips.indexWhere((t) => t.id == tripId);
        if (idx != -1) {
          _trips[idx] = refreshedTrip;
        } else {
          _trips.add(refreshedTrip);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TripProvider] refreshTrip error: $e');
    }
  }

  List<PersonBalance> getBalances(String tripId) {
    final trip = getTrip(tripId);
    if (trip == null) return [];
    return CalculationService.calculateBalances(trip);
  }

  List<SettlementResult> getSettlements(String tripId) {
    final trip = getTrip(tripId);
    if (trip == null) return [];
    return CalculationService.calculateSettlements(trip);
  }

  double getTotalExpense(String tripId) {
    final trip = getTrip(tripId);
    if (trip == null) return 0.0;
    return trip.expenses.fold(0.0, (sum, e) => sum + e.amount);
  }
}
