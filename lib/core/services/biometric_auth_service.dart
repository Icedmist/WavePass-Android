import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides biometric authentication (Fingerprint, Face ID, and device credentials)
/// for secure, seamless 1-tap app unlock and user verification.
class BiometricAuthService {
  static final BiometricAuthService instance = BiometricAuthService._internal();
  BiometricAuthService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  static const String keyBiometricsEnabled = 'wavepass_biometrics_enabled';
  static const String keyBiometricsEmail = 'wavepass_biometrics_email';
  static const String keyBiometricsPayload = 'wavepass_biometrics_payload';

  /// Determines whether the physical device has hardware support for biometrics.
  Future<bool> isDeviceSupported() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported || canCheck;
    } catch (e) {
      debugPrint('BiometricAuthService: isDeviceSupported error: $e');
      return false;
    }
  }

  /// Lists available biometric sensors on the current device (fingerprint, face, etc.).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('BiometricAuthService: getAvailableBiometrics error: $e');
      return [];
    }
  }

  /// Returns a user-friendly label describing available biometrics (e.g. "Fingerprint & Face ID").
  Future<String> getBiometricTypeLabel() async {
    try {
      final biometrics = await getAvailableBiometrics();
      final hasFingerprint = biometrics.contains(BiometricType.fingerprint);
      final hasFace = biometrics.contains(BiometricType.face);

      if (hasFingerprint && hasFace) {
        return "Fingerprint & Face ID";
      } else if (hasFace) {
        return "Face ID";
      } else if (hasFingerprint) {
        return "Fingerprint";
      } else if (biometrics.isNotEmpty) {
        return "Biometric Authentication";
      }
      return "Fingerprint / Face ID";
    } catch (_) {
      return "Fingerprint / Face ID";
    }
  }

  /// Returns whether the user has toggled biometric unlock on for their account.
  Future<bool> isBiometricLoginEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keyBiometricsEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns the email associated with the biometric unlock enrollment.
  Future<String?> getEnrolledEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(keyBiometricsEmail);
    } catch (_) {
      return null;
    }
  }

  /// Prompts the native OS biometric dialog (Fingerprint or Face ID).
  Future<bool> authenticate({
    String reason = 'Scan fingerprint or Face ID to unlock WavePass',
  }) async {
    try {
      final isSupported = await isDeviceSupported();
      if (!isSupported) return false;

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('BiometricAuthService: authentication error: $e');
      return false;
    }
  }

  /// Saves or updates biometric enrollment credentials.
  Future<void> enrollBiometrics({
    required String email,
    required String password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyBiometricsEnabled, true);
      await prefs.setString(keyBiometricsEmail, email);
      // Obfuscate credentials for seamless auto-relogin
      final payload = base64Encode(utf8.encode(jsonEncode({
        'email': email,
        'pass': password,
        'ts': DateTime.now().millisecondsSinceEpoch,
      })));
      await prefs.setString(keyBiometricsPayload, payload);
    } catch (e) {
      debugPrint('BiometricAuthService: enrollment error: $e');
    }
  }

  /// Retrieves saved credentials for login after a successful biometric prompt.
  Future<Map<String, String>?> getEnrolledCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(keyBiometricsEnabled) ?? false;
      if (!enabled) return null;

      final payload = prefs.getString(keyBiometricsPayload);
      if (payload == null) return null;

      final decoded = jsonDecode(utf8.decode(base64Decode(payload))) as Map<String, dynamic>;
      final email = decoded['email']?.toString();
      final pass = decoded['pass']?.toString();

      if (email != null && pass != null) {
        return {'email': email, 'password': pass};
      }
      return null;
    } catch (e) {
      debugPrint('BiometricAuthService: getCredentials error: $e');
      return null;
    }
  }

  /// Disables biometric login and removes stored credentials.
  Future<void> disableBiometrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyBiometricsEnabled);
      await prefs.remove(keyBiometricsEmail);
      await prefs.remove(keyBiometricsPayload);
    } catch (e) {
      debugPrint('BiometricAuthService: disable error: $e');
    }
  }
}
