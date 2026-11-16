import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_split/models/enums.dart';
import 'package:trip_split/models/expense.dart';
import 'package:trip_split/models/group.dart';
import 'package:trip_split/models/notification.dart';
import 'package:trip_split/models/person.dart';
import 'package:trip_split/models/settlement_proposal.dart';
import 'package:trip_split/models/trip.dart';
import 'package:trip_split/models/user.dart';
import 'package:trip_split/providers/auth_provider.dart';
import 'package:trip_split/providers/trip_provider.dart';
import 'package:trip_split/services/api_service.dart';
import 'package:trip_split/services/storage_service.dart';

class MockApiService extends ApiService {
  final Map<String, UserModel> _users = {};

  MockApiService() : super.test();

  @override
  Future<Map<String, dynamic>> register({
    required String phone,
    required String fullName,
    required String password,
    String? username,
    String? email,
    String? otp,
    int dietType = 0,
    String? dietName,
  }) async {
    if (_users.containsKey(phone)) {
      return {'success': false, 'message': 'Account with this phone already exists'};
    }
    final user = UserModel(
      id: 'mock-user-${DateTime.now().millisecondsSinceEpoch}',
      fullName: fullName,
      phone: phone,
      username: username ?? fullName,
      password: password,
      token: 'mock-token-123',
      dietType: dietType,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );
    _users[phone] = user;
    return {'success': true, 'user': user, 'token': 'mock-token-123'};
  }

  @override
  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
    String? email,
    String? username,
  }) async {
    final user = _users[phone];
    if (user == null) {
      return {'success': false, 'message': 'Account not found. Please register first.'};
    }
    if (user.password != password) {
      return {'success': false, 'message': 'Incorrect password.'};
    }
    return {'success': true, 'user': user, 'token': 'mock-token-123'};
  }

  @override
  Future<Map<String, dynamic>> verifyToken({required String token, String? phone}) async {
    if (phone != null && _users.containsKey(phone)) {
      return {'valid': true, 'user': _users[phone]};
    }
    return {'valid': false};
  }

  @override
  Future<List<Trip>> getTrips({String? userId, String? phone, String? token}) async => [];

  @override
  Future<List<NotificationModel>> getNotifications({String? userId, String? token}) async => [];

  @override
  Future<List<SettlementProposal>> getPendingSettlements({String? userId, String? phone, String? token}) async => [];

  @override
  Future<Map<String, dynamic>> createTrip({required Trip trip, String? currencyCode, String? token, String? userId}) async => {
    'success': true,
    'data': {'tripId': trip.id},
  };

  @override
  Future<Map<String, dynamic>> createGroup({required String tripId, required String name, String? token}) async => {
    'success': true,
    'data': {'groupId': 'group-1'},
  };

  @override
  Future<Map<String, dynamic>> createPerson({
    required String tripId,
    required String groupId,
    required String name,
    String? phone,
    String? userId,
    int dietType = 0,
    String? dietName,
    String? token,
  }) async => {
    'success': true,
    'data': {'personId': 'person-1'},
  };

  @override
  Future<Map<String, dynamic>> createExpense(Map<String, dynamic> expenseDto, {String? token}) async => {
    'success': true,
    'data': {'expenseId': 'exp-100'},
  };

  @override
  Future<bool> logout([String? token]) async => true;
}

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

  group('StorageService Session Tests', () {
    test('saveAuthToken and getAuthToken persists JWT token and credentials', () async {
      final storage = StorageService();
      await storage.saveAuthToken('jwt-token-xyz', phone: '9876543210', userId: 'usr-1');

      expect(await storage.getAuthToken(), 'jwt-token-xyz');
      expect(await storage.getSavedPhone(), '9876543210');
      expect(await storage.getSavedUserId(), 'usr-1');

      await storage.clearAuthToken();
      expect(await storage.getAuthToken(), isNull);
    });

    test('biometric preferences persist correctly', () async {
      final storage = StorageService();
      expect(await storage.isBiometricEnabled(), isFalse);

      await storage.setBiometricEnabled(true);
      expect(await storage.isBiometricEnabled(), isTrue);
    });
  });

  group('AuthProvider Tests', () {
    test('register successfully creates account and logs in', () async {
      final storage = StorageService(baseDirPath: testDir);
      final api = MockApiService();
      final auth = AuthProvider(storageService: storage, apiService: api);

      final success = await auth.register(
        phone: '9876543210',
        fullName: 'Charlie Brown',
        password: 'secure123',
        confirmPassword: 'secure123',
      );
      expect(success, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.fullName, 'Charlie Brown');

      // Duplicate registration should fail
      final duplicate = await auth.register(
        phone: '9876543210',
        fullName: 'Charlie Brown',
        password: 'anotherPass',
        confirmPassword: 'anotherPass',
      );
      expect(duplicate, isFalse);
    });

    test('login with correct credentials succeeds and invalid password fails', () async {
      final storage = StorageService(baseDirPath: testDir);
      final api = MockApiService();
      final auth = AuthProvider(storageService: storage, apiService: api);

      await auth.register(
        phone: '9876543211',
        fullName: 'David Miller',
        password: 'correctPass',
        confirmPassword: 'correctPass',
      );
      await auth.logout();
      expect(auth.isAuthenticated, isFalse);

      // Wrong password
      final wrong = await auth.login('9876543211', 'wrongPass');
      expect(wrong, isFalse);
      expect(auth.errorMessage, isNotNull);

      // Non-existent user
      final notFound = await auth.login('9999999999', 'pass');
      expect(notFound, isFalse);
      expect(auth.errorMessage, isNotNull);

      // Correct password
      final correct = await auth.login('9876543211', 'correctPass');
      expect(correct, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.fullName, 'David Miller');
    });
  });

  group('TripProvider Tests', () {
    test('trip mutations manage in-memory trips and invoke backend APIs', () async {
      final storage = StorageService();
      final api = MockApiService();
      final auth = AuthProvider(storageService: storage, apiService: api);

      await auth.register(
        phone: '9876543212',
        fullName: 'Emma Watson',
        password: 'pass1234',
        confirmPassword: 'pass1234',
      );
      final tripProvider = TripProvider(apiService: api);

      // Connect trip provider with user
      tripProvider.loadUserTrips(
        auth.currentUser!.trips,
        token: auth.currentUser!.token,
      );

      // Add a trip
      await tripProvider.addTrip('Kerala Backwaters', description: 'Houseboat stay');
      expect(tripProvider.trips.length, 1);

      // Add a group and person
      final tripId = tripProvider.trips.first.id;
      await tripProvider.addGroup(tripId, 'Group A');
      final groupId = tripProvider.trips.first.groups.first.id;
      await tripProvider.addPerson(tripId, groupId, 'Emma', DietType.vegetarian);

      // Add an expense
      final personId = tripProvider.trips.first.groups.first.members.first.id;
      await tripProvider.addExpense(
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

      expect(tripProvider.trips.length, 1);
      expect(tripProvider.trips.first.name, 'Kerala Backwaters');
      expect(tripProvider.trips.first.groups.first.name, 'Group A');
      expect(tripProvider.trips.first.groups.first.members.first.name, 'Emma');
      expect(tripProvider.trips.first.expenses.first.amount, 5000);
    });
  });
}
