import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import 'wavepass_api.dart';

/// Centralized, reactive state store for venue identity and plans.
/// Ensures consistent data sharing across Home, Sell, Admin, Batch Vouchers,
/// and Account Center without stale IndexedStack state.
class VenueStateService {
  VenueStateService._internal();
  static final VenueStateService instance = VenueStateService._internal();

  static const String keyVenueId = 'wavepass_active_venue_id';
  static const String keyLegacyVenueId = 'venueId';
  static const String keyVenueName = 'wavepass_active_venue_name';
  static const String keyLegacyVenueName = 'venueName';
  static const String keyVenueSlug = 'wavepass_active_venue_slug';
  static const String keyVenueLogo = 'wavepass_active_venue_logo';

  final ValueNotifier<Map<String, dynamic>?> venueNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<List<Map<String, dynamic>>> plansNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(false);

  Map<String, dynamic>? get currentVenue => venueNotifier.value;
  String? get currentVenueId => venueNotifier.value?['id']?.toString();
  String get currentVenueName => venueNotifier.value?['name']?.toString() ?? 'WavePass Venue';
  String get currentVenueSlug => venueNotifier.value?['slug']?.toString() ?? 'venue';
  String? get currentLogoUrl => venueNotifier.value?['logoUrl']?.toString();
  List<Map<String, dynamic>> get currentPlans => plansNotifier.value;

  bool _initialized = false;

  /// Initialize state from SharedPreferences cache, then refresh from cloud.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedId = prefs.getString(keyVenueId) ?? prefs.getString(keyLegacyVenueId);
      final cachedName = prefs.getString(keyVenueName) ?? prefs.getString(keyLegacyVenueName);
      final cachedSlug = prefs.getString(keyVenueSlug);
      final cachedLogo = prefs.getString(keyVenueLogo);

