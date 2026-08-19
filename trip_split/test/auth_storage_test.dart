// test/auth_storage_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_split/models/enums.dart';
import 'package:trip_split/models/expense.dart';
import 'package:trip_split/models/group.dart';
import 'package:trip_split/models/person.dart';
import 'package:trip_split/models/trip.dart';
import 'package:trip_split/models/user.dart';
import 'package:trip_split/providers/auth_provider.dart';
import 'package:trip_split/providers/trip_provider.dart';
import 'package:trip_split/services/storage_service.dart';

void main() {
  const testDir = 'data/test_users';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory(testDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  tearDown(() async {
    final dir = Directory(testDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('UserModel Tests', () {
    test('toJson and fromJson serializes user with trips properly', () {
      final now = DateTime.now();
      final user = UserModel(
        id: 'u-1',
        username: 'alice',
        password: 'password123',
        createdAt: now,
        lastLoginAt: now,
        trips: [
          Trip(
            id: 't-1',
            name: 'Goa Holiday',
            createdAt: now,
            groups: [
              Group(
                id: 'g-1',
                name: 'Friends',
                members: [
                  Person(id: 'p-1', name: 'Alice', dietType: DietType.nonVegetarian),
                ],
              ),
            ],
            expenses: [
              Expense(
                id: 'e-1',
                description: 'Dinner',
                amount: 1200.0,
                category: ExpenseCategory.nonVeg,
                paidById: 'p-1',
                date: now,
                splitAmongIds: ['p-1'],
              ),
            ],
          ),
        ],
      );

      final json = user.toJson();
      expect(json['username'], 'alice');
      expect(json['password'], 'password123');
      expect((json['trips'] as List).length, 1);

      final deserialized = UserModel.fromJson(json);
      expect(deserialized.id, user.id);
      expect(deserialized.username, 'alice');
      expect(deserialized.password, 'password123');
      expect(deserialized.trips.length, 1);
      expect(deserialized.trips.first.name, 'Goa Holiday');
      expect(deserialized.trips.first.groups.first.members.first.name, 'Alice');
      expect(deserialized.trips.first.expenses.first.amount, 1200.0);
    });
  });

  group('StorageService Tests', () {
    test('saveUser and loadUser stores JSON and retrieves user data', () async {
      final storage = StorageService(baseDirPath: testDir);
      final now = DateTime.now();
      final user = UserModel(
        id: 'u-2',
        username: 'bob',
        password: 'bobpassword',
        createdAt: now,
        lastLoginAt: now,
        trips: [
          Trip(
            id: 't-2',
            name: 'Manali Trek',
            createdAt: now,
            groups: [],
            expenses: [],
          ),
        ],
      );

      await storage.saveUser(user);

      expect(await storage.userExists('bob'), isTrue);

      final loadedUser = await storage.loadUser('bob');
      expect(loadedUser, isNotNull);
      expect(loadedUser!.username, 'bob');
      expect(loadedUser.password, 'bobpassword');
      expect(loadedUser.trips.length, 1);
      expect(loadedUser.trips.first.name, 'Manali Trek');
    });

    test('getAllUsers lists all registered user accounts', () async {
      final storage = StorageService(baseDirPath: testDir);
      final now = DateTime.now();

      await storage.saveUser(UserModel(
        id: 'u-1',
        username: 'user1',
        password: 'p1',
        createdAt: now,
        lastLoginAt: now,
      ));

      await storage.saveUser(UserModel(
        id: 'u-2',
        username: 'user2',
        password: 'p2',
        createdAt: now,
        lastLoginAt: now,
      ));

      final allUsers = await storage.getAllUsers();
      expect(allUsers.length, 2);
      expect(allUsers.map((u) => u.username).toSet(), containsAll(['user1', 'user2']));
    });
  });

  group('AuthProvider Tests', () {
    test('register successfully creates account and logs in', () async {
      final storage = StorageService(baseDirPath: testDir);
      final auth = AuthProvider(storageService: storage);

      final success = await auth.register('charlie', 'secure123');
      expect(success, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.username, 'charlie');
      expect(auth.currentUser?.password, 'secure123');

      // Duplicate registration should fail
      final duplicate = await auth.register('charlie', 'anotherPass');
      expect(duplicate, isFalse);
      expect(auth.errorMessage, contains('already taken'));
    });

    test('login with correct credentials succeeds and invalid password fails', () async {
      final storage = StorageService(baseDirPath: testDir);
      final auth = AuthProvider(storageService: storage);

      await auth.register('david', 'correctPass');
      auth.logout();
      expect(auth.isAuthenticated, isFalse);

      // Wrong password
      final wrong = await auth.login('david', 'wrongPass');
      expect(wrong, isFalse);
      expect(auth.errorMessage, contains('Incorrect password'));

      // Non-existent user
      final notFound = await auth.login('non_existent', 'pass');
      expect(notFound, isFalse);
      expect(auth.errorMessage, contains('not found'));

      // Correct password
      final correct = await auth.login('david', 'correctPass');
      expect(correct, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.username, 'david');
    });
  });

  group('TripProvider Persistence Tests', () {
    test('trip mutations trigger auto-save into user data', () async {
      final storage = StorageService(baseDirPath: testDir);
      final auth = AuthProvider(storageService: storage);

      await auth.register('emma', 'pass1234');
      final tripProvider = TripProvider();

      // Connect trip provider with user and auto-save callback
      tripProvider.loadUserTrips(
        auth.currentUser!.trips,
        onSave: (trips) => auth.saveCurrentUserData(trips),
      );

      // Add a trip
      tripProvider.addTrip('Kerala Backwaters', description: 'Houseboat stay');
      expect(tripProvider.trips.length, 1);

      // Add a group and person
      final tripId = tripProvider.trips.first.id;
      tripProvider.addGroup(tripId, 'Group A');
      final groupId = tripProvider.trips.first.groups.first.id;
      tripProvider.addPerson(tripId, groupId, 'Emma', DietType.vegetarian);

      // Add an expense
      final personId = tripProvider.trips.first.groups.first.members.first.id;
      tripProvider.addExpense(
        tripId,
        Expense(
          id: 'exp-100',
          description: 'Boat Rental',
          amount: 5000,
          category: ExpenseCategory.transport,
          paidById: personId,
          date: DateTime.now(),
          splitAmongIds: [personId],
        ),
      );

      // Wait a tick for async save to finish
      await Future.delayed(const Duration(milliseconds: 100));

      // Reload user from storage and verify all data persisted in JSON
      final loadedUser = await storage.loadUser('emma');
      expect(loadedUser, isNotNull);
      expect(loadedUser!.trips.length, 1);
      expect(loadedUser.trips.first.name, 'Kerala Backwaters');
      expect(loadedUser.trips.first.groups.first.name, 'Group A');
      expect(loadedUser.trips.first.groups.first.members.first.name, 'Emma');
      expect(loadedUser.trips.first.expenses.first.amount, 5000);
    });
  });
}
