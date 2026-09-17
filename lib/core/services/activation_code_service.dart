import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'supabase_service.dart';

/// Service responsible for managing venue activation codes.
///
/// Codes are issued by the system admin to specific venues, each carrying its
/// own expiry date (monthly rotation). The cloud backend is the source of
/// truth: when a code expires, activation is denied and the app must pause
/// all activity until a fresh code is redeemed.
///
/// Local cache (SharedPreferences) only carries an *unexpired* activation
/// across offline gaps — any positive denial from the backend clears it.
class ActivationCodeService {
  ActivationCodeService._();
  static final ActivationCodeService instance = ActivationCodeService._();

  static const String keyGlobalActivated = 'wavepass_venue_activated_globally';
  static const String keyGlobalExpiry = 'wavepass_venue_activated_expiry_globally';
  static const String keyLastExpired = 'wavepass_last_activation_expired_on';
  static const String _keyActivationPrefix = 'wavepass_venue_activated_';
  static const String _keyActivatedCodePrefix = 'wavepass_venue_activation_code_';
  static const String _keyExpiryPrefix = 'wavepass_venue_activated_expiry_';

  static const String _superAdminEmail = 'talk2icedmist@gmail.com';

  /// Synchronous cached status for router guards. Warmed at startup via
  /// [warmCache]; refreshed by [isAccountActivated] and [reverifyActivations].
  bool isActivatedCached = false;

