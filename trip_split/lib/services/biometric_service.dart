// lib/services/biometric_service.dart
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Checks if the device supports biometric or device lock authentication
  Future<bool> isBiometricAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      return canAuthenticateWithBiometrics || isDeviceSupported;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts the user with Fingerprint, Face ID, or Device PIN / Pattern lock
  Future<bool> authenticate({String reason = 'Authenticate to access your EquiTrip account'}) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        // Still attempt auth directly as some device vendors report false for isDeviceSupported
      }

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          useErrorDialogs: true,
          biometricOnly: false, // Allows phone lock PIN/Password/Pattern fallback
        ),
      );
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
