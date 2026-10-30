import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'router_discovery_service.dart';
import 'supabase_service.dart';
import 'venue_state_service.dart';
import 'voucher_history_service.dart';

/// Centralized service to persist and synchronize all user and operator configurations
/// directly to the cloud Supabase database (`UserAppState` table).
/// Ensures that venues, plans, router pairings, portal customizations, printer setups,
/// and voucher histories survive application deletion, cache clears, and logouts.
class UserAppStateService {
  UserAppStateService._();
  static final UserAppStateService instance = UserAppStateService._();

  static const String _table = 'UserAppState';

  /// Syncs state from Supabase to local memory and SharedPreferences upon login or launch.
  Future<Map<String, dynamic>?> syncFromCloud({String? targetEmail}) async {
    try {
      if (!SupabaseService.isInitialized) return null;

      final prefs = await SharedPreferences.getInstance();
      final email = (targetEmail ??
              SupabaseService.instance.currentUser?.email ??
              prefs.getString('sb-user-email') ??
              prefs.getString('sb-last-signed-in-email') ??
              '')
          .trim()
          .toLowerCase();

      if (email.isEmpty) return null;

      final supabase = SupabaseService.instance.client;
      final res = await supabase
          .from(_table)
          .select('*')
          .eq('email', email)
          .maybeSingle();

      if (res == null) {
        debugPrint('[UserAppStateService] No remote UserAppState found for $email');
        return null;
      }

      final data = Map<String, dynamic>.from(res);
      debugPrint('[UserAppStateService] Rehydrating user app state for $email from Supabase');

      // 1. Active Venue rehydration
      final activeVid = data['activeVenueId']?.toString();
      if (activeVid != null && activeVid.isNotEmpty) {
        await prefs.setString(VenueStateService.keyVenueId, activeVid);
        await prefs.setString(VenueStateService.keyLegacyVenueId, activeVid);
        await prefs.setString(VenueStateService.keyLastKnownVenueId, activeVid);
        await VenueStateService.instance.refreshVenue(targetVenueId: activeVid);
        await VenueStateService.instance.refreshPlans();
      }

      // 2. Router configuration rehydration
      final router = data['routerConfig'] as Map<String, dynamic>? ??
          (data['routerConfig'] is String ? jsonDecode(data['routerConfig'] as String) : null);
      if (router is Map) {
        final ip = router['localIp']?.toString();
        final user = router['username']?.toString();
        final pass = router['password']?.toString();
        final tunnel = router['tunnelEndpoint']?.toString();
        if (ip != null && ip.isNotEmpty) await prefs.setString(RouterDiscoveryService.keyRouterLocalIp, ip);
        if (user != null && user.isNotEmpty) await prefs.setString(RouterDiscoveryService.keyRouterUsername, user);
        if (pass != null && pass.isNotEmpty) await prefs.setString(RouterDiscoveryService.keyRouterPassword, pass);
        if (tunnel != null && tunnel.isNotEmpty) await prefs.setString(RouterDiscoveryService.keyRouterTunnelEndpoint, tunnel);
      }

      // 3. Captive portal branding rehydration
      final branding = data['portalBranding'] as Map<String, dynamic>? ??
          (data['portalBranding'] is String ? jsonDecode(data['portalBranding'] as String) : null);
      if (branding is Map) {
        final bg = branding['bgUrl']?.toString();
        final logo = branding['logoUrl']?.toString();
        final template = branding['templateId']?.toString();
        final effectiveTemplate = (template == null || template.isEmpty || template == 'classic-glass') ? 'onyx' : template;
        if (bg != null && bg.isNotEmpty) await prefs.setString('wavepass_portal_bg_url', bg);
        if (logo != null && logo.isNotEmpty) {
          await prefs.setString('wavepass_portal_logo_url', logo);
          await prefs.setString(VenueStateService.keyVenueLogo, logo);
        }
        await prefs.setString('wavepass_portal_template', effectiveTemplate);
      }

      // 4. Thermal printer configuration rehydration
      final printer = data['printerConfig'] as Map<String, dynamic>? ??
          (data['printerConfig'] is String ? jsonDecode(data['printerConfig'] as String) : null);
      if (printer is Map) {
        final pUrl = printer['printerUrl']?.toString();
        final pName = printer['printerName']?.toString();
        final pAuto = printer['autoPrint'];
        final pWidth = printer['paperWidth'];
        if (pUrl != null && pUrl.isNotEmpty) await prefs.setString('wavepass_selected_printer_url', pUrl);
        if (pName != null && pName.isNotEmpty) await prefs.setString('wavepass_selected_printer_name', pName);
        if (pAuto is bool) await prefs.setBool('wavepass_auto_print_receipts', pAuto);
        if (pWidth is num) await prefs.setInt('wavepass_printer_paper_width', pWidth.toInt());
      }

      // 5. User preferences rehydration
      final preferences = data['preferences'] as Map<String, dynamic>? ??
          (data['preferences'] is String ? jsonDecode(data['preferences'] as String) : null);
      if (preferences is Map) {
        final hideBal = preferences['hideBalance'];
        if (hideBal is bool) await prefs.setBool('hide_balance_preference', hideBal);
      }

      // 6. Rehydrate vouchers from cloud for active venue
      await VoucherHistoryService.instance.fetchFullVoucherActivity();

      return data;
    } catch (e) {
      debugPrint('[UserAppStateService] Error syncing from cloud: $e');
      return null;
    }
  }

