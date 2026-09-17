import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'supabase_service.dart';

/// Lightweight HTTP client for the WavePass NestJS backend (single-key
/// Paystack with dedicated virtual accounts + password-confirmed cashouts).
class WavePassApi {
  WavePassApi._();
  static final WavePassApi instance = WavePassApi._();

  static const String _base = ApiConstants.cloudBaseUrl;
  static const Duration _timeout = Duration(seconds: 15);

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(Uri.parse('$_base$path'),
            headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$_base$path'), headers: _jsonHeaders).timeout(_timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(Uri.parse('$_base$path'), headers: _jsonHeaders, body: jsonEncode(body)).timeout(_timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) => _post(path, body);

  Future<Map<String, dynamic>> clientPatch(String path, Map<String, dynamic> body) => _patch(path, body);

  Future<Map<String, dynamic>> patchVenue(String id, Map<String, dynamic> data) => _patch('/api/v1/venues/$id', data);

  Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return {'status': res.statusCode};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'status': res.statusCode, 'data': decoded};
  }

  // ── Venue helpers ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getDefaultVenue() {
    return _get('/api/v1/venues/default');
  }

  Future<Map<String, dynamic>> createVenue({required String name, required String slug, String? logoUrl}) {
    final body = {'name': name, 'slug': slug};
    if (logoUrl != null && logoUrl.trim().isNotEmpty) {
      body['logoUrl'] = logoUrl.trim();
    }
    return _post('/api/v1/venues', body);
  }

  Future<Map<String, dynamic>> getVenueBySubdomain(String sub) {
    return _get('/api/v1/venues/by-subdomain/${Uri.encodeComponent(sub)}');
  }

  Future<Map<String, dynamic>> getVenueByHost(String host) {
    return _get('/api/v1/venues/by-host?host=${Uri.encodeComponent(host)}');
  }

  /// New-venue setup gate: reports missing plans/router before going live.
  Future<Map<String, dynamic>> venueReadiness(String venueId) {
    return _get('/api/v1/venues/${Uri.encodeComponent(venueId)}/readiness');
  }

  Future<Map<String, dynamic>> checkSlugAvailability(String slug, {String? venueId}) {
    final query = venueId != null ? '?venueId=$venueId' : '';
    return _get('/api/v1/venues/check-slug/${Uri.encodeComponent(slug)}$query');
  }

  // ── Plan endpoints ─────────────────────────────────────────────────────
  Future<List<dynamic>> listPlans({String? venueId}) async {
    final query = venueId != null ? '?venueId=$venueId' : '';
    final res = await http.get(Uri.parse('$_base/api/v1/plans$query'), headers: _jsonHeaders).timeout(_timeout);
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['data'] is List) return decoded['data'];
    }
    return [];
  }

  Future<Map<String, dynamic>> getPlan(String id) {
    return _get('/api/v1/plans/$id');
  }

  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> dto) {
    return _post('/api/v1/plans', dto);
  }

  Future<Map<String, dynamic>> updatePlan(String id, Map<String, dynamic> dto) {
    return _patch('/api/v1/plans/$id', dto);
  }

  Future<Map<String, dynamic>> deletePlan(String id) async {
    final res = await http.delete(Uri.parse('$_base/api/v1/plans/$id'), headers: _jsonHeaders).timeout(_timeout);
    return _decode(res);
  }

  // ── Voucher cloud sync ───────────────────────────────────────────────
  /// Uploads caller-generated codes so cloud records match app + router.
  /// Returns {vouchers, requested, created, conflicts}.
  Future<Map<String, dynamic>> uploadVoucherBatch({
    required String venueId,
    required String planId,
    required List<String> codes,
  }) {
    return _post('/api/v1/vouchers/batches', {
      'venueId': venueId,
      'planId': planId,
      'quantity': codes.length,
      if (codes.length == 1) 'customCode': codes.first,
      if (codes.length > 1) 'customCodes': codes,
    });
  }

  /// Non-consuming cloud existence check for a single code.
  Future<Map<String, dynamic>> checkVoucher(String code) {
    return _get('/api/v1/vouchers/check/${Uri.encodeComponent(code)}');
  }

  // ── Virtual accounts (DVA per venue) ───────────────────────────────────
  Future<Map<String, dynamic>> ensureVirtualAccount(
      String venueId, {String? email}) {
    return _post('/api/v1/virtual-accounts/ensure/$venueId',
        email == null ? {} : {'email': email});
  }

  Future<Map<String, dynamic>> getVirtualAccount(String venueId) {
    return _get('/api/v1/virtual-accounts/venue/$venueId');
  }

  // ── Venue balance & cashouts ───────────────────────────────────────────
  Future<Map<String, dynamic>> venueBalance(String venueId) {
    return _get('/api/v1/cashouts/balance/$venueId');
  }

  Future<Map<String, dynamic>> registerBankAccount({
    required String venueId,
    required String accountName,
    required String accountNumber,
    required String bankCode,
    String? bankName,
  }) {
    return _post('/api/v1/cashouts/bank-accounts', {
      'venueId': venueId,
      'accountName': accountName,
      'accountNumber': accountNumber,
      'bankCode': bankCode,
      'bankName': ?bankName,
    });
  }

  Future<dynamic> listBankAccounts(String venueId) {
    return _get('/api/v1/cashouts/bank-accounts?venueId=${Uri.encodeComponent(venueId)}');
  }

  Future<List<dynamic>> listStorePayments(String venueId, {int limit = 50}) async {
    try {
      final res = await _get('/api/v1/cashouts/payments/${Uri.encodeComponent(venueId)}?limit=$limit');
      if (res['data'] is List) return List<dynamic>.from(res['data'] as List);
      return [];
    } catch (_) {
      try {
        final res = await SupabaseService.instance.client
            .from('Payment')
            .select('id, amountMinor, status, provider, providerReference, channel, paidAt, createdAt, Order!inner(venueId, customerRef, Plan(name))')
            .eq('Order.venueId', venueId)
            .eq('status', 'FULFILLED')
            .order('createdAt', ascending: false)
            .limit(limit);
        return List<Map<String, dynamic>>.from(res).map((p) {
          final order = p['Order'] as Map? ?? {};
          final plan = order['Plan'] as Map? ?? {};
          return {
            'id': p['id'],
            'amountMinor': p['amountMinor'],
            'amountNGN': ((p['amountMinor'] as num?)?.toInt() ?? 0) / 100,
            'status': p['status'],
            'provider': p['provider'],
            'providerReference': p['providerReference'],
            'channel': p['channel'],
            'paidAt': p['paidAt'],
            'createdAt': p['createdAt'],
            'planName': plan['name'] ?? 'Wi-Fi Pass',
            'customerRef': order['customerRef'],
          };
        }).toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<Map<String, dynamic>> requestCashout({
    required String venueId,
    required int amountMinor,
    required String password,
    String? reason,
  }) {
    return _post('/api/v1/cashouts', {
      'venueId': venueId,
      'amountMinor': amountMinor,
      'password': password,
      'reason': ?reason,
    });
  }

  Future<Map<String, dynamic>> confirmCashout({
    required String cashoutId,
    required String adminPassword,
  }) {
    return _post('/api/v1/cashouts/confirm', {
      'cashoutId': cashoutId,
      'adminPassword': adminPassword,
    });
  }

  Future<Map<String, dynamic>> listCashouts(String venueId) {
    return _get('/api/v1/cashouts?venueId=$venueId');
  }

  Future<Map<String, dynamic>> adminStats() {
    return _get('/api/v1/admin/stats');
  }

  // ── Notifications (venue-owner payment bar) ──────────────────────────
  Future<List<dynamic>> listNotifications(String venueId, {bool unreadOnly = false}) async {
    final res = await http
        .get(
          Uri.parse('$_base/api/v1/notifications?venueId=${Uri.encodeComponent(venueId)}${unreadOnly ? '&unreadOnly=true' : ''}'),
          headers: _jsonHeaders,
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['data'] is List) return decoded['data'];
    }
    return [];
  }

  Future<Map<String, dynamic>> markNotificationRead(String id) {
    return _patch('/api/v1/notifications/$id/read', {});
  }

  Future<Map<String, dynamic>> markAllNotificationsRead(String venueId) {
    return _post('/api/v1/notifications/venue/$venueId/read-all', {});
  }

  // ── Venue sales funnel (initiated → paid → active + revenue) ──────────
  Future<Map<String, dynamic>> fetchFunnel(String venueId, {int days = 7}) async {
    try {
      return await _get('/api/v1/admin/funnel?venueId=${Uri.encodeComponent(venueId)}&days=$days');
    } catch (_) {
      return {};
    }
  }

  // ── Router endpoints ──────────────────────────────────────────────────
  Future<List<dynamic>> listRouters({String? venueId}) async {
    final query = venueId != null ? '?venueId=$venueId' : '';
    final res = await http.get(Uri.parse('$_base/api/v1/routers$query'), headers: _jsonHeaders).timeout(_timeout);
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['data'] is List) return decoded['data'];
    }
    return [];
  }

  Future<Map<String, dynamic>> getRouterHealth(String routerId) {
    return _get('/api/v1/routers/$routerId/health');
  }

  Future<Map<String, dynamic>> testRouter(String routerId) {
    return _post('/api/v1/routers/$routerId/test', {});
  }

  Future<String> getRouterProvisionScript(String routerId) async {
    final res = await http.get(Uri.parse('$_base/api/v1/routers/$routerId/provision.rsc')).timeout(_timeout);
    return res.body;
  }

  Future<Map<String, dynamic>> createRouter({
    required String venueId,
    required String name,
    required String endpoint,
    required String connectionMode,
    String? rosVersion,
  }) {
    return _post('/api/v1/routers', {
      'venueId': venueId,
      'name': name,
      'endpoint': endpoint,
      'connectionMode': connectionMode,
      'rosVersion': ?rosVersion,
    });
  }

  Future<Map<String, dynamic>> updateProfile({
    required String email,
    String? name,
    String? newEmail,
  }) {
    return _post('/api/v1/admin/update-profile', {
      'email': email,
      'name': ?name,
      'newEmail': ?newEmail,
    });
  }

  Future<Map<String, dynamic>> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) {
    return _post('/api/v1/admin/change-password', {
      'email': email,
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<Map<String, dynamic>> deleteAccount({
    required String email,
    required String password,
  }) {
    return _post('/api/v1/admin/delete-account', {
      'email': email,
      'password': password,
    });
  }

  // ── Portal Transfer Approval & Voucher Retrieval ────────────────────────
  Future<Map<String, dynamic>> approveAccess({
    required String venueId,
    String? orderId,
    required String mac,
    String? planId,
    String? reference,
  }) {
    return _post('/api/v1/portal/approve-access', {
      'venueId': venueId,
      'orderId': ?orderId,
      'mac': mac,
      'planId': ?planId,
      'reference': ?reference,
    });
  }

  Future<Map<String, dynamic>> submitTransferRequest({
    String? venueSlug,
    String? venueId,
    required String mac,
    required String planId,
    String? senderName,
    int? amountMinor,
    String? bankAccount,
    String? notes,
  }) {
    return _post('/api/v1/portal/transfer-request', {
      'venueSlug': ?venueSlug,
      'venueId': ?venueId,
      'mac': mac,
      'planId': planId,
      'senderName': ?senderName,
      'amountMinor': ?amountMinor,
      'bankAccount': ?bankAccount,
      'notes': ?notes,
    });
  }

  Future<Map<String, dynamic>> retrieveVoucher({
    String? mac,
    String? query,
    String? venueId,
  }) {
    final qParams = <String>[];
    if (mac != null) qParams.add('mac=${Uri.encodeComponent(mac)}');
    if (query != null) qParams.add('query=${Uri.encodeComponent(query)}');
    if (venueId != null) qParams.add('venueId=${Uri.encodeComponent(venueId)}');
    final q = qParams.isNotEmpty ? '?${qParams.join('&')}' : '';
    return _get('/api/v1/portal/retrieve-voucher$q');
  }

  Future<Map<String, dynamic>> getPortalVenueInfo({String? venueSlug, String? venueId}) {
    final v = venueSlug ?? venueId;
    final q = v != null ? '?venue=${Uri.encodeComponent(v)}' : '';
    return _get('/api/v1/portal/info$q');
  }
}