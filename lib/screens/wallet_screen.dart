import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_theme.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/widgets/shimmer.dart';

class _NigerianBankChoice {
  final String name;
  final String code;
  const _NigerianBankChoice(this.name, this.code);
}

const List<_NigerianBankChoice> _kPopularNigerianBanks = [
  _NigerianBankChoice('Access Bank', '044'),
  _NigerianBankChoice('Guaranty Trust Bank (GTBank)', '058'),
  _NigerianBankChoice('Zenith Bank', '057'),
  _NigerianBankChoice('First Bank of Nigeria', '011'),
  _NigerianBankChoice('United Bank for Africa (UBA)', '033'),
  _NigerianBankChoice('Kuda Bank', '50211'),
  _NigerianBankChoice('OPay Digital Services', '999992'),
  _NigerianBankChoice('PalmPay', '999991'),
  _NigerianBankChoice('Moniepoint MFB', '50515'),
  _NigerianBankChoice('Stanbic IBTC Bank', '221'),
  _NigerianBankChoice('Sterling Bank', '232'),
  _NigerianBankChoice('Fidelity Bank', '070'),
  _NigerianBankChoice('First City Monument Bank (FCMB)', '214'),
  _NigerianBankChoice('Wema Bank', '035'),
  _NigerianBankChoice('Union Bank of Nigeria', '032'),
  _NigerianBankChoice('Polaris Bank', '076'),
  _NigerianBankChoice('Providus Bank', '101'),
  _NigerianBankChoice('Ecobank Nigeria', '050'),
  _NigerianBankChoice('Jaiz Bank', '301'),
  _NigerianBankChoice('Taj Bank', '302'),
  _NigerianBankChoice('Other / Custom Bank Code', 'custom'),
];

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
  bool _hideBalance = true; // Hidden by default

  Map<String, dynamic>? _virtualAccount;
  Map<String, dynamic>? _balance;
  List<dynamic> _cashouts = [];
  List<dynamic> _bankAccounts = [];
  List<dynamic> _storePayments = [];
  int _selectedHistoryTab = 0; // 0: All, 1: Paystack Store Sales, 2: Cashouts
  String? _vaError;
  bool _refreshingVa = false;
  final bool _isPaystackLocked = false;

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

  Future<void> _toggleHideBalance() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _hideBalance = !_hideBalance);
    await prefs.setBool('hide_balance_preference', _hideBalance);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _hideBalance = prefs.getBool('hide_balance_preference') ?? true;
        });
      }
      var venueId = widget.venueId;
      if (venueId == 'default') {
        venueId = VenueStateService.instance.currentVenueId ?? 'default';
        if (venueId == 'default') {
          final venue = await _api.getDefaultVenue();
          venueId = venue['id']?.toString() ?? 'default';
        }
      }

      // Always ensure: the backend self-heals stale mock/PENDING rows into
      // live DVAs once real keys exist. Fall back to a plain read offline.
      // VA failures are tracked separately so the card can tell pending,
      // mock-mode, and load errors apart instead of crying KYC for all.
      // Backend error maps (4xx/5xx JSON) also surface as errors, not pending.
      String? backendErrorOf(Map<String, dynamic> m) {
        final code = (m['statusCode'] as num?)?.toInt() ?? (m['status'] as num?)?.toInt() ?? 0;
        if (m['error'] == true || code >= 400) {
          final msg = (m['message'] ?? m['error'] ?? 'Server error').toString();
          return msg.isEmpty ? 'Server error.' : msg;
        }
        return null;
      }

      Map<String, dynamic> vaData = {};
      String? vaError;
      try {
        vaData = await _api.ensureVirtualAccount(venueId);
        vaError = backendErrorOf(vaData);
        if (vaData['accountNumber'] == null && vaError == null) {
          vaData = await _api.getVirtualAccount(venueId);
          vaError = backendErrorOf(vaData);
        }
      } catch (e) {
        try {
          vaData = await _api.getVirtualAccount(venueId);
          vaError = backendErrorOf(vaData);
        } catch (_) {}
        if ((vaData['accountNumber'] as String?)?.isNotEmpty != true && vaError == null) {
          vaError = e.toString().replaceFirst('Exception: ', '');
        }
      }
      final bal = await _api.venueBalance(venueId);
      final cashoutsRaw = await _api.listCashouts(venueId);
      final cashoutsList = cashoutsRaw is List
          ? (cashoutsRaw as List<dynamic>)
          : (cashoutsRaw['data'] as List<dynamic>? ?? cashoutsRaw['cashouts'] as List<dynamic>? ?? []);

      final banksRaw = await _api.listBankAccounts(venueId);
      final banksList = banksRaw is List
          ? banksRaw
          : (banksRaw['data'] as List<dynamic>? ?? []);

      final paymentsRaw = await _api.listStorePayments(venueId);
      final paymentsList = paymentsRaw;

      if (!mounted) return;
      setState(() {
        _virtualAccount = vaData;
        _vaError = vaError;
        _balance = bal;
        _cashouts = List<dynamic>.from(cashoutsList);
        _bankAccounts = List<dynamic>.from(banksList);
        _storePayments = List<dynamic>.from(paymentsList);
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
  int get _earnedMinor => (_balance?['earnedMinor'] as num?)?.toInt() ?? 0;
  double get _earnedNgn => _earnedMinor / 100;
  int get _lockedMinor => (_balance?['lockedMinor'] as num?)?.toInt() ?? 0;
  double get _lockedNgn => _lockedMinor / 100;
  int get _cashedOutMinor => (_balance?['cashedOutMinor'] as num?)?.toInt() ?? 0;
  double get _cashedOutNgn => _cashedOutMinor / 100;

  String get _acctNumber => _virtualAccount?['accountNumber']?.toString() ?? '—';
  String get _acctName => _virtualAccount?['accountName']?.toString() ?? '—';

  bool get _isMockRow {
    final v = _virtualAccount;
    if (v == null) return false;
    final meta = v['metadata'];
    if (meta is Map && (meta['mock'] == true || meta['mock']?.toString() == 'true')) return true;
    final bank = (v['bankName']?.toString() ?? '').toLowerCase();
    return bank.contains('mock');
  }

  Future<void> _refreshDva() async {
    setState(() {
      _refreshingVa = true;
      _vaError = null;
    });
    try {
      var venueId = widget.venueId;
      if (venueId == 'default') {
        venueId = VenueStateService.instance.currentVenueId ?? 'default';
      }
      final vaData = await _api.ensureVirtualAccount(venueId);
      if (!mounted) return;
      setState(() => _virtualAccount = vaData);
    } catch (e) {
      if (!mounted) return;
      setState(() => _vaError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _refreshingVa = false);
    }
  }

  bool get _hasActiveVirtualAccount {
    if (_virtualAccount == null) return false;
    final meta = _virtualAccount?['metadata'];
    if (meta is Map && (meta['mock'] == true || meta['mock']?.toString() == 'true')) {
      return false;
    }
    final bank = (_virtualAccount?['bankName']?.toString() ?? '').toLowerCase();
    if (bank.contains('mock')) return false;
    final acct = _virtualAccount?['accountNumber']?.toString() ?? '';
    if (acct.isEmpty || acct == '—' || acct == 'PENDING') return false;
    return true;
  }

  /// Truthful DVA status card: pending, test-mode, and load-failure states
  /// each say what they are (never a blanket "KYC pending") with a retry.
  Widget _buildDvaStatusCard() {
    String badge;
    Color badgeColor;
    String title;
    String message;
    IconData icon;
    if (_vaError != null) {
      badge = 'LOAD FAILED';
      badgeColor = AppColors.accentRed;
      title = 'DIRECT BANK TRANSFER (DVA)';
      message = 'Could not load your dedicated account: $_vaError. Your Paystack setup may be fine — retry to check again.';
      icon = Icons.cloud_off_rounded;
    } else if (_isMockRow) {
      badge = 'TEST MODE';
      badgeColor = AppColors.primary;
      title = 'DIRECT BANK TRANSFER (DVA)';
      message = 'Server is running without live Paystack keys, so this is a test account. Card/USSD checkout still works in mock mode — ask your admin to configure PAYSTACK_SECRET_KEY for live settlement.';
      icon = Icons.science_outlined;
    } else {
      badge = 'PENDING ACTIVATION';
      badgeColor = const Color(0xFFD97706);
      title = 'DIRECT BANK TRANSFER (DVA)';
      message = 'Dedicated NUBAN is pending Paystack activation. Online card/USSD payments and owner bank cashouts stay active meanwhile.';
      icon = Icons.account_balance_wallet_outlined;
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.containerBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 0.8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _refreshingVa ? null : _refreshDva,
                  icon: _refreshingVa
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 15),
                  label: Text(_refreshingVa ? 'Checking...' : 'Retry now'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  /// Locked Paystack feature portrait notification card
  Widget _buildPaystackLockedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_clock_outlined, color: Color(0xFFB45309), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE68A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'FEATURE NOT AVAILABLE YET',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF92400E),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Paystack Wallet & Checkout Locked',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF78350F),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Automated Paystack wallet cashouts and online card checkout are currently locked under scheduled upgrade. Cash voucher pass sales, counter redemptions, direct bank transfers, and router hardware operations remain fully operational.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF92400E),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestCashout() async {
    if (_isPaystackLocked) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: Color(0xFFB45309)),
              SizedBox(width: 8),
              Text('Feature Not Available Yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Automated Paystack wallet cashouts and online card checkout are currently locked under scheduled upgrade. Cash voucher sales at the counter and router operations remain fully active.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    if (_bankAccounts.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.account_balance_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Bank Account Required', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'You do not have a registered settlement bank account yet. Where should Paystack send your cashout funds?\n\nPlease add your Nigerian bank account first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _registerBank();
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Bank Account'),
            ),
          ],
        ),
      );
      return;
    }

    if (_availableNgn <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No funds currently available for cashout. Available balance is ₦0.00.'),
          backgroundColor: AppColors.warmSand,
        ),
      );
      return;
    }

    final firstBank = _bankAccounts.first;
    final bankLabel = '${firstBank['accountName']} (${firstBank['accountNumber']} • ${firstBank['bankName'] ?? firstBank['bankCode']})';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final amtCtrl = TextEditingController(text: _availableNgn > 0 ? _availableNgn.toStringAsFixed(0) : '');
        final passCtrl = TextEditingController();
        bool obscurePass = true;
        String? amtError;
        String? passError;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.currency_exchange, color: AppColors.primary, size: 22),
                SizedBox(width: 8),
                Text('Cash Out Funds', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PAYOUT DESTINATION',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bankLabel,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (NGN)',
                      prefixText: '₦ ',
                      helperText: 'Available: ₦${_availableNgn.toStringAsFixed(2)} (Min ₦500)',
                      errorText: amtError,
                    ),
                    onChanged: (_) {
                      if (amtError != null) setDialogState(() => amtError = null);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscurePass,
                    decoration: InputDecoration(
                      labelText: 'Venue / Owner Password',
                      helperText: 'Required to authorize payout',
                      errorText: passError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: AppColors.textLight,
                          size: 20,
                        ),
                        onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                      ),
                    ),
                    onChanged: (_) {
                      if (passError != null) setDialogState(() => passError = null);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final rawAmt = amtCtrl.text.trim();
                  final enteredAmt = double.tryParse(rawAmt);
                  final enteredPass = passCtrl.text;
                  bool hasError = false;

                  if (rawAmt.isEmpty || enteredAmt == null || enteredAmt <= 0) {
                    setDialogState(() => amtError = 'Please enter a valid cashout amount.');
                    hasError = true;
                  } else if (enteredAmt < 500) {
                    setDialogState(() => amtError = 'Minimum cashout amount is ₦500.');
                    hasError = true;
                  } else if (enteredAmt > _availableNgn) {
                    setDialogState(() => amtError = 'Cannot exceed available balance (₦${_availableNgn.toStringAsFixed(2)}).');
                    hasError = true;
                  }

                  if (enteredPass.trim().isEmpty) {
                    setDialogState(() => passError = 'Password is required to authorize payout.');
                    hasError = true;
                  }

                  if (hasError) return;

                  Navigator.of(ctx).pop({
                    'amount': enteredAmt,
                    'password': enteredPass,
                  });
                },
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
          const SnackBar(content: Text('Missing required cashout details (amount and password).')),
        );
      }
      return;
    }

    if (amount > _availableNgn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot cash out more than available balance (₦${_availableNgn.toStringAsFixed(2)})'),
            backgroundColor: AppColors.accentRed,
          ),
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
      final res = await _api.requestCashout(
        venueId: venueId,
        amountMinor: (amount * 100).round(),
        password: password,
      );

      final cashoutId = res['id']?.toString() ?? res['cashoutId']?.toString();
      final status = res['status']?.toString();
      final reason = (res['failureReason'] ?? '').toString();
      final requiresOtp = status == 'otp' || reason.contains('OTP_REQUIRED') || res['requiresOtp'] == true;

      if (requiresOtp && cashoutId != null && mounted) {
        final otp = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final otpCtrl = TextEditingController();
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
                  SizedBox(width: 8),
                  Text('Paystack Transfer OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Paystack sent an authorization OTP to your registered phone or authenticator app. Enter it below to complete your payout:',
                    style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 4),
                    decoration: InputDecoration(
                      hintText: '••••••',
                      counterText: '',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel Payout'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(otpCtrl.text.trim()),
                  child: const Text('Authorize Transfer'),
                ),
              ],
            );
          },
        );

        if (otp != null && otp.isNotEmpty) {
          try {
            await _api.finalizeCashoutOtp(cashoutId: cashoutId, otp: otp);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ OTP verified — payout completed and funds sent!'),
                backgroundColor: AppColors.accentGreen,
              ),
            );
          } catch (otpErr) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('OTP authorization failed: $otpErr'),
                backgroundColor: AppColors.accentRed,
              ),
            );
          }
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cashout pending OTP confirmation. You can retry from wallet.'),
              backgroundColor: AppColors.warmSand,
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cashout complete — funds on the way.'),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cashout failed: $e'), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _registerBank() async {
    if (_isPaystackLocked) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: Color(0xFFB45309)),
              SizedBox(width: 8),
              Text('Feature Not Available Yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Automated Paystack bank registration and wallet cashouts are currently locked under scheduled upgrade. Cash voucher sales at the counter and router operations remain fully active.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    _nameCtrl.clear();
    _acctCtrl.clear();
    _bankCtrl.clear();

    final form = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        _NigerianBankChoice? selectedBank = _kPopularNigerianBanks.first;
        String? nameError;
        String? acctError;
        String? bankError;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.account_balance, color: AppColors.primary, size: 22),
                SizedBox(width: 8),
                Text('Add Payout Bank', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Register a 10-digit Nigerian NUBAN account to receive instant Paystack automated payouts.',
                    style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<_NigerianBankChoice>(
                    initialValue: selectedBank,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Select Bank',
                      errorText: bankError,
                    ),
                    items: _kPopularNigerianBanks.map((b) {
                      return DropdownMenuItem<_NigerianBankChoice>(
                        value: b,
                        child: Text(
                          b.name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedBank = val;
                        bankError = null;
                      });
                    },
                  ),
                  if (selectedBank?.code == 'custom') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bankCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Bank Code (e.g. 058)',
                        helperText: 'Enter 3-to-6 digit CBN bank code',
                        errorText: bankError,
                      ),
                      onChanged: (_) {
                        if (bankError != null) setDialogState(() => bankError = null);
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _acctCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Account Number',
                      hintText: '10 digits (NUBAN)',
                      helperText: 'Must be exactly 10 digits',
                      errorText: acctError,
                    ),
                    onChanged: (_) {
                      if (acctError != null) setDialogState(() => acctError = null);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Account Holder Name',
                      hintText: 'e.g. John Doe / Venue Name',
                      helperText: 'Name as registered on the bank account',
                      errorText: nameError,
                    ),
                    onChanged: (_) {
                      if (nameError != null) setDialogState(() => nameError = null);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = _nameCtrl.text.trim();
                  final acct = _acctCtrl.text.trim();
                  bool hasError = false;

                  if (selectedBank == null) {
                    setDialogState(() => bankError = 'Please select a bank.');
                    hasError = true;
                  } else if (selectedBank!.code == 'custom') {
                    final code = _bankCtrl.text.trim();
                    if (code.isEmpty) {
                      setDialogState(() => bankError = 'Enter a valid bank code.');
                      hasError = true;
                    } else if (code.length < 3 || !RegExp(r'^\d{3,6}$').hasMatch(code)) {
                      setDialogState(() => bankError = 'Bank code must be 3 to 6 digits.');
                      hasError = true;
                    }
                  }

                  if (acct.isEmpty) {
                    setDialogState(() => acctError = 'Account number is required.');
                    hasError = true;
                  } else if (acct.length != 10 || !RegExp(r'^\d{10}$').hasMatch(acct)) {
                    setDialogState(() => acctError = 'Account number must be exactly 10 digits.');
                    hasError = true;
                  }

                  if (name.isEmpty) {
                    setDialogState(() => nameError = 'Account holder name is required.');
                    hasError = true;
                  }

                  if (hasError) return;

                  final bankCode = selectedBank!.code == 'custom' ? _bankCtrl.text.trim() : selectedBank!.code;
                  final bankName = selectedBank!.code == 'custom' ? 'Custom Bank ($bankCode)' : selectedBank!.name;

                  Navigator.of(ctx).pop({
                    'name': name,
                    'acct': acct,
                    'bankCode': bankCode,
                    'bankName': bankName,
                  });
                },
                child: const Text('Save Bank Account'),
              ),
            ],
          ),
        );
      },
    );

    if (form == null) return;
    final name = form['name'] ?? '';
    final acct = form['acct'] ?? '';
    final bankCode = form['bankCode'] ?? '';
    final bankName = form['bankName'];

    if (name.isEmpty || acct.isEmpty || bankCode.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Missing required bank details. Please check name, 10-digit account number, and bank.'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
      return;
    }

    var venueId = widget.venueId;
    if (venueId == 'default') {
      try {
        final venue = await _api.getDefaultVenue();
        venueId = venue['id']?.toString() ?? venueId;
      } catch (_) {}
    }

    setState(() => _submitting = true);
    try {
      await _api.registerBankAccount(
        venueId: venueId,
        accountName: name,
        accountNumber: acct,
        bankCode: bankCode,
        bankName: bankName,
      );
      _nameCtrl.clear();
      _acctCtrl.clear();
      _bankCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $bankName ($acct) registered for payouts.'),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().replaceFirst('Exception: ', '');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.accentRed),
                SizedBox(width: 8),
                Text('Bank Registration Failed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Could not register this account with Paystack:\n\n$errStr\n\nPlease ensure the 10-digit account number and bank match the registered account name.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _adminConfirmCashout(String id) async {
    final pass = await _askAdminPassword();
    if (pass == null || pass.trim().isEmpty) return;
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
        String? passError;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Confirm Cashout'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter your password to authorise this payout.'),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    errorText: passError,
                  ),
                  onChanged: (_) {
                    if (passError != null) setDialogState(() => passError = null);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (ctrl.text.trim().isEmpty) {
                    setDialogState(() => passError = 'Password is required.');
                    return;
                  }
                  Navigator.of(ctx).pop(ctrl.text);
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
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
                    // PAYSTACK FEATURES LOCKED NOTIFICATION
                    if (_isPaystackLocked) ...[
                      _buildPaystackLockedCard(),
                      const SizedBox(height: 16),
                    ],
                    // VIRTUAL ACCOUNT / WALLET STATUS
                    if (_hasActiveVirtualAccount)
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
                      )
                    else
                      _buildDvaStatusCard(),
                    const SizedBox(height: 16),
                    // BALANCE
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.cardBorder)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(
                          children: [
                            const Text('AVAILABLE BALANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8)),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _toggleHideBalance,
                              child: Icon(
                                _hideBalance ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 16,
                                color: AppColors.textLight,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PAYSTACK STORE TRANSACTIONS • READY FOR CASHOUT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textLight,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _hideBalance ? '₦ • • • • • •' : '₦${_availableNgn.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildMiniStat('Paystack Sales', _hideBalance ? '₦ •••' : '₦${_earnedNgn.toStringAsFixed(2)}'),
                            _buildMiniStat('Pending Payouts', _hideBalance ? '₦ •••' : '₦${_lockedNgn.toStringAsFixed(2)}'),
                            _buildMiniStat('Already Paid', _hideBalance ? '₦ •••' : '₦${_cashedOutNgn.toStringAsFixed(2)}'),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Wrap(spacing: 12, runSpacing: 12, children: [
                          SizedBox(
                            width: (MediaQuery.of(context).size.width - 52) / 2,
                            child: FilledButton.icon(
                              onPressed: _submitting ? null : _registerBank,
                              icon: const Icon(Icons.account_balance, size: 18),
                              label: const FittedBox(child: Text('Add Bank')),
                            ),
                          ),
                          SizedBox(
                            width: (MediaQuery.of(context).size.width - 52) / 2,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.accentGreen),
                              onPressed: _submitting ? null : _requestCashout,
                              icon: const Icon(Icons.currency_exchange, size: 18),
                              label: const FittedBox(child: Text('Cash Out')),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // REGISTERED PAYOUT BANK ACCOUNTS
                    const Text(
                      'PAYOUT DESTINATION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textLight,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_bankAccounts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.containerBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: AppColors.textLight),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'No payout bank registered. Tap "Add Bank" to connect your bank account.',
                                style: TextStyle(fontSize: 12, color: AppColors.textLight),
                              ),
                            ),
                            TextButton(
                              onPressed: _registerBank,
                              child: const Text('Add Bank', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._bankAccounts.map((b) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentGreen.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.verified_outlined, color: AppColors.accentGreen, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b['accountName']?.toString() ?? 'Bank Account',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${b['accountNumber']} • ${b['bankName'] ?? b['bankCode'] ?? 'Bank'}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textLight, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentGreen.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Active',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentGreen),
                                  ),
                                ),
                              ],
                            ),
                          )),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TRANSACTION HISTORY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textLight,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        '${_storePayments.length} Sales • ${_cashouts.length} Cashouts',
                        style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Segmented Filter
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        _buildFilterTab(0, 'All'),
                        _buildFilterTab(1, 'Paystack Sales (${_storePayments.length})'),
                        _buildFilterTab(2, 'Cashouts (${_cashouts.length})'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (_selectedHistoryTab == 0 || _selectedHistoryTab == 1) ...[
                    if (_storePayments.isNotEmpty) ...[
                      const Text(
                        'PAYSTACK STORE PAYMENTS (INFLOW)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentGreen,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._storePayments.map((p) {
                        final amtNgn = (p['amountNGN'] as num?)?.toDouble() ?? (((p['amountMinor'] as num?)?.toDouble() ?? 0) / 100);
                        final plan = p['planName']?.toString() ?? 'Wi-Fi Pass';
                        final mac = p['customerRef']?.toString() ?? '';
                        final dateStr = p['paidAt'] ?? p['createdAt'];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.accentGreen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.arrow_downward_rounded, color: AppColors.accentGreen, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            plan,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '+₦${amtNgn.toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.accentGreen),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('Paystack', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                        ),
                                        const SizedBox(width: 6),
                                        if (mac.isNotEmpty) ...[
                                          Text(mac, style: const TextStyle(fontSize: 11, color: AppColors.textLight, fontFamily: 'monospace')),
                                          const SizedBox(width: 6),
                                        ],
                                        Expanded(
                                          child: Text(
                                            _formatDate(dateStr),
                                            style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                                            textAlign: TextAlign.end,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                    ] else if (_selectedHistoryTab == 1) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No Paystack guest transactions found yet.',
                            style: TextStyle(color: AppColors.textLight, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ],

                  if (_selectedHistoryTab == 0 || _selectedHistoryTab == 2) ...[
                    if (_cashouts.isNotEmpty) ...[
                      const Text(
                        'CASHOUTS TO BANK (OUTFLOW)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textLight,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._cashouts.map((c) {
                        final status = (c['status'] as String?) ?? 'PENDING';
                        final amtMinor = (c['amountMinor'] as num?)?.toInt() ?? 0;
                        final color = status == 'COMPLETED'
                            ? AppColors.accentGreen
                            : status == 'PENDING' || status == 'APPROVED'
                                ? AppColors.warmSand
                                : AppColors.accentRed;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.arrow_upward_rounded, color: color, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Payout (${status.toLowerCase()})',
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                                          ),
                                        ),
                                        Text(
                                          '-₦${(amtMinor / 100).toStringAsFixed(2)}',
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      c['bankAccount'] != null
                                          ? '${c['bankAccount']['bankName'] ?? 'Bank'} • ${c['bankAccount']['accountNumber']}'
                                          : status,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                                    ),
                                  ],
                                ),
                              ),
                              if (status == 'PENDING' || status == 'APPROVED')
                                GestureDetector(
                                  onTap: _submitting ? null : () => _adminConfirmCashout(c['id']),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(color: AppColors.accentGreen, borderRadius: BorderRadius.circular(8)),
                                    child: const Text('Confirm', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ] else if (_selectedHistoryTab == 2) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No cashout requests found.',
                            style: TextStyle(color: AppColors.textLight, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ],

                  if (_selectedHistoryTab == 0 && _storePayments.isEmpty && _cashouts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No transactions recorded yet.',
                          style: TextStyle(color: AppColors.textLight, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterTab(int index, String label) {
    final active = _selectedHistoryTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedHistoryTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))] : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? AppColors.primary : AppColors.textLight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  String _formatDate(dynamic iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.toString();
    }
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}