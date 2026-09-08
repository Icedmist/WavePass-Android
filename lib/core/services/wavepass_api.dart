import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';

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

  Future<Map<String, dynamic>> createVenue({required String name, required String slug, required String logoUrl}) {
    return _post('/api/v1/venues', {'name': name, 'slug': slug, 'logoUrl': logoUrl});
  }

  Future<Map<String, dynamic>> getVenueBySubdomain(String sub) {
    return _get('/api/v1/venues/by-subdomain/${Uri.encodeComponent(sub)}');
  }

  Future<Map<String, dynamic>> getVenueByHost(String host) {
    return _get('/api/v1/venues/by-host?host=${Uri.encodeComponent(host)}');
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
}