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
    final res = await http
        .get(Uri.parse('$_base$path'), headers: _jsonHeaders)
        .timeout(_timeout);
    return _decode(res);
  }

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
      if (bankName != null) 'bankName': bankName,
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
      if (reason != null) 'reason': reason,
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
}