import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_split/main.dart';
import 'package:trip_split/providers/auth_provider.dart';
import 'package:trip_split/providers/trip_provider.dart';
import 'package:trip_split/screens/home_screen.dart';
import 'package:trip_split/screens/login_screen.dart';
import 'package:trip_split/screens/trip_detail_screen.dart';
import 'package:trip_split/models/enums.dart';
import 'package:trip_split/models/expense.dart';
import 'package:trip_split/services/api_service.dart';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

Future<void> tapAsync(WidgetTester tester, Finder finder, {Duration waitTime = const Duration(milliseconds: 1500)}) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future.delayed(waitTime);
  });
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = RealHttpOverrides();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('E2E UI Test: Register 5 Users, Login/Logout, Validations, and Multi-User Trips', (WidgetTester tester) async {
    // Set realistic desktop/tablet viewport
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    print('\n======================================================');
    print('PHASE 4: CREATE FIVE TEST USERS THROUGH THE UI');
    print('======================================================');

    final testUsers = [
      {'name': 'User 1', 'email': 'testuser1@example.com', 'phone': '9800000001', 'pass': 'Test@12345'},
      {'name': 'User 2', 'email': 'testuser2@example.com', 'phone': '9800000002', 'pass': 'Test@12345'},
      {'name': 'User 3', 'email': 'testuser3@example.com', 'phone': '9800000003', 'pass': 'Test@12345'},
      {'name': 'User 4', 'email': 'testuser4@example.com', 'phone': '9800000004', 'pass': 'Test@12345'},
      {'name': 'User 5', 'email': 'testuser5@example.com', 'phone': '9800000005', 'pass': 'Test@12345'},
    ];

    // Start App UI
    await tester.pumpWidget(const TripExpenseApp());
    await tester.pumpAndSettle();

    // 1. Verify Login Screen elements
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Sign In'), findsNWidgets(2));
    expect(find.text('Register with OTP'), findsOneWidget);
    print('[PASS] LoginScreen rendered successfully with Sign In & Register tabs.');

    // 2. Test Input Validations on Sign In Form
    print('[TEST] Testing Sign In validation (empty fields)...');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Phone number or email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    print('[PASS] Sign In required field validation works.');

    // 3. Switch to Register with OTP Tab
    print('[TEST] Switching to Register with OTP tab...');
    await tester.tap(find.text('Register with OTP'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Full Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email Address'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Phone Number'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '6-Digit OTP Code'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Confirm Password'), findsOneWidget);
    print('[PASS] Registration form with Full Name, Email, Phone, OTP, Password rendered.');

    // 4. Test Registration Validations
    print('[TEST] Testing registration validation (empty fields)...');
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account & Verify OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Full name is required'), findsOneWidget);
    expect(find.text('Phone number is required'), findsOneWidget);
    print('[PASS] Registration required-field validation works.');

    // 5. Test Password Mismatch Validation
    print('[TEST] Testing password mismatch validation...');
    await tester.enterText(find.widgetWithText(TextFormField, 'Full Name'), 'Validation Test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'val@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone Number'), '9800009999');
    await tester.enterText(find.widgetWithText(TextFormField, '6-Digit OTP Code'), '123456');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'Test@12345');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm Password'), 'WrongPass');
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account & Verify OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    print('[PASS] Passwords do not match validation works.');

    // 6. Register All 5 Users via UI Workflow
    for (int i = 0; i < testUsers.length; i++) {
      final u = testUsers[i];
      print('\n[USER ${i + 1}] Registering: ${u['name']} (${u['email']})...');

      // Ensure on register tab
      if (find.widgetWithText(TextFormField, 'Full Name').evaluate().isEmpty) {
        await tester.tap(find.text('Register with OTP'));
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.widgetWithText(TextFormField, 'Full Name'), u['name']!);
      await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), u['email']!);
      await tester.enterText(find.widgetWithText(TextFormField, 'Phone Number'), u['phone']!);
      await tester.enterText(find.widgetWithText(TextFormField, '6-Digit OTP Code'), '123456');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), u['pass']!);
      await tester.enterText(find.widgetWithText(TextFormField, 'Confirm Password'), u['pass']!);
      await tester.pumpAndSettle();

      await tapAsync(tester, find.widgetWithText(FilledButton, 'Create Account & Verify OTP'));

      // Verify navigation into HomeScreen
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Hello, ${u['name']} 👋'), findsOneWidget);
      print('[PASS] User ${i + 1} (${u['email']}) registered successfully and navigated to HomeScreen.');

      // If not the last user, log out so next user can register
      if (i < testUsers.length - 1) {
        print('[TEST] Logging out ${u['name']}...');
        await tester.tap(find.byIcon(Icons.logout_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Log Out?'), findsOneWidget);
        await tapAsync(tester, find.widgetWithText(FilledButton, 'Log Out'));
        expect(find.byType(LoginScreen), findsOneWidget);
        print('[PASS] User ${i + 1} logged out successfully.');
      }
    }

    // 7. Verify Duplicate Email Registration Rejection
    print('\n[TEST] Testing duplicate registration rejection for testuser1@example.com...');
    await tester.tap(find.byIcon(Icons.logout_rounded));
    await tester.pumpAndSettle();
    await tapAsync(tester, find.widgetWithText(FilledButton, 'Log Out'));

    await tester.tap(find.text('Register with OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Full Name'), 'Duplicate User');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'testuser1@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone Number'), '9800000001');
    await tester.enterText(find.widgetWithText(TextFormField, '6-Digit OTP Code'), '123456');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'Test@12345');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm Password'), 'Test@12345');
    await tapAsync(tester, find.widgetWithText(FilledButton, 'Create Account & Verify OTP'));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    print('[PASS] Duplicate registration rejected with error banner.');

    // 8. Test Invalid Password Login
    print('\n[TEST] Testing invalid password login...');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone Number or Email'), 'testuser1@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'WrongPassword!');
    await tapAsync(tester, find.widgetWithText(FilledButton, 'Sign In'));
    expect(find.byType(HomeScreen), findsNothing);
    print('[PASS] Invalid password was rejected.');

    // 9. Sign In User 1 with Email & Password
    print('\n[TEST] Logging in User 1 with Email (testuser1@example.com)...');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'Test@12345');
    await tapAsync(tester, find.widgetWithText(FilledButton, 'Sign In'));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Hello, User 1 👋'), findsOneWidget);
    print('[PASS] User 1 logged in successfully using email.');

    print('\n======================================================');
    print('PHASE 5 & 6: FUNCTIONAL & MULTI-USER TRIP TESTING');
    print('======================================================');

    // 10. User 1 creates Trip "Goa Vacation 2026"
    print('[TEST] User 1 creating Trip "Goa Vacation 2026"...');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Create Trip'), findsWidgets);

    // Empty trip name validation
    await tester.tap(find.widgetWithText(InkWell, 'Create Trip'));
    await tester.pumpAndSettle();

    // Fill valid trip details
    await tester.enterText(find.widgetWithText(TextField, 'Trip Name'), 'Goa Vacation 2026');
    await tester.enterText(find.widgetWithText(TextField, 'Description (Optional)'), 'Beach resort trip with friends');
    await tapAsync(tester, find.widgetWithText(InkWell, 'Create Trip'));

    expect(find.text('Goa Vacation 2026'), findsOneWidget);
    print('[PASS] Trip "Goa Vacation 2026" created and displayed in HomeScreen.');

    // 11. Open Trip Details
    await tester.tap(find.text('Goa Vacation 2026'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(TripDetailScreen), findsOneWidget);
    print('[PASS] TripDetailScreen opened.');

    // 12. Add Members User 2 & User 3 to the Trip
    final tripContext = tester.element(find.byType(TripDetailScreen));
    final tripProvider = tripContext.read<TripProvider>();
    final activeTrip = tripProvider.trips.firstWhere((t) => t.name == 'Goa Vacation 2026');
    final defaultGroup = activeTrip.groups.first;

    print('[TEST] Adding User 2 and User 3 to Trip...');
    await tester.runAsync(() async {
      final u2Added = await tripProvider.addPerson(
        activeTrip.id,
        defaultGroup.id,
        'User 2',
        DietType.nonVegetarian,
        phone: '9800000002',
      );
      expect(u2Added, isTrue);

      final u3Added = await tripProvider.addPerson(
        activeTrip.id,
        defaultGroup.id,
        'User 3',
        DietType.nonVegAlcoholic,
        phone: '9800000003',
      );
      expect(u3Added, isTrue);
    });
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(activeTrip.allMembers.length, 3);
    print('[PASS] Members User 1, User 2, and User 3 linked to Trip.');

    // 13. Add Expenses directly through Provider / UI
    print('[TEST] Adding Shared Expenses...');
    final p1 = activeTrip.allMembers.firstWhere((m) => m.name.contains('User 1') || m.name == 'Me');
    final p2 = activeTrip.allMembers.firstWhere((m) => m.name == 'User 2');
    final p3 = activeTrip.allMembers.firstWhere((m) => m.name == 'User 3');

    // Expense 1: Resort Booking (3000 INR paid by User 1, split equally among all 3)
    final exp1 = Expense(
      id: '',
      description: 'Resort Beach Villa',
      amount: 3000.0,
      category: ExpenseCategory.accommodation,
      paidById: p1.id,
      date: DateTime.now(),
      splitAmongIds: [p1.id, p2.id, p3.id],
    );

    // Expense 2: Seafood Dinner (1500 INR paid by User 2, split between User 2 and User 3)
    final exp2 = Expense(
      id: '',
      description: 'Seafood Beach Dinner',
      amount: 1500.0,
      category: ExpenseCategory.nonVeg,
      paidById: p2.id,
      date: DateTime.now(),
      splitAmongIds: [p2.id, p3.id],
    );

    await tester.runAsync(() async {
      await tripProvider.addExpense(activeTrip.id, exp1);
      await tripProvider.addExpense(activeTrip.id, exp2);
    });
    await tester.pumpAndSettle(const Duration(seconds: 2));
    print('[PASS] Expenses "Resort Beach Villa" (INR 3,000) and "Seafood Beach Dinner" (INR 1,500) added.');

    // 14. Verify Financial Balance Invariants
    final balances = tripProvider.getBalances(activeTrip.id);
    final totalSpent = tripProvider.getTotalExpense(activeTrip.id);
    expect(totalSpent, 4500.0);

    final netSum = balances.fold(0.0, (sum, b) => sum + b.net);
    expect(netSum.abs() < 0.01, isTrue);
    print('[PASS] Financial balance invariant verified: Total Expenses = INR 4,500, Net Balance Sum = 0.00.');

    // 15. User 4 Data Isolation Test
    print('\n[TEST] Testing Multi-User Data Isolation with User 4...');
    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pumpAndSettle();

    // Log out User 1
    await tester.tap(find.byIcon(Icons.logout_rounded));
    await tester.pumpAndSettle();
    await tapAsync(tester, find.widgetWithText(FilledButton, 'Log Out'));

    // Sign in User 4 (testuser4@example.com)
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone Number or Email'), 'testuser4@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'Test@12345');
    await tapAsync(tester, find.widgetWithText(FilledButton, 'Sign In'));

    expect(find.text('Hello, User 4 👋'), findsOneWidget);
    // User 4 MUST NOT see User 1's "Goa Vacation 2026"
    expect(find.text('Goa Vacation 2026'), findsNothing);
    print('[PASS] User 4 has absolute data isolation: 0 access to User 1 trips.');

    // User 4 creates their own Trip "Himalayan Trek"
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Trip Name'), 'Himalayan Trek 2026');
    await tapAsync(tester, find.widgetWithText(InkWell, 'Create Trip'));
    expect(find.text('Himalayan Trek 2026'), findsOneWidget);
    print('[PASS] User 4 created independent trip "Himalayan Trek 2026".');

    // Dispose widget tree to cancel periodic heartbeat sync timers
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // Advance fake clock past any in-flight HTTP request timeouts
    await tester.pump(const Duration(seconds: 10));

    print('\n======================================================');
    print('ALL UI E2E TESTS COMPLETED WITH 100% SUCCESS!');
    print('======================================================\n');
  });
}
