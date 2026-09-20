import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import 'venue_state_service.dart';
import 'voucher_history_service.dart';
import 'router_discovery_service.dart';
import 'activation_code_service.dart';

/// Manages user session lifecycle, enforcing a strict 48-hour (2-day)
/// session expiration policy across the app.
class SessionService {
  static final SessionService instance = SessionService._internal();
  SessionService._internal();

  /// Maximum session duration: 48 hours (2 days)
  static const int sessionExpiryHours = 48;
  static const String keySessionLoginTime = 'wavepass_session_login_time';
  static const String keySessionExpiredNotice = 'wavepass_session_expired_notice';

  bool _isExpiredCached = false;
  bool get isExpiredCached => _isExpiredCached;

  /// Records fresh login timestamp when a user signs in.
  Future<void> recordLogin(String email) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _isExpiredCached = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(keySessionLoginTime, nowMs);
      await prefs.remove(keySessionExpiredNotice);
      await prefs.setString('sb-user-email', email);
    } catch (e) {
      debugPrint('SessionService: Error recording login: $e');
    }
  }

  /// Checks if current session has exceeded 48 hours.
  Future<bool> isSessionExpired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginMs = prefs.getInt(keySessionLoginTime);
      if (loginMs == null) {
        // If there's an active Supabase user or admin token but no recorded login time yet,
        // seed current login time to prevent immediate eviction on migration, but start the 48h clock.
        final user = SupabaseService.instance.currentUser;
        final adminToken = prefs.getString('admin_token');
        if (user != null || (adminToken != null && adminToken.isNotEmpty)) {
          final now = DateTime.now().millisecondsSinceEpoch;
          await prefs.setInt(keySessionLoginTime, now);
          _isExpiredCached = false;
          return false;
        }
        _isExpiredCached = true;
        return true;
      }

      final loginTime = DateTime.fromMillisecondsSinceEpoch(loginMs);
      final difference = DateTime.now().difference(loginTime);
      final expired = difference.inHours >= sessionExpiryHours;
      _isExpiredCached = expired;
      return expired;
    } catch (e) {
      debugPrint('SessionService: Error checking expiry: $e');
      return false;
    }
  }

  /// Returns the remaining duration until session expiry, or null if unauthenticated.
  Future<Duration?> getRemainingDuration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginMs = prefs.getInt(keySessionLoginTime);
      if (loginMs == null) return null;

      final loginTime = DateTime.fromMillisecondsSinceEpoch(loginMs);
      final elapsed = DateTime.now().difference(loginTime);
      final remaining = Duration(hours: sessionExpiryHours) - elapsed;
      return remaining.isNegative ? Duration.zero : remaining;
    } catch (_) {
      return null;
    }
  }

  /// Checks and automatically terminates expired sessions.
  /// Returns true if session was expired and cleared.
  Future<bool> checkAndEnforceExpiry() async {
    final expired = await isSessionExpired();
    if (expired) {
      await clearSession(markedExpired: true);
      return true;
    }
    return false;
  }

  /// Wipes active session data from memory & SharedPreferences.
  Future<void> clearSession({bool markedExpired = false}) async {
    _isExpiredCached = true;
    try {
      await SupabaseService.instance.signOut();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keySessionLoginTime);
      await prefs.remove('admin_token');
      await prefs.remove('wavepass_voucher_history_v1');
      await prefs.remove(RouterDiscoveryService.keyRouterLocalIp);
      await prefs.remove(RouterDiscoveryService.keyRouterTunnelEndpoint);
      await prefs.remove(RouterDiscoveryService.keyRouterUsername);
      await prefs.remove(RouterDiscoveryService.keyRouterPassword);
      if (markedExpired) {
        await prefs.setBool(keySessionExpiredNotice, true);
      }
      await VenueStateService.instance.clearVenue();
      await ActivationCodeService.instance.clearCache();
      await VoucherHistoryService.instance.clearCache();
    } catch (e) {
      debugPrint('SessionService: Error clearing session: $e');
    }
  }

  /// Consumes and returns whether a 48-hour expiration banner should be displayed.
  Future<bool> consumeExpiryNotice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notice = prefs.getBool(keySessionExpiredNotice) ?? false;
      if (notice) {
        await prefs.remove(keySessionExpiredNotice);
      }
      return notice;
    } catch (_) {
      return false;
    }
  }
}
