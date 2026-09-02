import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: ApiConstants.supabaseUrl,
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
    await client.auth.signOut();
  }

  User? get currentUser => client.auth.currentUser;

  // Venue queries
  Future<Map<String, dynamic>?> getPrimaryVenue() async {
    try {
      final res = await client
          .from('Venue')
          .select('*')
          .limit(1)
          .maybeSingle();
      return res;
    } catch (e) {
      return null;
    }
  }

  // Plans queries
  Future<List<Map<String, dynamic>>> getActivePlans(String venueId) async {
    try {
      final res = await client
          .from('Plan')
          .select('*')
          .eq('venueId', venueId)
          .eq('active', true)
          .order('priceMinor', ascending: true);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      return [
        {
          'id': 'plan_1hr',
          'name': '1 Hour Quick Pass',
          'priceMinor': 20000,
          'durationSeconds': 3600,
          'rateLimit': 'profile_1h',
        },
        {
          'id': 'plan_12hr',
          'name': '12 Hour Work Pass',
          'priceMinor': 80000,
          'durationSeconds': 43200,
          'rateLimit': 'profile_12h',
        },
        {
          'id': 'plan_24hr',
          'name': '24 Hour All-Day Pass',
          'priceMinor': 150000,
          'durationSeconds': 86400,
          'rateLimit': 'profile_24h',
        },
      ];
    }
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
