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
  final List<Trip> _trips = [];
  final _uuid = const Uuid();

  List<Trip> get trips => List.unmodifiable(_trips);

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
    notifyListeners();
  }

  void deleteTrip(String tripId) {
    _trips.removeWhere((t) => t.id == tripId);
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
    notifyListeners();
  }

  void deleteGroup(String tripId, String groupId) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    trip.groups.removeWhere((g) => g.id == groupId);
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
    notifyListeners();
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
    
    notifyListeners();
  }

  void addExpense(String tripId, Expense expense) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    trip.expenses.add(expense);
    notifyListeners();
  }

  void deleteExpense(String tripId, String expenseId) {
    final trip = getTrip(tripId);
    if (trip == null) return;

    trip.expenses.removeWhere((e) => e.id == expenseId);
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