import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: ApiConstants.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: ApiConstants.supabaseAnonKey,
    );
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
      await client.auth.signOut();
    } catch (_) {}
  }

  User? get currentUser {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  // Venue queries
  Future<Map<String, dynamic>?> getPrimaryVenue({String? email}) async {
    try {
      final user = currentUser;
      final targetEmail = (email ?? user?.email ?? '').toLowerCase().trim();

      // 1. If user is logged in, try finding their venue via VenueMember membership
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

      // 2. Only platform super admin is allowed to inspect the primary venue fallback
      if (targetEmail == 'talk2icedmist@gmail.com') {
        final res = await client
            .from('Venue')
            .select('*')
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

      if (targetEmail == 'talk2icedmist@gmail.com') {
        final res = await client.from('Venue').select('*');
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