      if (cachedId != null && cachedId.isNotEmpty) {
        venueNotifier.value = {
          'id': cachedId,
          'name': cachedName ?? 'WavePass Venue',
          'slug': cachedSlug ?? 'venue',
          'logoUrl': cachedLogo,
        };
      }
    } catch (_) {}

    await refreshVenue();
  }

  /// Refreshes the active venue from the backend API or Supabase.
  Future<Map<String, dynamic>?> refreshVenue({String? targetVenueId}) async {
    isLoadingNotifier.value = true;
    Map<String, dynamic>? venue;

    try {
      final prefs = await SharedPreferences.getInstance();
      final vid = targetVenueId ?? prefs.getString(keyVenueId) ?? prefs.getString(keyLegacyVenueId);

      // 1. Try finding by ID or default from backend
      if (vid != null && vid.isNotEmpty) {
        try {
          final res = await WavePassApi.instance.getVenueBySubdomain(vid);
          if (res['id'] != null) venue = res;
        } catch (_) {}
      }

      // 2. Try default venue from backend
      if (venue == null) {
        try {
          final res = await WavePassApi.instance.getDefaultVenue();
          if (res['id'] != null) venue = res;
        } catch (_) {}
      }

      // 3. Fallback to Supabase directly
      if (venue == null) {
        try {
          if (vid != null && vid.isNotEmpty) {
            final res = await SupabaseService.instance.client
                .from('Venue')
                .select('*')
                .eq('id', vid)
                .maybeSingle();
            if (res != null) venue = Map<String, dynamic>.from(res);
          }
          venue ??= await SupabaseService.instance.getPrimaryVenue();
        } catch (_) {}
      }

      if (venue != null) {
        venueNotifier.value = Map<String, dynamic>.from(venue);
        final id = venue['id']?.toString() ?? '';
        final name = venue['name']?.toString() ?? 'WavePass Venue';
        final slug = venue['slug']?.toString() ?? 'venue';
        final logo = venue['logoUrl']?.toString() ?? '';

        await prefs.setString(keyVenueId, id);
        await prefs.setString(keyLegacyVenueId, id);
        await prefs.setString(keyVenueName, name);
        await prefs.setString(keyLegacyVenueName, name);
        await prefs.setString(keyVenueSlug, slug);
        if (logo.isNotEmpty) await prefs.setString(keyVenueLogo, logo);

        await refreshPlans();
      }
    } catch (e) {
      debugPrint('[VenueStateService] refreshVenue error: $e');
    } finally {
      isLoadingNotifier.value = false;
    }
    return venue;
  }

  /// Refreshes plans for the currently active venue.
  Future<List<Map<String, dynamic>>> refreshPlans() async {
    final vid = currentVenueId;
    if (vid == null || vid.isEmpty) return [];

    List<Map<String, dynamic>> plans = [];

    // 1. Try backend plans API
    try {
      final list = await WavePassApi.instance.listPlans(venueId: vid);
      if (list.isNotEmpty) {
        plans = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    // 2. Fallback to Supabase direct query
    if (plans.isEmpty) {
      try {
        final dbPlans = await SupabaseService.instance.getActivePlans(vid);
        if (dbPlans.isNotEmpty) {
          plans = dbPlans;
        }
      } catch (_) {}
    }

    plansNotifier.value = plans;
    return plans;
  }

  /// Updates the venue name, slug, or logo, and immediately notifies all screens.
  Future<Map<String, dynamic>> updateVenue({
    required String name,
    required String slug,
    String? logoUrl,
  }) async {
    final vid = currentVenueId;
    if (vid == null || vid.isEmpty) {
      throw Exception('No active venue to update');
    }

    final cleanSlug = slug.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');
    final payload = <String, dynamic>{
      'name': name.trim(),
      'slug': cleanSlug,
    };
    if (logoUrl != null) payload['logoUrl'] = logoUrl;

    Map<String, dynamic>? updated;

    // 1. Try backend patch
    try {
      final res = await WavePassApi.instance.patchVenue(vid, payload);
      if (res['id'] != null) updated = res;
    } catch (_) {}

    // 2. Supabase direct fallback
    if (updated == null) {
      try {
        final res = await SupabaseService.instance.client
            .from('Venue')
            .update(payload)
            .eq('id', vid)
            .select()
            .maybeSingle();
        if (res != null) updated = Map<String, dynamic>.from(res);
      } catch (e) {
        throw Exception('Failed to update venue: $e');
      }
    }

    // Update in-memory state & notify all listeners
    final current = Map<String, dynamic>.from(venueNotifier.value ?? {});
    current['name'] = name.trim();
    current['slug'] = cleanSlug;
    if (logoUrl != null) current['logoUrl'] = logoUrl;
    venueNotifier.value = current;

    // Persist to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyVenueName, name.trim());
    await prefs.setString(keyLegacyVenueName, name.trim());
    await prefs.setString(keyVenueSlug, cleanSlug);
    if (logoUrl != null) await prefs.setString(keyVenueLogo, logoUrl);

    return current;
  }

  /// Validates and checks whether a subdomain/slogan is available.
  Future<Map<String, dynamic>> checkSlugAvailability(String rawSlug) async {
    final slug = rawSlug.trim().toLowerCase();
    if (slug.isEmpty) {
      return {'available': false, 'reason': 'Subdomain cannot be empty'};
    }
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      return {'available': false, 'reason': 'Only lowercase letters, numbers, and hyphens allowed'};
    }
    if (slug.length < 2) {
      return {'available': false, 'reason': 'Subdomain must be at least 2 characters'};
    }
    if (currentVenueSlug == slug) {
      return {'available': true, 'isCurrent': true, 'message': 'Current venue subdomain'};
    }

    // 1. Try backend API
    try {
      final res = await WavePassApi.instance.checkSlugAvailability(slug, venueId: currentVenueId);
      if (res.containsKey('available')) return res;
    } catch (_) {}

    // 2. Fallback to Supabase direct query
    try {
      final res = await SupabaseService.instance.client
          .from('Venue')
          .select('id, slug')
          .eq('slug', slug)
          .maybeSingle();

      if (res == null) {
        return {'available': true, 'message': 'Subdomain is available'};
      }
      final existingId = res['id']?.toString();
      if (existingId == currentVenueId) {
        return {'available': true, 'isCurrent': true, 'message': 'Current venue subdomain'};
      }
      return {'available': false, 'reason': 'Subdomain already taken by another venue'};
    } catch (_) {
      return {'available': true, 'message': 'Subdomain looks good'};
    }
  }

  /// Creates a new Plan using backend API with Supabase fallback, and updates all screens.
  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> planData) async {
    var vid = currentVenueId;
    if (vid == null || vid.isEmpty) {
      final venue = await refreshVenue();
      vid = venue?['id']?.toString();
    }
    if (vid == null || vid.isEmpty) {
      throw Exception('Cannot create plan: no active venue found.');
    }

    final payload = Map<String, dynamic>.from(planData);
    payload['venueId'] = vid;
    payload['active'] = true;
    payload['mode'] = payload['mode'] ?? 'ELAPSED';

    Map<String, dynamic>? created;

    // 1. Try backend API
    try {
      final res = await WavePassApi.instance.createPlan(payload);
      if (res['id'] != null) created = res;
    } catch (e) {
      debugPrint('[VenueStateService] backend createPlan failed: $e, trying Supabase');
    }

    // 2. Direct Supabase fallback
    if (created == null) {
      final res = await SupabaseService.instance.client
          .from('Plan')
          .insert(payload)
          .select()
          .single();
      created = Map<String, dynamic>.from(res);
    }

    // Trigger reactive plans update across all screens
    await refreshPlans();
    return created;
  }

  /// Updates an existing Plan and refreshes all screens.
  Future<Map<String, dynamic>> updatePlan(String planId, Map<String, dynamic> updateData) async {
    Map<String, dynamic>? updated;

    try {
      final res = await WavePassApi.instance.updatePlan(planId, updateData);
      if (res['id'] != null) updated = res;
    } catch (_) {}

    if (updated == null) {
      final res = await SupabaseService.instance.client
          .from('Plan')
          .update(updateData)
          .eq('id', planId)
          .select()
          .single();
      updated = Map<String, dynamic>.from(res);
    }

    await refreshPlans();
    return updated;
  }

  /// Deletes or deactivates a Plan and refreshes all screens.
  Future<void> deletePlan(String planId) async {
    try {
      await WavePassApi.instance.deletePlan(planId);
    } catch (_) {
      await SupabaseService.instance.client.from('Plan').delete().eq('id', planId);
    }
    await refreshPlans();
  }
}
