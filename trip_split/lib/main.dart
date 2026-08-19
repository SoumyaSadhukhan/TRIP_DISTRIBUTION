// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/trip_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const TripExpenseApp());
}

class TripExpenseApp extends StatelessWidget {
  const TripExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
      ],
      child: MaterialApp(
        title: 'EquiTrip',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamilyFallback: const ['Roboto', 'sans-serif'],
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4F46E5),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFF4F46E5),
            secondary: const Color(0xFF7C3AED),
            tertiary: const Color(0xFF06B6D4),
            surface: const Color(0xFFF8F9FF),
          ),
          scaffoldBackgroundColor: const Color(0xFFF8F9FF),
          useMaterial3: true,
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.grey.shade100, width: 1),
            ),
            shadowColor: const Color(0xFF4F46E5).withValues(alpha: 0.08),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
            ),
            labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          chipTheme: ChipThemeData(
            backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.08),
            labelStyle: const TextStyle(
              color: Color(0xFF4F46E5),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            side: BorderSide.none,
          ),
          tabBarTheme: const TabBarThemeData(
            labelColor: Color(0xFF4F46E5),
            unselectedLabelColor: Color(0xFF9CA3AF),
            indicatorColor: Color(0xFF4F46E5),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            shape: StadiumBorder(),
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isAuthenticated) {
      return const HomeScreen();
    }
    return const LoginScreen();
  }
}