  Future<void> warmCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isExpired(prefs.getString(keyGlobalExpiry))) {
        await clearCache();
        isActivatedCached = false;
        return;
      }
      isActivatedCached = prefs.getBool(keyGlobalActivated) == true;
    } catch (_) {
      isActivatedCached = false;
    }
  }

  bool _isExpired(String? expiryIso) {
    if (expiryIso == null || expiryIso.isEmpty) return false;
    try {
      return DateTime.parse(expiryIso).isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Future<void> _noteExpiryBeforeClear(SharedPreferences prefs, String? targetEmail) async {
    final candidates = <String?>[
      if (targetEmail != null && targetEmail.isNotEmpty) prefs.getString('$_keyExpiryPrefix$targetEmail'),
      prefs.getString(keyGlobalExpiry),
    ];
    for (final c in candidates) {
      if (c != null && c.isNotEmpty) {
        await prefs.setString(keyLastExpired, c);
        return;
      }
    }
  }

  Future<void> _storeActivation(SharedPreferences prefs, String targetEmail, String? code, String? expiresAt) async {
    await prefs.setBool(keyGlobalActivated, true);
    if (targetEmail.isNotEmpty) {
      await prefs.setBool('$_keyActivationPrefix$targetEmail', true);
      if (code != null) {
        await prefs.setString('$_keyActivatedCodePrefix$targetEmail', code);
      } else {
        await prefs.remove('$_keyActivatedCodePrefix$targetEmail');
      }
      if (expiresAt != null) {
        await prefs.setString('$_keyExpiryPrefix$targetEmail', expiresAt);
      } else {
        await prefs.remove('$_keyExpiryPrefix$targetEmail');
      }
    }
    if (expiresAt != null) {
      await prefs.setString(keyGlobalExpiry, expiresAt);
    } else {
      await prefs.remove(keyGlobalExpiry);
    }
    isActivatedCached = true;
  }

  /// Checks whether an account is activated and permitted to configure venues.
  /// System administrator (talk2icedmist@gmail.com) is permanently activated.
  /// Set [forceRefresh] to bypass local cache (used for enforcement sweeps).
  Future<bool> isAccountActivated([String? email, bool forceRefresh = false]) async {
    final prefs = await SharedPreferences.getInstance();

    // Expired local activation locks the account even offline.
    if (_isExpired(prefs.getString(keyGlobalExpiry))) {
      await _noteExpiryBeforeClear(prefs, null);
      await clearCache();
      return false;
    }

    // If an explicit email was specified, check specifically for that account
    if (email != null && email.isNotEmpty) {
      final target = email.toLowerCase().trim();
      if (target == _superAdminEmail) return true;
      if (!forceRefresh) {
        if (_isExpired(prefs.getString('$_keyExpiryPrefix$target'))) {
          await _noteExpiryBeforeClear(prefs, target);
          await clearCache(target);
          return false;
        }
        final cached = prefs.getBool('$_keyActivationPrefix$target');
        if (cached == true) {
          isActivatedCached = true;
          return true;
        }
      }
      return _checkCloudActivation(target, prefs);
    }

    // 1. Check global device activation flag
    if (!forceRefresh && prefs.getBool(keyGlobalActivated) == true) {
      isActivatedCached = true;
      return true;
    }

    final targetEmail = (await _getCurrentUserEmail()).toLowerCase().trim();

    // Super admin bypass
    if (targetEmail == _superAdminEmail) {
      await prefs.setBool(keyGlobalActivated, true);
      isActivatedCached = true;
      return true;
    }

    // 2. Check local account cache
    if (!forceRefresh && targetEmail.isNotEmpty) {
      if (_isExpired(prefs.getString('$_keyExpiryPrefix$targetEmail'))) {
        await _noteExpiryBeforeClear(prefs, targetEmail);
        await clearCache(targetEmail);
        return false;
      }
      final cached = prefs.getBool('$_keyActivationPrefix$targetEmail');
      if (cached == true) {
        await prefs.setBool(keyGlobalActivated, true);
        isActivatedCached = true;
        return true;
      }
    }

    if (targetEmail.isEmpty) {
      isActivatedCached = false;
      return false;
    }

    // 3. Check cloud backend (source of truth, expiry-aware)
    return _checkCloudActivation(targetEmail, prefs);
  }

  /// Enforcement sweep: re-validates against the backend, clearing stale local
  /// activations (revoked, expired, or unknown). Returns the live status.
  Future<Map<String, dynamic>> reverifyActivations() async {
    final prefs = await SharedPreferences.getInstance();
    final targetEmail = (await _getCurrentUserEmail()).toLowerCase().trim();
    if (targetEmail.isEmpty || targetEmail == _superAdminEmail) {
      return {'activated': true, 'source': 'local'};
    }
    final ok = await _checkCloudActivation(targetEmail, prefs, force: true);
    return {'activated': ok, 'source': 'cloud'};
  }

  Future<bool> _checkCloudActivation(String targetEmail, SharedPreferences prefs, {bool force = false}) async {
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
          await _storeActivation(
            prefs,
            targetEmail,
            data['code']?.toString(),
            data['expiresAt']?.toString(),
          );
          return true;
        }
        // Positive denial (unknown, revoked, or expired) clears stale cache.
        if (data['expired'] == true && data['expiresAt'] != null) {
          await prefs.setString(keyLastExpired, data['expiresAt'].toString());
        } else {
          await _noteExpiryBeforeClear(prefs, targetEmail);
        }
        await clearCache(targetEmail);
        await prefs.remove(keyGlobalActivated);
        await prefs.remove(keyGlobalExpiry);
        isActivatedCached = false;
        return false;
      }
    } catch (e) {
      debugPrint('[ActivationCodeService] Cloud check error: $e');
    }
    // Backend unreachable: honor unexpired local cache, otherwise deny.
    if (_isExpired(prefs.getString('$_keyExpiryPrefix$targetEmail')) ||
        _isExpired(prefs.getString(keyGlobalExpiry))) {
      await _noteExpiryBeforeClear(prefs, targetEmail);
      await clearCache(targetEmail);
      return false;
    }
    final cached = prefs.getBool('$_keyActivationPrefix$targetEmail') == true ||
        prefs.getBool(keyGlobalActivated) == true;
    isActivatedCached = cached;
    return cached;
  }

  /// Clears cached activation keys for a specific email or global cache.
  /// The last-expired notice survives per-account clears (so the lockout
  /// screen can explain) but is wiped on full/global clear (logout).
  Future<void> clearCache([String? email]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email != null && email.isNotEmpty) {
        final targetEmail = email.toLowerCase().trim();
        await prefs.remove('$_keyActivationPrefix$targetEmail');
        await prefs.remove('$_keyActivatedCodePrefix$targetEmail');
        await prefs.remove('$_keyExpiryPrefix$targetEmail');
      } else {
        await prefs.remove(keyGlobalActivated);
        await prefs.remove(keyGlobalExpiry);
        await prefs.remove(keyLastExpired);
        final keys = prefs.getKeys();
        for (final key in keys) {
          if (key.startsWith(_keyActivationPrefix) ||
              key.startsWith(_keyActivatedCodePrefix) ||
              key.startsWith(_keyExpiryPrefix)) {
            await prefs.remove(key);
          }
        }
      }
      isActivatedCached = false;
    } catch (_) {}
  }

  /// Gets the redeemed activation code for this account, if any.
  Future<String?> getActivatedCode([String? email]) async {
    final targetEmail = (email ?? await _getCurrentUserEmail()).toLowerCase().trim();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_keyActivatedCodePrefix$targetEmail');
  }
  /// Gets the expiry date of the current activation, if any.
  Future<String?> getActivationExpiry([String? email]) async {
    final targetEmail = (email ?? await _getCurrentUserEmail()).toLowerCase().trim();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_keyExpiryPrefix$targetEmail') ?? prefs.getString(keyGlobalExpiry);
  }

  /// Date of the most recent expiry lockout, for the "code expired" notice.
  Future<String?> getLastExpired() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLastExpired);
  }

  /// Redeems an activation code to activate a venue for an account.
  /// Validates with cloud backend and persists locally with its expiry date.
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
        final codeObj = data['code'] as Map<String, dynamic>?;
        final expiresAt = codeObj?['expiresAt']?.toString();
        await _storeActivation(prefs, targetEmail, cleanCode, expiresAt);
        final msg = data['message']?.toString() ?? 'Venue activated successfully!';
        return {
          'ok': true,
          'message': expiresAt != null ? '$msg Active until $expiresAt.' : msg,
          'expiresAt': expiresAt,
        };
      } else {
        if (data['expired'] == true) {
          await clearCache(targetEmail.isNotEmpty ? targetEmail : null);
        }
        return {'ok': false, 'error': data['error'] ?? data['message'] ?? 'Invalid or unauthorized activation code'};
      }
    } catch (e) {
      return {'ok': false, 'error': 'Failed to connect to activation server: $e'};
    }
  }

  /// Sends a code request to the system admin for users without a code.
  Future<Map<String, dynamic>> requestActivationCode({
    required String email,
    String? name,
    String? phone,
    String? venueName,
    String? venueId,
    String? message,
  }) async {
    final targetEmail = email.toLowerCase().trim();
    if (targetEmail.isEmpty || !targetEmail.contains('@')) {
      return {'ok': false, 'error': 'A valid email address is required'};
    }
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/admin/activation-requests'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'email': targetEmail,
              if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
              if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
              if (venueName != null && venueName.trim().isNotEmpty) 'venueName': venueName.trim(),
              if (venueId != null && venueId.trim().isNotEmpty) 'venueId': venueId.trim(),
              if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 200 && res.statusCode < 300 && data['ok'] == true) {
        return {'ok': true, 'message': data['message']?.toString() ?? 'Request sent.', 'duplicate': data['duplicate'] == true};
      }
      return {'ok': false, 'error': data['error']?.toString() ?? 'Failed to send request'};
    } catch (e) {
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
