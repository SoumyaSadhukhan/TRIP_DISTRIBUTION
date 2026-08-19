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

  List<Trip> get trips => List.unmodifiable(_trips);

  /// Initializes the provider with a user's trips and a save callback
  void loadUserTrips(List<Trip> trips, {Future<void> Function(List<Trip>)? onSave}) {
    _trips = List.from(trips);
    _onSaveCallback = onSave;
    notifyListeners();
  }

  /// Clears all loaded trips (used on logout)
  void clearTrips() {
    _trips = [];
    _onSaveCallback = null;
    notifyListeners();
  }

  void _persist() {
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

  void deleteTrip(String tripId) {
    _trips.removeWhere((t) => t.id == tripId);
    _persist();
    notifyListeners();
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

  void addPerson(String tripId, String groupId, String name, DietType dietType) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    final group = trip.groups.firstWhere((g) => g.id == groupId);
    group.members.add(Person(
      id: _uuid.v4(),
      name: name,
      dietType: dietType,
    ));
    _persist();
    notifyListeners();
  }

  void editPerson(String tripId, String groupId, String personId, String newName, DietType newDietType) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    try {
      final group = trip.groups.firstWhere((g) => g.id == groupId);
      final memberIndex = group.members.indexWhere((m) => m.id == personId);
      if (memberIndex != -1) {
        group.members[memberIndex] = Person(
          id: personId,
          name: newName,
          dietType: newDietType,
        );
        _persist();
        notifyListeners();
      }
    } catch (_) {}
  }

  void deletePerson(String tripId, String groupId, String personId) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    final group = trip.groups.firstWhere((g) => g.id == groupId);
    group.members.removeWhere((m) => m.id == personId);

    // Also remove from expenses
    for (var expense in trip.expenses) {
      expense.splitAmongIds.remove(personId);
      if (expense.paidById == personId) {
        expense.paidById = '';
      }
    }

    _persist();
    notifyListeners();
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