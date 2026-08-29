// lib/providers/trip_provider.dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/enums.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/person.dart';
import '../models/trip.dart';
import '../services/calculation_service.dart';

class TripProvider extends ChangeNotifier {
  List<Trip> _trips = [];
  final _uuid = const Uuid();
  Future<void> Function(List<Trip>)? _onSaveCallback;
  bool _hasPendingSync = true; // True by default so initial startup syncs with DB

  List<Trip> get trips => List.unmodifiable(_trips);
  bool get hasPendingSync => _hasPendingSync;

  void markPendingSync() {
    _hasPendingSync = true;
    notifyListeners();
  }

  void clearPendingSync() {
    _hasPendingSync = false;
    notifyListeners();
  }

  /// Initializes the provider with a user's trips and a save callback
  void loadUserTrips(List<Trip> trips, {Future<void> Function(List<Trip>)? onSave}) {
    _trips = List.from(trips);
    _onSaveCallback = onSave;
    _hasPendingSync = true;
    notifyListeners();
  }

  /// Seamlessly updates trips from background live-sync without overwriting save callbacks
  void updateFromRemote(List<Trip> remoteTrips) {
    _trips = List.from(remoteTrips);
    _hasPendingSync = false;
    notifyListeners();
  }

  /// Clears all loaded trips (used on logout)
  void clearTrips() {
    _trips = [];
    _onSaveCallback = null;
    _hasPendingSync = false;
    notifyListeners();
  }

  void _persist() {
    _hasPendingSync = true;
    _onSaveCallback?.call(_trips);
  }

  void addTrip(String name, {String? description}) {
    final trip = Trip(
      id: _uuid.v4(),
      name: name,
      description: description,
      createdAt: DateTime.now(),
      groups: [],
      expenses: [],
    );
    _trips.add(trip);
    _persist();
    notifyListeners();
  }

  void editTrip(String tripId, String newName, {String? newDescription}) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    trip.name = newName;
    trip.description = newDescription;
    _persist();
    notifyListeners();
  }

  bool deleteTrip(String tripId) {
    final trip = getTrip(tripId);
    if (trip == null) return false;

    // RULE: Admin CANNOT delete trip if members exist!
    if (trip.allMembers.isNotEmpty) {
      return false; // Deletion blocked because members are present
    }

    _trips.removeWhere((t) => t.id == tripId);
    _persist();
    notifyListeners();
    return true;
  }

  Trip? getTrip(String tripId) {
    try {
      return _trips.firstWhere((t) => t.id == tripId);
    } catch (_) {
      return null;
    }
  }

  void addGroup(String tripId, String groupName) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    trip.groups.add(Group(
      id: _uuid.v4(),
      name: groupName,
      members: [],
    ));
    _persist();
    notifyListeners();
  }

  void editGroup(String tripId, String groupId, String newName) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    final groupIndex = trip.groups.indexWhere((g) => g.id == groupId);
    if (groupIndex != -1) {
      trip.groups[groupIndex] = Group(
        id: trip.groups[groupIndex].id,
        name: newName,
        members: trip.groups[groupIndex].members,
      );
      _persist();
      notifyListeners();
    }
  }

  void deleteGroup(String tripId, String groupId) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    trip.groups.removeWhere((g) => g.id == groupId);
    _persist();
    notifyListeners();
  }

  bool addPerson(String tripId, String groupId, String name, DietType dietType, {String? userId, String? phone}) {
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

    final group = trip.groups.firstWhere((g) => g.id == groupId);
    group.members.add(Person(
      id: _uuid.v4(),
      userId: userId,
      phone: phone,
      name: name.trim(),
      dietType: dietType,
    ));
    _persist();
    notifyListeners();
    return true;
  }

  void editPerson(String tripId, String groupId, String personId, String newName, DietType newDietType, {String? userId, String? phone}) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    try {
      final group = trip.groups.firstWhere((g) => g.id == groupId);
      final memberIndex = group.members.indexWhere((m) => m.id == personId);
      if (memberIndex != -1) {
        group.members[memberIndex] = Person(
          id: personId,
          userId: userId ?? group.members[memberIndex].userId,
          phone: phone ?? group.members[memberIndex].phone,
          name: newName,
          dietType: newDietType,
          paidAmount: group.members[memberIndex].paidAmount,
          owedAmount: group.members[memberIndex].owedAmount,
          balance: group.members[memberIndex].balance,
        );
        _persist();
        notifyListeners();
      }
    } catch (_) {}
  }

  void deletePerson(String tripId, String groupId, String personId) {
    final trip = getTrip(tripId);
    if (trip == null) return;

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

      _persist();
      notifyListeners();
    } catch (_) {}
  }

  void addExpense(String tripId, Expense expense) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    trip.expenses.add(expense);
    _persist();
    notifyListeners();
  }

  void editExpense(String tripId, Expense updatedExpense) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    final index = trip.expenses.indexWhere((e) => e.id == updatedExpense.id);
    if (index != -1) {
      trip.expenses[index] = updatedExpense;
      _persist();
      notifyListeners();
    }
  }

  void deleteExpense(String tripId, String expenseId) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    trip.expenses.removeWhere((e) => e.id == expenseId);
    _persist();
    notifyListeners();
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