  /// Saves the complete state to Supabase.
  Future<void> saveToCloud() async {
    try {
      if (!SupabaseService.isInitialized) return;

      final prefs = await SharedPreferences.getInstance();
      final user = SupabaseService.instance.currentUser;
      final email = (user?.email ??
              prefs.getString('sb-user-email') ??
              prefs.getString('sb-last-signed-in-email') ??
              '')
          .trim()
          .toLowerCase();

      if (email.isEmpty) return;

      final activeVid = VenueStateService.instance.currentVenueId ??
          prefs.getString(VenueStateService.keyVenueId) ??
          prefs.getString(VenueStateService.keyLegacyVenueId);

      final routerConfig = {
        'localIp': prefs.getString(RouterDiscoveryService.keyRouterLocalIp) ?? '192.168.88.1',
        'username': prefs.getString(RouterDiscoveryService.keyRouterUsername) ?? 'admin',
        'password': prefs.getString(RouterDiscoveryService.keyRouterPassword) ?? '',
        'tunnelEndpoint': prefs.getString(RouterDiscoveryService.keyRouterTunnelEndpoint) ?? '',
      };

      final savedTemplate = prefs.getString('wavepass_portal_template');
      final effectiveTemplate = (savedTemplate == null || savedTemplate.isEmpty || savedTemplate == 'classic-glass') ? 'onyx' : savedTemplate;

      final portalBranding = {
        'bgUrl': prefs.getString('wavepass_portal_bg_url') ?? '',
        'logoUrl': prefs.getString('wavepass_portal_logo_url') ?? prefs.getString(VenueStateService.keyVenueLogo) ?? '',
        'templateId': effectiveTemplate,
      };

      final printerConfig = {
        'printerUrl': prefs.getString('wavepass_selected_printer_url') ?? '',
        'printerName': prefs.getString('wavepass_selected_printer_name') ?? '',
        'autoPrint': prefs.getBool('wavepass_auto_print_receipts') ?? true,
        'paperWidth': prefs.getInt('wavepass_printer_paper_width') ?? 58,
      };

      final preferences = {
        'hideBalance': prefs.getBool('hide_balance_preference') ?? false,
      };

      final payload = {
        'id': user?.id ?? email,
        if (user?.id != null) 'userId': user!.id,
        'email': email,
        if (activeVid != null && activeVid.isNotEmpty) 'activeVenueId': activeVid,
        'routerConfig': routerConfig,
        'portalBranding': portalBranding,
        'printerConfig': printerConfig,
        'preferences': preferences,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await SupabaseService.instance.client
          .from(_table)
          .upsert(payload, onConflict: 'email');

      debugPrint('[UserAppStateService] Successfully synced state to cloud for $email');
    } catch (e) {
      debugPrint('[UserAppStateService] Error saving state to cloud: $e');
    }
  }

  /// Updates active venue in cloud and triggers background sync.
  Future<void> saveActiveVenue(String venueId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(VenueStateService.keyVenueId, venueId);
    await prefs.setString(VenueStateService.keyLegacyVenueId, venueId);
    await prefs.setString(VenueStateService.keyLastKnownVenueId, venueId);
    saveToCloud();
  }

  /// Updates router credentials in cloud.
  Future<void> saveRouterConfig({
    String? localIp,
    String? username,
    String? password,
    String? tunnelEndpoint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (localIp != null) await prefs.setString(RouterDiscoveryService.keyRouterLocalIp, localIp);
    if (username != null) await prefs.setString(RouterDiscoveryService.keyRouterUsername, username);
    if (password != null) await prefs.setString(RouterDiscoveryService.keyRouterPassword, password);
    if (tunnelEndpoint != null) await prefs.setString(RouterDiscoveryService.keyRouterTunnelEndpoint, tunnelEndpoint);
    saveToCloud();
  }

  /// Updates captive portal branding in cloud.
  Future<void> savePortalBranding({
    String? bgUrl,
    String? logoUrl,
    String? templateId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (bgUrl != null) await prefs.setString('wavepass_portal_bg_url', bgUrl);
    if (logoUrl != null) {
      await prefs.setString('wavepass_portal_logo_url', logoUrl);
      await prefs.setString(VenueStateService.keyVenueLogo, logoUrl);
    }
    if (templateId != null) await prefs.setString('wavepass_portal_template', templateId);
    saveToCloud();
  }

  /// Updates printer settings in cloud.
  Future<void> savePrinterConfig({
    String? printerUrl,
    String? printerName,
    bool? autoPrint,
    int? paperWidth,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (printerUrl != null) await prefs.setString('wavepass_selected_printer_url', printerUrl);
    if (printerName != null) await prefs.setString('wavepass_selected_printer_name', printerName);
    if (autoPrint != null) await prefs.setBool('wavepass_auto_print_receipts', autoPrint);
    if (paperWidth != null) await prefs.setInt('wavepass_printer_paper_width', paperWidth);
    saveToCloud();
  }

  /// Updates balance visibility preference in cloud.
  Future<void> savePreferences({bool? hideBalance}) async {
    final prefs = await SharedPreferences.getInstance();
    if (hideBalance != null) await prefs.setBool('hide_balance_preference', hideBalance);
    saveToCloud();
  }
}
