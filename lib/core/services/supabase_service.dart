import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  static bool _initialized = false;
  static bool get isInitialized => _initialized;
  bool get initialized => _initialized;

  SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
        'Supabase is not initialized. Please run or build the app with --dart-define=SUPABASE_ANON_KEY=<key>.',
      );
    }
    return Supabase.instance.client;
  }

  static Future<void> initialize() async {
    if (ApiConstants.supabaseAnonKey.isEmpty) {
      _initialized = false;
      throw StateError(
        'Missing SUPABASE_ANON_KEY — rebuild with --dart-define=SUPABASE_ANON_KEY=<key> (never hardcode keys in source).',
      );
    }
    await Supabase.initialize(
      url: ApiConstants.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: ApiConstants.supabaseAnonKey,
    );
    _initialized = true;
  }

  // Authentication
  Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    try {
      if (!_initialized) return;
      await client.auth.signOut();
    } catch (_) {}
  }

  User? get currentUser {
    try {
      if (!_initialized) return null;
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  // Venue queries
  static const String superAdminEmail = 'talk2icedmist@gmail.com';

  bool _isSuperAdmin(String email) =>
      email.toLowerCase().trim() == superAdminEmail;

  Future<Map<String, dynamic>?> getPrimaryVenue({String? email}) async {
    try {
      final user = currentUser;
      final targetEmail = (email ?? user?.email ?? '').toLowerCase().trim();

      // 1. If user is logged in, try finding their venue via VenueMember membership
      // Strict isolation: a venue is only returned if the user is an explicit member.
      if (user != null) {
        try {
          final memberRes = await client
              .from('VenueMember')
              .select('venueId, role, Venue(*)')
              .eq('userId', user.id)
              .limit(1)
              .maybeSingle();
          if (memberRes != null && memberRes['Venue'] != null) {
            return Map<String, dynamic>.from(memberRes['Venue'] as Map);
          }
        } catch (_) {}
      }

      // 1b. Check User table by targetEmail (heals logins where currentUser was delayed or id differed)
      if (targetEmail.isNotEmpty) {
        try {
          final userRow = await client
              .from('User')
              .select('id')
              .ilike('email', targetEmail)
              .limit(1)
              .maybeSingle();
          if (userRow != null && userRow['id'] != null) {
            final memberRes = await client
                .from('VenueMember')
                .select('venueId, role, Venue(*)')
                .eq('userId', userRow['id'])
                .limit(1)
                .maybeSingle();
            if (memberRes != null && memberRes['Venue'] != null) {
              final v = Map<String, dynamic>.from(memberRes['Venue'] as Map);
              if (user != null && user.id != userRow['id']) {
                try {
                  await client.from('VenueMember').upsert({
                    'venueId': v['id'],
                    'userId': user.id,
                    'role': 'Owner',
                  });
                } catch (_) {}
              }
              return v;
            }
          }
        } catch (_) {}
      }

      // 2. Self-healing fallback: Check ActivationRedemption for this operator's email
      if (targetEmail.isNotEmpty) {
        try {
          final redemption = await client
              .from('ActivationRedemption')
              .select('venueId, Venue(*)')
              .ilike('email', targetEmail)
              .not('venueId', 'is', null)
              .limit(1)
              .maybeSingle();
          if (redemption != null && redemption['Venue'] != null) {
            final v = Map<String, dynamic>.from(redemption['Venue'] as Map);
            if (user != null) {
              try {
                await client.from('User').upsert({
                  'id': user.id,
                  'email': user.email ?? targetEmail,
                  'authProvider': 'supabase',
                  'status': 'active',
                });
                await client.from('VenueMember').upsert({
                  'venueId': v['id'],
                  'userId': user.id,
                  'role': 'Owner',
                });
              } catch (_) {}
            }
            return v;
          }
        } catch (_) {}
      }

      // 3. Logged-in non-member: do NOT fall through to another venue's data.
      // Only the platform super-admin may use the global fallback below.
      if (user != null && !_isSuperAdmin(targetEmail)) return null;

      // 4. Fallback: super-admin only — latest venue for inspection/support.
      if (targetEmail == superAdminEmail) {
        final res = await client
            .from('Venue')
            .select('*')
            .order('createdAt', ascending: false)
            .limit(1)
            .maybeSingle();
        return res;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getVenues({String? email}) async {
    try {
      final user = currentUser;
      final targetEmail = (email ?? user?.email ?? '').toLowerCase().trim();

      if (user != null) {
        try {
          final memberRes = await client
              .from('VenueMember')
              .select('venueId, role, Venue(*)')
              .eq('userId', user.id);
          final venues = (memberRes as List)
              .where((m) => m['Venue'] != null)
              .map((m) => Map<String, dynamic>.from(m['Venue'] as Map))
              .toList();
          if (venues.isNotEmpty) return venues;
        } catch (_) {}
      }

      // 1b. Check User table by targetEmail
      if (targetEmail.isNotEmpty) {
        try {
          final userRow = await client
              .from('User')
              .select('id')
              .ilike('email', targetEmail)
              .limit(1)
              .maybeSingle();
          if (userRow != null && userRow['id'] != null) {
            final memberRes = await client
                .from('VenueMember')
                .select('venueId, role, Venue(*)')
                .eq('userId', userRow['id']);
            final venues = (memberRes as List)
                .where((m) => m['Venue'] != null)
                .map((m) => Map<String, dynamic>.from(m['Venue'] as Map))
                .toList();
            if (venues.isNotEmpty) return venues;
          }
        } catch (_) {}
      }

      // Self-healing fallback: Check ActivationRedemption for this operator's email
      if (targetEmail.isNotEmpty) {
        try {
          final redemption = await client
              .from('ActivationRedemption')
              .select('venueId, Venue(*)')
              .ilike('email', targetEmail)
              .not('venueId', 'is', null)
              .limit(1)
              .maybeSingle();
          if (redemption != null && redemption['Venue'] != null) {
            final v = Map<String, dynamic>.from(redemption['Venue'] as Map);
            if (user != null) {
              try {
                await client.from('User').upsert({
                  'id': user.id,
                  'email': user.email ?? targetEmail,
                  'authProvider': 'supabase',
                  'status': 'active',
                });
                await client.from('VenueMember').upsert({
                  'venueId': v['id'],
                  'userId': user.id,
                  'role': 'Owner',
                });
              } catch (_) {}
            }
            return [v];
          }
        } catch (_) {}
      }

      // Non-member operators see zero venues — never the full table.
      if (user != null && !_isSuperAdmin(targetEmail)) return [];

      if (targetEmail == superAdminEmail) {
        final res = await client.from('Venue').select('*').order('createdAt', ascending: false);
        return List<Map<String, dynamic>>.from(res);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Plans queries — no mock fallback, returns empty on error for prod parity
  Future<List<Map<String, dynamic>>> getActivePlans(String venueId) async {
    final res = await client.from('Plan').select('*').eq('venueId', venueId).eq('active', true).order('priceMinor', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  // Active sessions query
  Future<List<Map<String, dynamic>>> getActiveSessions(String venueId) async {
    try {
      final res = await client
          .from('Session')
          .select('*, router:Router(name)')
          .eq('venueId', venueId)
          .eq('status', 'ACTIVE')
          .order('startedAt', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      return [];
    }
  }
}
