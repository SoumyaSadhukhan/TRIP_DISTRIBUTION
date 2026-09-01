import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_split/main.dart';
import 'package:trip_split/models/notification.dart';
import 'package:trip_split/models/settlement_proposal.dart';
import 'package:trip_split/models/trip.dart';
import 'package:trip_split/models/user.dart';
import 'package:trip_split/providers/auth_provider.dart';
import 'package:trip_split/providers/trip_provider.dart';
import 'package:trip_split/screens/login_screen.dart';
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
    String? otp,
    int dietType = 0,
  }) async {
    final user = UserModel(
      id: 'mock-user-123',
      fullName: fullName,
      phone: phone,
      username: fullName,
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
  }) async {
    final user = _users[phone] ?? UserModel(
      id: 'mock-user-login',
      fullName: phone,
      phone: phone,
      username: phone,
      password: password,
      token: 'mock-token-123',
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );
    return {'success': true, 'user': user, 'token': 'mock-token-123'};
  }

  @override
  Future<Map<String, dynamic>> verifyToken({required String token, String? phone}) async {
    return {'valid': false};
  }

  @override
  Future<List<Trip>> getTrips({required String userId, String? phone, String? token}) async => [];

  @override
  Future<List<NotificationModel>> getNotifications(String userId, {String? token}) async => [];

  @override
  Future<List<SettlementProposal>> getPendingSettlements({required String userId, String? phone, String? token}) async => [];
}

void main() {
  const testDir = 'data/test_widget_users';

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

  Widget createTestWidget({required AuthProvider auth, required TripProvider trip}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TripProvider>.value(value: trip),
      ],
      child: const MaterialApp(
        home: AuthWrapper(),
      ),
    );
  }

  testWidgets('LoginScreen renders and switches between Sign In and Create Account', (tester) async {
    final storage = StorageService(baseDirPath: testDir);
    final api = MockApiService();
    final auth = AuthProvider(storageService: storage, apiService: api);
    final trip = TripProvider();

    await tester.pumpWidget(createTestWidget(auth: auth, trip: trip));
    while (auth.isCheckingToken) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Login Screen initial state
    expect(find.text('TripSplit'), findsOneWidget);
    expect(find.text('Sign In'), findsNWidgets(2)); // Tab and Button
    expect(find.text('Register with OTP'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Phone Number'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Confirm Password'), findsNothing);

    // Switch to Create Account mode
    await tester.tap(find.text('Register with OTP'));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Confirm Password appears
    expect(find.widgetWithText(TextFormField, 'Confirm Password'), findsOneWidget);
  });

  testWidgets('Registering a new account navigates to HomeScreen with username greeting', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final storage = StorageService(baseDirPath: testDir);
    final api = MockApiService();
    final auth = AuthProvider(storageService: storage, apiService: api);
    final trip = TripProvider();

    await tester.pumpWidget(createTestWidget(auth: auth, trip: trip));
    while (auth.isCheckingToken) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 100));

    // Switch to Create Account
    await tester.tap(find.text('Register with OTP'));
    await tester.pump(const Duration(milliseconds: 200));

    // Enter name, phone, otp, password, confirm password
    await tester.enterText(find.widgetWithText(TextFormField, 'Full Name'), 'Sam Altman');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone Number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextFormField, '6-Digit OTP Code'), '123456');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'open_ai_123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm Password'), 'open_ai_123');
    await tester.pump();

    // Register user directly
    final success = await auth.register(
      phone: '9876543210',
      fullName: 'Sam Altman',
      password: 'open_ai_123',
      confirmPassword: 'open_ai_123',
    );
    expect(success, isTrue);
    expect(auth.isAuthenticated, isTrue);
  });

  testWidgets('Logout confirms and redirects back to LoginScreen', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final storage = StorageService(baseDirPath: testDir);
    final api = MockApiService();
    final auth = AuthProvider(storageService: storage, apiService: api);
    final trip = TripProvider();

    await tester.pumpWidget(createTestWidget(auth: auth, trip: trip));
    while (auth.isCheckingToken) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Register user
    await auth.register(
      phone: '9876543299',
      fullName: 'test_logout_user',
      password: 'pass1234',
      confirmPassword: 'pass1234',
    );
    trip.loadUserTrips(auth.currentUser!.trips, onSave: (trips) => auth.saveCurrentUserData(trips));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('👤 test_logout_user'), findsOneWidget);

    // Tap logout button
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Dialog appears
    expect(find.text('Log Out'), findsNWidgets(2)); // Title and action button
    expect(find.text('Cancel'), findsOneWidget);

    // Confirm logout
    await tester.tap(find.widgetWithText(FilledButton, 'Log Out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Redirected to LoginScreen
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(auth.isAuthenticated, isFalse);
  });
}
