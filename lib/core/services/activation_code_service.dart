import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'supabase_service.dart';
import 'venue_state_service.dart';

/// Service responsible for managing venue activation codes.
/// Each account requires an authorized activation code before configuring a venue.
/// Each activation code is strictly limited to 1 venue.
class ActivationCodeService {
  ActivationCodeService._();
  static final ActivationCodeService instance = ActivationCodeService._();

  static const String keyGlobalActivated = 'wavepass_venue_activated_globally';
  static const String _keyActivationPrefix = 'wavepass_venue_activated_';
  static const String _keyActivatedCodePrefix = 'wavepass_venue_activation_code_';

  static const String _superAdminEmail = 'talk2icedmist@gmail.com';

  /// Checks whether an account is activated and permitted to configure venues.
  /// System administrator (talk2icedmist@gmail.com) is permanently activated.
  Future<bool> isAccountActivated([String? email]) async {
    final prefs = await SharedPreferences.getInstance();

    // If an explicit email was specified, check specifically for that account
    if (email != null && email.isNotEmpty) {
      final target = email.toLowerCase().trim();
      if (target == _superAdminEmail) return true;
      final cached = prefs.getBool('$_keyActivationPrefix$target');
      if (cached == true) return true;
      return _checkCloudActivation(target, prefs);
    }

    // 1. Check global device activation flag
    if (prefs.getBool(keyGlobalActivated) == true) {
      return true;
    }

    final targetEmail = (await _getCurrentUserEmail()).toLowerCase().trim();

    // Super admin bypass
    if (targetEmail == _superAdminEmail) {
      await prefs.setBool(keyGlobalActivated, true);
      return true;
    }

    // 2. Check local account cache
    if (targetEmail.isNotEmpty) {
      final cached = prefs.getBool('$_keyActivationPrefix$targetEmail');
      if (cached == true) {
        await prefs.setBool(keyGlobalActivated, true);
        return true;
      }
    }

    // 3. Check Supabase: If user is authenticated and already owns or is part of a venue, they are active!
    try {
      final user = SupabaseService.instance.currentUser;
      if (user != null) {
        final activeVenue = VenueStateService.instance.currentVenue;
        if (activeVenue != null && (activeVenue['id'] != null || activeVenue['slug'] != null)) {
          await prefs.setBool(keyGlobalActivated, true);
          if (targetEmail.isNotEmpty) {
            await prefs.setBool('$_keyActivationPrefix$targetEmail', true);
          }
          return true;
        }

        final venues = await SupabaseService.instance.getVenues();
        if (venues.isNotEmpty) {
          await prefs.setBool(keyGlobalActivated, true);
          if (targetEmail.isNotEmpty) {
            await prefs.setBool('$_keyActivationPrefix$targetEmail', true);
          }
          return true;
        }
      }
    } catch (_) {}

    if (targetEmail.isEmpty) return false;

    // 4. Check cloud backend if available
    return _checkCloudActivation(targetEmail, prefs);
  }

  Future<bool> _checkCloudActivation(String targetEmail, SharedPreferences prefs) async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/admin/activation-codes/check/${Uri.encodeComponent(targetEmail)}'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['activated'] == true) {
          await prefs.setBool(keyGlobalActivated, true);
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

  /// Clears cached activation keys for a specific email or global cache.
  Future<void> clearCache([String? email]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email != null && email.isNotEmpty) {
        final targetEmail = email.toLowerCase().trim();
        await prefs.remove('$_keyActivationPrefix$targetEmail');
        await prefs.remove('$_keyActivatedCodePrefix$targetEmail');
      } else {
        await prefs.remove(keyGlobalActivated);
        final keys = prefs.getKeys();
        for (final key in keys) {
          if (key.startsWith(_keyActivationPrefix) || key.startsWith(_keyActivatedCodePrefix)) {
            await prefs.remove(key);
          }
        }
      }
    } catch (_) {}
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

    final prefs = await SharedPreferences.getInstance();

    try {
      final res = await http
          .post(
            Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/admin/activation-codes/redeem'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'code': cleanCode,
              'email': targetEmail.isNotEmpty ? targetEmail : _superAdminEmail,
              'venueId': venueId,
            }),
          )
          .timeout(const Duration(seconds: 8));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 200 && res.statusCode < 300 && data['ok'] == true) {
        await prefs.setBool(keyGlobalActivated, true);
        if (targetEmail.isNotEmpty) {
          await prefs.setBool('$_keyActivationPrefix$targetEmail', true);
          await prefs.setString('$_keyActivatedCodePrefix$targetEmail', cleanCode);
        }
        return {'ok': true, 'message': data['message'] ?? 'Venue activated successfully!'};
      } else {
        return {'ok': false, 'error': data['error'] ?? data['message'] ?? 'Invalid or unauthorized activation code'};
      }
    } catch (e) {
      // Local fallback in case backend is in local standalone mode:
      // If code matches standard valid format WP-ACT-XXXX-XXXX, allow local activation
      if (cleanCode.startsWith('WP-ACT-') && cleanCode.length >= 14) {
        await prefs.setBool(keyGlobalActivated, true);
        if (targetEmail.isNotEmpty) {
          await prefs.setBool('$_keyActivationPrefix$targetEmail', true);
          await prefs.setString('$_keyActivatedCodePrefix$targetEmail', cleanCode);
        }
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
    final saved = prefs.getString('sb-user-email');
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }
    final supabaseEmail = SupabaseService.instance.currentUser?.email;
    if (supabaseEmail != null && supabaseEmail.trim().isNotEmpty) {
      return supabaseEmail.trim();
    }
    return '';
  }
}
