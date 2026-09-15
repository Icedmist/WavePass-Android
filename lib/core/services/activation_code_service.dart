import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';

/// Service responsible for managing venue activation codes.
/// Each account requires an authorized activation code before configuring a venue.
/// Each activation code is strictly limited to 1 venue.
class ActivationCodeService {
  ActivationCodeService._();
  static final ActivationCodeService instance = ActivationCodeService._();

  static const String _keyActivationPrefix = 'wavepass_venue_activated_';
  static const String _keyActivatedCodePrefix = 'wavepass_venue_activation_code_';

  static const String _superAdminEmail = 'talk2icedmist@gmail.com';

  /// Checks whether an account is activated and permitted to configure venues.
  /// System administrator (talk2icedmist@gmail.com) is permanently activated.
  Future<bool> isAccountActivated([String? email]) async {
    final targetEmail = (email ?? await _getCurrentUserEmail()).toLowerCase().trim();
    if (targetEmail.isEmpty) return false;

    // Super admin bypass
    if (targetEmail == _superAdminEmail) return true;

    // 1. Check local cache
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool('$_keyActivationPrefix$targetEmail');
    if (cached == true) return true;

    // 2. Check cloud backend
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/admin/activation-codes/check/${Uri.encodeComponent(targetEmail)}'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['activated'] == true) {
          await prefs.setBool('$_keyActivationPrefix$targetEmail', true);
          if (data['code'] != null) {
            await prefs.setString('$_keyActivatedCodePrefix$targetEmail', data['code'].toString());
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('[ActivationCodeService] Cloud check error: $e');
    }

    return false;
  }

  /// Gets the redeemed activation code for this account, if any.
  Future<String?> getActivatedCode([String? email]) async {
    final targetEmail = (email ?? await _getCurrentUserEmail()).toLowerCase().trim();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_keyActivatedCodePrefix$targetEmail');
  }

  /// Redeems an activation code to activate a venue for an account.
  /// Validates with cloud backend and persists locally.
  Future<Map<String, dynamic>> redeemActivationCode({
    required String code,
    String? email,
    String? venueId,
  }) async {
    final targetEmail = (email ?? await _getCurrentUserEmail()).toLowerCase().trim();
    final cleanCode = code.toUpperCase().trim();

    if (cleanCode.isEmpty) {
      return {'ok': false, 'error': 'Activation code is required'};
    }
    if (targetEmail.isEmpty) {
      return {'ok': false, 'error': 'User email is required for activation'};
    }

    try {
      final res = await http
          .post(
            Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/admin/activation-codes/redeem'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'code': cleanCode,
              'email': targetEmail,
              'venueId': venueId,
            }),
          )
          .timeout(const Duration(seconds: 8));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 200 && res.statusCode < 300 && data['ok'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('$_keyActivationPrefix$targetEmail', true);
        await prefs.setString('$_keyActivatedCodePrefix$targetEmail', cleanCode);
        return {'ok': true, 'message': data['message'] ?? 'Venue activated successfully!'};
      } else {
        return {'ok': false, 'error': data['error'] ?? data['message'] ?? 'Invalid or unauthorized activation code'};
      }
    } catch (e) {
      // Local fallback in case backend is in local standalone mode:
      // If code matches standard valid format WP-ACT-XXXX-XXXX, allow local activation
      if (cleanCode.startsWith('WP-ACT-') && cleanCode.length >= 14) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('$_keyActivationPrefix$targetEmail', true);
        await prefs.setString('$_keyActivatedCodePrefix$targetEmail', cleanCode);
        return {
          'ok': true,
          'message': 'Venue activated in standalone offline mode.',
        };
      }
      return {'ok': false, 'error': 'Failed to connect to activation server: $e'};
    }
  }

  Future<String> _getCurrentUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sb-user-email') ?? '';
  }
}
