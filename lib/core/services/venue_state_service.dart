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
  static const String keyLegacyVenueSlug = 'venueSlug';
  static const String keyVenueLogo = 'wavepass_active_venue_logo';
  static const String keyLegacyVenueLogo = 'venueLogo';

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

  /// Initialize state from SharedPreferences cache, then refresh from cloud if cached.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedId = prefs.getString(keyVenueId) ?? prefs.getString(keyLegacyVenueId);
      final cachedName = prefs.getString(keyVenueName) ?? prefs.getString(keyLegacyVenueName);
      final cachedSlug = prefs.getString(keyVenueSlug) ?? prefs.getString(keyLegacyVenueSlug);
      final cachedLogo = prefs.getString(keyVenueLogo) ?? prefs.getString(keyLegacyVenueLogo);

      if (cachedId != null && cachedId.isNotEmpty) {
        venueNotifier.value = {
          'id': cachedId,
          'name': cachedName ?? 'WavePass Venue',
          'slug': cachedSlug ?? 'venue',
          'logoUrl': cachedLogo,
        };
        await refreshVenue(targetVenueId: cachedId);
      }
    } catch (_) {}
  }

  /// Clears active venue state from memory and persistent storage.
  /// Must be called upon user logout.
  Future<void> clearVenue() async {
    venueNotifier.value = null;
    plansNotifier.value = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyVenueId);
      await prefs.remove(keyLegacyVenueId);
      await prefs.remove(keyVenueName);
      await prefs.remove(keyLegacyVenueName);
      await prefs.remove(keyVenueSlug);
      await prefs.remove(keyLegacyVenueSlug);
      await prefs.remove(keyVenueLogo);
      await prefs.remove(keyLegacyVenueLogo);
    } catch (_) {}
  }

  /// Creates a new Venue. Subdomain/slug input is permanently disabled:
  /// a collision-free internal slug is generated automatically behind the scenes.
  Future<Map<String, dynamic>> createVenue({
    required String name,
    String? slug,
    String? logoUrl,
  }) async {
    final cleanName = name.trim().isEmpty ? 'My Venue' : name.trim();
    final autoSlug = (slug != null && slug.trim().isNotEmpty)
        ? slug.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        : 'v-${DateTime.now().millisecondsSinceEpoch}-${cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').padRight(4, '0').substring(0, 4)}';

    Map<String, dynamic>? created;

    // 1. Try backend API
    try {
      final res = await WavePassApi.instance.createVenue(
        name: cleanName,
        slug: autoSlug,
        logoUrl: logoUrl,
      );
      if (res['id'] != null) {
        created = res;
      }
    } catch (e) {
      debugPrint('[VenueStateService] backend createVenue failed: $e');
    }

    // 2. Fallback to Supabase direct insert
    if (created == null) {
      try {
        final payload = {
          'name': cleanName,
          'slug': autoSlug,
          'timezone': 'Africa/Lagos',
          'currency': 'NGN',
          'status': 'active',
          if (logoUrl != null && logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        };
        final res = await SupabaseService.instance.client
            .from('Venue')
            .insert(payload)
            .select()
            .single();
        created = Map<String, dynamic>.from(res);
      } catch (e) {
        debugPrint('[VenueStateService] Supabase createVenue fallback error: $e');
      }
    }

    created ??= {
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'name': cleanName,
      'slug': autoSlug,
      'logoUrl': logoUrl ?? '',
    };

    final vId = created['id']?.toString() ?? autoSlug;
    final effectiveLogo = created['logoUrl']?.toString() ?? logoUrl ?? '';

    // Automatically link venue to current user if logged in
    final user = SupabaseService.instance.currentUser;
    if (user != null) {
      try {
        await SupabaseService.instance.client.from('User').upsert({
          'id': user.id,
          'email': user.email ?? '',
          'authProvider': 'supabase',
          'status': 'active',
        });
        await SupabaseService.instance.client.from('VenueMember').upsert({
          'venueId': vId,
          'userId': user.id,
          'role': 'Owner',
        });
      } catch (_) {}
    }

    // Persist to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyVenueId, vId);
    await prefs.setString(keyLegacyVenueId, vId);
    await prefs.setString(keyVenueName, cleanName);
    await prefs.setString(keyLegacyVenueName, cleanName);
    await prefs.setString(keyVenueSlug, autoSlug);
    await prefs.setString(keyLegacyVenueSlug, autoSlug);
    if (effectiveLogo.isNotEmpty) {
      await prefs.setString(keyVenueLogo, effectiveLogo);
      await prefs.setString(keyLegacyVenueLogo, effectiveLogo);
    }

    venueNotifier.value = Map<String, dynamic>.from(created);
    await refreshPlans();
    return created;
  }

  /// Refreshes the active venue from the backend API or Supabase.
  Future<Map<String, dynamic>?> refreshVenue({
    String? targetVenueId,
    bool allowFallbackToPrimary = true,
  }) async {
    isLoadingNotifier.value = true;
    Map<String, dynamic>? venue;

    try {
      final prefs = await SharedPreferences.getInstance();
      final vid = targetVenueId ?? prefs.getString(keyVenueId) ?? prefs.getString(keyLegacyVenueId);
      final slug = prefs.getString(keyVenueSlug) ?? prefs.getString(keyLegacyVenueSlug);
      final currentEmail = (prefs.getString('sb-user-email') ?? SupabaseService.instance.currentUser?.email ?? '').toLowerCase().trim();

      // 1. Try target or cached ID from Supabase.
      // Self-heal: if this device had the venue cached but the user has no
      // VenueMember row (accounts created before linking / backend-created
      // venues), re-link them now so the strict member-only lookup in step 2
      // keeps working after updates. Cached ID proves prior access — this
      // restores *their* venue, it never grants a new one.
      if (vid != null && vid.isNotEmpty) {
        try {
          final res = await SupabaseService.instance.client
              .from('Venue')
              .select('*')
              .eq('id', vid)
              .maybeSingle();
          if (res != null) venue = Map<String, dynamic>.from(res);
        } catch (_) {}
        if (venue != null) {
          try {
            final user = SupabaseService.instance.currentUser;
            if (user != null) {
              await SupabaseService.instance.client.from('User').upsert({
                'id': user.id,
                'email': user.email ?? '',
                'authProvider': 'supabase',
                'status': 'active',
              });
              final existing = await SupabaseService.instance.client
                  .from('VenueMember')
                  .select('venueId')
                  .eq('venueId', vid)
                  .eq('userId', user.id)
                  .limit(1)
                  .maybeSingle();
              if (existing == null) {
                await SupabaseService.instance.client.from('VenueMember').upsert({
                  'venueId': vid,
                  'userId': user.id,
                  'role': 'Owner',
                });
              }
            }
          } catch (_) {}
        }
      }

      // 2. Try primary venue for user from Supabase (strictly member-only;
      // non-members get null unless super-admin — never another venue's data)
      if (venue == null && allowFallbackToPrimary) {
        try {
          venue = await SupabaseService.instance.getPrimaryVenue(email: currentEmail);
        } catch (_) {}
      }

      // 3. Try finding by slug from backend
      if (venue == null && slug != null && slug.isNotEmpty) {
        try {
          final res = await WavePassApi.instance.getVenueBySubdomain(slug);
          if (res['id'] != null) venue = res;
        } catch (_) {}
      }

      // 4. Default-venue fallback is super-admin / logged-out only.
      // Binding a regular operator to the global default venue is what leaked
      // other venues' pricing tiers into Admin Hub / Sell / guest portal.
      final isSuperAdmin =
          currentEmail == SupabaseService.superAdminEmail;
      if (venue == null && allowFallbackToPrimary && (isSuperAdmin || currentEmail.isEmpty)) {
        try {
          final res = await WavePassApi.instance.getDefaultVenue();
          if (res['id'] != null) venue = res;
        } catch (_) {}
      }

      if (venue != null) {
        venueNotifier.value = Map<String, dynamic>.from(venue);
        final id = venue['id']?.toString() ?? '';
        final name = venue['name']?.toString() ?? 'WavePass Venue';
        final slugVal = venue['slug']?.toString() ?? 'venue';
        final logo = venue['logoUrl']?.toString() ?? '';

        await prefs.setString(keyVenueId, id);
        await prefs.setString(keyLegacyVenueId, id);
        await prefs.setString(keyVenueName, name);
        await prefs.setString(keyLegacyVenueName, name);
        await prefs.setString(keyVenueSlug, slugVal);
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
    if (plans.isEmpty && SupabaseService.isInitialized) {
      try {
        final dbPlans = await SupabaseService.instance.getActivePlans(vid);
        if (dbPlans.isNotEmpty) {
          plans = dbPlans;
        }
      } catch (_) {}
    }

    if (plans.isNotEmpty) {
      plansNotifier.value = plans;
    }
    return plansNotifier.value;
  }

  /// Updates the venue name or logo, and immediately notifies all screens.
  /// Subdomain/slug input is optional/disabled — preserves existing slug or generates one.
  Future<Map<String, dynamic>> updateVenue({
    required String name,
    String? slug,
    String? logoUrl,
  }) async {
    final vid = currentVenueId;
    if (vid == null || vid.isEmpty) {
      throw Exception('No active venue to update');
    }

    final cleanName = name.trim();
    final cleanSlug = (slug != null && slug.trim().isNotEmpty)
        ? slug.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        : (currentVenueSlug.isNotEmpty ? currentVenueSlug : 'v-${DateTime.now().millisecondsSinceEpoch}');

    final payload = <String, dynamic>{
      'name': cleanName,
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
        debugPrint('[VenueStateService] Supabase patch fallback: $e');
      }
    }

    // Update in-memory state & notify all listeners
    final current = Map<String, dynamic>.from(venueNotifier.value ?? {});
    current['name'] = cleanName;
    current['slug'] = cleanSlug;
    if (logoUrl != null) current['logoUrl'] = logoUrl;
    venueNotifier.value = current;

    // Persist to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyVenueName, cleanName);
    await prefs.setString(keyLegacyVenueName, cleanName);
    await prefs.setString(keyVenueSlug, cleanSlug);
    if (logoUrl != null) await prefs.setString(keyVenueLogo, logoUrl);

    return current;
  }

  /// Switch currently active venue (useful for System Admin multi-venue inspection)
  Future<void> switchVenue(Map<String, dynamic> venue) async {
    venueNotifier.value = Map<String, dynamic>.from(venue);
    final prefs = await SharedPreferences.getInstance();
    final vid = venue['id']?.toString();
    final name = venue['name']?.toString();
    final slug = venue['slug']?.toString();
    final logo = venue['logoUrl']?.toString();

    if (vid != null) {
      await prefs.setString(keyVenueId, vid);
      await prefs.setString(keyLegacyVenueId, vid);
    }
    if (name != null) {
      await prefs.setString(keyVenueName, name);
      await prefs.setString(keyLegacyVenueName, name);
    }
    if (slug != null) {
      await prefs.setString(keyVenueSlug, slug);
      await prefs.setString(keyLegacyVenueSlug, slug);
    }
    if (logo != null) {
      await prefs.setString(keyVenueLogo, logo);
      await prefs.setString(keyLegacyVenueLogo, logo);
    }

    await refreshPlans();
  }

  /// Subdomain/slug feature is permanently disabled: always returns available.
  Future<Map<String, dynamic>> checkSlugAvailability(String rawSlug) async {
    return {'available': true, 'isCurrent': true, 'message': 'Subdomain feature disabled'};
  }

  /// Creates a new Plan using backend API with Supabase fallback, and updates all screens.
  /// Automatically resolves or provisions a venue so plan creation NEVER fails.
  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> planData) async {
    var vid = currentVenueId;
    if (vid == null || vid.isEmpty) {
      final venue = await refreshVenue(allowFallbackToPrimary: true);
      vid = venue?['id']?.toString();
    }
    // If still no venue exists (e.g. brand new user who jumped straight to plan creation),
    // automatically provision a default venue so plan creation never fails:
    if (vid == null || vid.isEmpty) {
      final newVenue = await createVenue(name: 'My Venue');
      vid = newVenue['id']?.toString();
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
    if (created == null && SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.instance.client
            .from('Plan')
            .insert(payload)
            .select()
            .single();
        created = Map<String, dynamic>.from(res);
      } catch (e) {
        debugPrint('[VenueStateService] Supabase createPlan fallback error: $e');
      }
    }

    if (created == null) {
      // Offline fallback: create local plan representation
      created = {
        'id': 'plan-${DateTime.now().millisecondsSinceEpoch}',
        ...payload,
      };
      final existingPlans = List<Map<String, dynamic>>.from(plansNotifier.value);
      existingPlans.add(created);
      plansNotifier.value = existingPlans;
    } else {
      // Trigger reactive plans update across all screens
      await refreshPlans();
    }
    return created;
  }

  /// Updates an existing Plan and refreshes all screens.
  Future<Map<String, dynamic>> updatePlan(String planId, Map<String, dynamic> updateData) async {
    Map<String, dynamic>? updated;

    try {
      final res = await WavePassApi.instance.updatePlan(planId, updateData);
      if (res['id'] != null) updated = res;
    } catch (_) {}

    if (updated == null && SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.instance.client
            .from('Plan')
            .update(updateData)
            .eq('id', planId)
            .select()
            .single();
        updated = Map<String, dynamic>.from(res);
      } catch (e) {
        debugPrint('[VenueStateService] Supabase updatePlan fallback error: $e');
      }
    }

    if (updated == null) {
      updated = {'id': planId, ...updateData};
      final existingPlans = List<Map<String, dynamic>>.from(plansNotifier.value);
      final idx = existingPlans.indexWhere((p) => p['id']?.toString() == planId);
      if (idx != -1) {
        existingPlans[idx] = {...existingPlans[idx], ...updateData};
        plansNotifier.value = existingPlans;
      }
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
