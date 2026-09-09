import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/widgets/shimmer.dart';

/// Wallet / cashout hub. Shows the venue's dedicated virtual account (funded
/// via the single Nexa Paystack key), the available balance, and lets the venue
/// owner register a bank account and cash out automatically by confirming
/// **their own** password — no admin approval needed.
class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    this.venueId = 'default',
    this.admin = false,
  });

  final String venueId;
  final bool admin;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _api = WavePassApi.instance;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  Map<String, dynamic>? _virtualAccount;
  Map<String, dynamic>? _balance;
  List<dynamic> _cashouts = [];

  // New bank account form
  final _nameCtrl = TextEditingController();
  final _acctCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _acctCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var venueId = widget.venueId;
      if (venueId == 'default') {
        venueId = VenueStateService.instance.currentVenueId ?? 'default';
        if (venueId == 'default') {
          final venue = await _api.getDefaultVenue();
          venueId = venue['id']?.toString() ?? 'default';
        }
      }

      final va = await _api.getVirtualAccount(venueId);
      final vaData = va['accountNumber'] != null
          ? va
          : await _api.ensureVirtualAccount(venueId);
      final bal = await _api.venueBalance(venueId);
      final cashoutsRaw = await _api.listCashouts(venueId);
      final cashoutsList = cashoutsRaw is List
          ? (cashoutsRaw as List<dynamic>)
          : (cashoutsRaw['data'] as List<dynamic>? ?? cashoutsRaw['cashouts'] as List<dynamic>? ?? []);
      if (!mounted) return;
      setState(() {
        _virtualAccount = vaData;
        _balance = bal;
        _cashouts = List<dynamic>.from(cashoutsList);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load wallet: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _availableMinor => (_balance?['availableMinor'] as num?)?.toInt() ?? 0;
  double get _availableNgn => _availableMinor / 100;
  String get _acctNumber => _virtualAccount?['accountNumber']?.toString() ?? '—';
  String get _acctName => _virtualAccount?['accountName']?.toString() ?? '—';

  bool get _isPaystackConfigured {
    if (_virtualAccount == null) return false;
    final meta = _virtualAccount?['metadata'];
    if (meta is Map && (meta['mock'] == true || meta['mock']?.toString() == 'true')) {
      return false;
    }
    final bank = (_virtualAccount?['bankName']?.toString() ?? '').toLowerCase();
    if (bank.contains('mock')) return false;
    final acct = _virtualAccount?['accountNumber']?.toString() ?? '';
    if (acct.isEmpty || acct == '—') return false;
    return true;
  }

  Future<void> _requestCashout() async {
    if (!_isPaystackConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wallet Not Available: Paystack is not configured on the server.'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final amtCtrl = TextEditingController();
        final passCtrl = TextEditingController();
        bool obscurePass = true;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Cash Out'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (NGN)',
                    helperText: 'Payout goes to your registered bank account',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: obscurePass,
                  decoration: InputDecoration(
                    labelText: 'Confirm your password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: AppColors.textLight,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop({
                  'amount': double.tryParse(amtCtrl.text),
                  'password': passCtrl.text,
                }),
                child: const Text('Cash Out'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final amount = result['amount'] as double?;
    final password = result['password'] as String?;
    if (amount == null || amount <= 0 || password == null || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter an amount and your password.')),
        );
      }
      return;
    }

    // Resolve real venue id when using the 'default' placeholder
    var venueId = widget.venueId;
    if (venueId == 'default') {
      try {
        final venue = await _api.getDefaultVenue();
        venueId = venue['id']?.toString() ?? venueId;
      } catch (_) {}
    }

    setState(() => _submitting = true);
    try {
      await _api.requestCashout(
        venueId: venueId,
        amountMinor: (amount * 100).round(),
        password: password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cashout complete — funds on the way.')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _registerBank() async {
    if (!_isPaystackConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wallet Not Available: Paystack is not configured on the server.'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }
    final form = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        final h = AlertDialog(
          title: const Text('Register Bank Account'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Account Name')),
              TextField(controller: _acctCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Account Number')),
              TextField(controller: _bankCtrl, decoration: const InputDecoration(labelText: 'Bank Code (e.g. 058)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop({'name': _nameCtrl.text.trim(), 'acct': _acctCtrl.text.trim(), 'bank': _bankCtrl.text.trim()}), child: const Text('Save')),
          ],
        );
        return h;
      },
    );
    if (form == null) return;
    if (form['name']!.isEmpty || form['acct']!.isEmpty || form['bank']!.isEmpty) return;
    var venueId = widget.venueId;
    if (venueId == 'default') {
      try {
        final venue = await _api.getDefaultVenue();
        venueId = venue['id']?.toString() ?? venueId;
      } catch (_) {}
    }
    setState(() => _submitting = true);
    try {
      await _api.registerBankAccount(venueId: venueId, accountName: form['name']!, accountNumber: form['acct']!, bankCode: form['bank']!);
      _nameCtrl.clear();
      _acctCtrl.clear();
      _bankCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bank account registered for payouts.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _adminConfirmCashout(String id) async {
    final pass = await _askAdminPassword();
    if (pass == null) return;
    setState(() => _submitting = true);
    try {
      await _api.confirmCashout(cashoutId: id, adminPassword: pass);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cashout confirmed — payout processing.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rejected: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _askAdminPassword() {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Confirm Cashout'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your password to authorise this payout.'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Venue Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? ListView(padding: const EdgeInsets.all(20), children: const [
              ShimmerBox(h: 120, r: 26),
              SizedBox(height: 16),
              ShimmerBox(h: 140, r: 24),
              SizedBox(height: 16),
              ShimmerBox(h: 80, r: 16),
            ])
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 80),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.redTint, borderRadius: BorderRadius.circular(14)),
                          child: Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
                        ),
                      ),
                    // VIRTUAL ACCOUNT / WALLET STATUS
                    if (!_isPaystackConfigured)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppColors.containerBg,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentRed.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.accentRed, size: 24),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Wallet Not Available',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Paystack is not configured',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.accentRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Dedicated Virtual Accounts (DVA) and automated bank payouts require active Paystack API credentials on the server. Please configure PAYSTACK_SECRET_KEY in the backend environment to activate venue wallets.',
                              style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(26)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('VENUE VIRTUAL ACCOUNT', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: Colors.white54)),
                              if (_virtualAccount?['bankName'] != null)
                                Text(_virtualAccount!['bankName'].toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(_acctNumber, style: const TextStyle(fontSize: 26, letterSpacing: 1.5, fontFamily: 'monospace', fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                          const SizedBox(height: 4),
                          Text(_acctName, style: const TextStyle(fontSize: 12, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    const SizedBox(height: 16),
                    // BALANCE
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.cardBorder)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('AVAILABLE BALANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8)),
                        const SizedBox(height: 8),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('₦${_availableNgn.toStringAsFixed(2)}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.primary))),
                        const SizedBox(height: 14),
                        Wrap(spacing: 12, runSpacing: 12, children: [
                          SizedBox(
                            width: (MediaQuery.of(context).size.width - 52) / 2,
                            child: FilledButton.icon(
                              onPressed: (_submitting || !_isPaystackConfigured) ? null : _registerBank,
                              icon: const Icon(Icons.account_balance, size: 18),
                              label: const FittedBox(child: Text('Add Bank')),
                            ),
                          ),
                          SizedBox(
                            width: (MediaQuery.of(context).size.width - 52) / 2,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.accentGreen),
                              onPressed: (_submitting || !_isPaystackConfigured) ? null : _requestCashout,
                              icon: const Icon(Icons.currency_exchange, size: 18),
                              label: const FittedBox(child: Text('Cash Out')),
                            ),
                          ),
                        ]),
                        if (!_isPaystackConfigured) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Wallet actions are disabled until Paystack is configured on the backend server.',
                            style: TextStyle(fontSize: 11, color: AppColors.textLight),
                          ),
                        ],
                      ]),
                    ),
                  const SizedBox(height: 20),

                  const Text(
                    'CASHOUT HISTORY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textLight,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_cashouts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No cashouts yet.',
                        style: TextStyle(color: AppColors.textLight),
                      ),
                    )
                  else
                    ..._cashouts.map((c) {
                      final status = (c['status'] as String?) ?? 'PENDING';
                      final amtMinor = (c['amountMinor'] as num?)?.toInt() ?? 0;
                      final color = status == 'COMPLETED'
                          ? AppColors.accentGreen
                          : status == 'PENDING' || status == 'APPROVED'
                              ? AppColors.warmSand
                              : AppColors.accentRed;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '₦${(amtMinor / 100).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  Text(
                                    status,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (status == 'PENDING' || status == 'APPROVED')
                              GestureDetector(
                                onTap: _submitting
                                    ? null
                                    : () => _adminConfirmCashout(c['id']),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentGreen,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Confirm',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}