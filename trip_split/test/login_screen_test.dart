// test/login_screen_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_split/main.dart';
import 'package:trip_split/providers/auth_provider.dart';
import 'package:trip_split/providers/trip_provider.dart';
import 'package:trip_split/screens/login_screen.dart';
import 'package:trip_split/services/storage_service.dart';

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
    final auth = AuthProvider(storageService: storage);
    final trip = TripProvider();

    await tester.pumpWidget(createTestWidget(auth: auth, trip: trip));
    await tester.pumpAndSettle();

    // Verify Login Screen initial state
    expect(find.text('EquiTrip'), findsOneWidget);
    expect(find.byKey(const Key('tab_sign_in')), findsOneWidget);
    expect(find.byKey(const Key('tab_create_account')), findsOneWidget);
    expect(find.byKey(const Key('username_field')), findsOneWidget);
    expect(find.byKey(const Key('password_field')), findsOneWidget);
    expect(find.byKey(const Key('confirm_password_field')), findsNothing);

    // Switch to Create Account mode
    await tester.tap(find.byKey(const Key('tab_create_account')));
    await tester.pumpAndSettle();

    // Verify Confirm Password appears
    expect(find.byKey(const Key('confirm_password_field')), findsOneWidget);
  });

  testWidgets('Registering a new account navigates to HomeScreen with username greeting', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final storage = StorageService(baseDirPath: testDir);
    final auth = AuthProvider(storageService: storage);
    final trip = TripProvider();

    await tester.pumpWidget(createTestWidget(auth: auth, trip: trip));
    await tester.pumpAndSettle();

    // Switch to Create Account
    await tester.tap(find.byKey(const Key('tab_create_account')));
    await tester.pumpAndSettle();

    // Enter username, password, confirm password
    await tester.enterText(find.byKey(const Key('username_field')), 'sam_altman');
    await tester.enterText(find.byKey(const Key('password_field')), 'open_ai_123');
    await tester.enterText(find.byKey(const Key('confirm_password_field')), 'open_ai_123');
    await tester.pump();

    // Ensure button is visible and tap submit
    await tester.ensureVisible(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit_button')));

    // Allow async auth registration to complete without hanging on progress indicator animation
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Verify navigates to HomeScreen
    expect(find.text('👤 sam_altman'), findsOneWidget);
    expect(find.text('No trips yet'), findsOneWidget);

    // Verify user data was created
    final savedUser = await storage.loadUser('sam_altman');
    expect(savedUser, isNotNull);
    expect(savedUser!.username, 'sam_altman');
    expect(savedUser.password, 'open_ai_123');
  });

  testWidgets('Logout confirms and redirects back to LoginScreen', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final storage = StorageService(baseDirPath: testDir);
    final auth = AuthProvider(storageService: storage);
    final trip = TripProvider();

    await tester.pumpWidget(createTestWidget(auth: auth, trip: trip));
    await tester.pump();

    // Register user
    await auth.register('test_logout_user', 'pass1234');
    trip.loadUserTrips(auth.currentUser!.trips, onSave: (trips) => auth.saveCurrentUserData(trips));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('👤 test_logout_user'), findsOneWidget);

    // Tap logout button
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

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
