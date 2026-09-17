import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/router_discovery_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/plan_configurator.dart';
import '../core/widgets/qr_code_widget.dart';
import '../core/services/voucher_history_service.dart';
import 'voucher_history_sheet.dart';

class SellPassScreen extends StatefulWidget {
  const SellPassScreen({super.key});

  @override
  State<SellPassScreen> createState() => _SellPassScreenState();
}

class _SellPassScreenState extends State<SellPassScreen> {
  int _selectedPlanIndex = 0;
  bool _isGenerating = false;
  String? _generatedCode;
  String? _generatedPassword;
  bool _soldGenerated = false;
  bool? _provisioned;
  String? _provisionDetail;
  bool _retryingProvision = false;
  bool _showCustomSettings = false;
  final _prefixCtrl = TextEditingController(text: '');
  final _passPrefixCtrl = TextEditingController(text: '');
  int _codeLength = 6;
  String _charPattern = 'Numbers Only'; // 'Numbers Only', 'Alphanumeric', 'Uppercase Only'
  String _userMode = 'Voucher Code'; // 'Voucher Code', 'Username & Password'
  int _passLength = 4;
  String _passPattern = 'Numbers Only'; // 'Numbers Only', 'Alphanumeric', 'Uppercase Only', 'Same as Username'

  bool _isPrinting = false;
  String? _directProvisionMode; // 'local', 'tunnel', or null
  bool _directProvisionAttempted = false;

  List<Map<String, dynamic>> _plans = [];
  bool _loadingPlans = true;
  String? _venueId;
  String? _venueName;
  String? _venueSlug;

  @override
  void initState() {
    super.initState();
    VenueStateService.instance.plansNotifier.addListener(_onPlansChanged);
    VenueStateService.instance.venueNotifier.addListener(_onVenueChanged);
    _onVenueChanged();
    _onPlansChanged();
    if (VenueStateService.instance.currentPlans.isEmpty) {
      _loadPlans();
    }
  }

  @override
  void dispose() {
    VenueStateService.instance.plansNotifier.removeListener(_onPlansChanged);
    VenueStateService.instance.venueNotifier.removeListener(_onVenueChanged);
    _prefixCtrl.dispose();
    _passPrefixCtrl.dispose();
    super.dispose();
  }

  void _onVenueChanged() {
    final v = VenueStateService.instance.currentVenue;
    if (v != null && mounted) {
      setState(() {
        _venueId = v['id']?.toString() ?? _venueId;
        _venueName = v['name']?.toString() ?? _venueName ?? 'WavePass Venue';
        _venueSlug = v['slug']?.toString() ?? _venueSlug ?? 'venue';
      });
    }
  }

  void _onPlansChanged() {
    final rawPlans = VenueStateService.instance.currentPlans;
    if (mounted) {
      setState(() {
        _plans = rawPlans.map((p) {
          final priceMinor = (p['priceMinor'] as num?)?.toInt() ?? 0;
          final durationSec = (p['durationSeconds'] as num?)?.toInt() ?? 3600;
          final durationStr = durationSec < 3600
              ? '${durationSec ~/ 60} Mins'
              : durationSec < 86400
                  ? '${durationSec ~/ 3600} Hours'
                  : '${durationSec ~/ 86400} Days';
          final dataLimit = p['dataLimitBytes'];
          final dataStr = dataLimit == null
              ? 'Unlimited'
              : '${((dataLimit as num) / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
          return {
            'id': p['id']?.toString() ?? '',
            'title': p['name']?.toString() ?? 'Pass',
            'price': '₦${priceMinor ~/ 100}',
            'priceMinor': priceMinor,
            'duration': durationStr,
            'durationSeconds': durationSec,
            'subtitle': p['description']?.toString() ?? 'Custom plan',
            'data': dataStr,
            'speed': p['rateLimit']?.toString() ?? '10 Mbps',
            'devices': '${p['simultaneousDevices'] ?? 1} device',
          };
        }).toList();
        if (_selectedPlanIndex >= _plans.length) {
          _selectedPlanIndex = 0;
        }
        _loadingPlans = false;
      });
    }
  }

  Future<void> _loadPlans() async {
    setState(() => _loadingPlans = true);
    try {
      if (VenueStateService.instance.currentVenue == null) {
        await VenueStateService.instance.refreshVenue();
      } else {
        await VenueStateService.instance.refreshPlans();
      }
    } catch (e) {
      debugPrint('Error loading plans: $e');
    } finally {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  String _generateSegment(int length, String pattern) {
    String charset;
    if (pattern == 'Numbers Only') {
      charset = '0123456789';
    } else if (pattern == 'Uppercase Only' || pattern == 'Letters Only') {
      charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    } else {
      // Combination with letters without dashes or confusing characters
      charset = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    }
    final rnd = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => charset.codeUnitAt(rnd.nextInt(charset.length))),
    );
  }

  String _randomCode() {
    final prefix = _prefixCtrl.text.trim().toUpperCase().replaceAll('-', '');
    final seg = _generateSegment(_codeLength, _charPattern);
    return '$prefix$seg'.replaceAll('-', '');
  }

  Widget _miniChip(String text, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: AppColors.textLight), const SizedBox(width: 4), Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary))]),
      );

  void _handleGenerate() async {
    if (_plans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one pricing plan first.')),
      );
      return;
    }
    if (_selectedPlanIndex >= _plans.length) {
      _selectedPlanIndex = 0;
    }

    setState(() {
      _isGenerating = true;
    });

    final selectedPlan = _plans[_selectedPlanIndex];
    final planId = selectedPlan['id'] as String?;

    // Custom format: numbers only on default or numbers+letters without dashes
    final code = _randomCode().replaceAll('-', '');

    String password = code;
    if (_userMode == 'Username & Password') {
      if (_passPattern == 'Same as Username') {
        password = code;
      } else {
        final passSeg = _generateSegment(_passLength, _passPattern);
        final passPrefix = _passPrefixCtrl.text.trim().replaceAll('-', '');
        password = '$passPrefix$passSeg'.replaceAll('-', '');
      }
    }

    // 1. Upload the exact code to cloud so records match app + router.
    bool cloudOk = false;
    if (_venueId != null && planId != null && planId.isNotEmpty) {
      try {
        final res = await WavePassApi.instance.uploadVoucherBatch(
          venueId: _venueId!,
          planId: planId,
          codes: [code],
        ).timeout(const Duration(seconds: 8));
        final created = (res['created'] as num?)?.toInt() ?? 0;
        cloudOk = created > 0;
      } catch (e) {
        debugPrint('Cloud voucher upload failed: $e');
      }
    }

    // 2. Provision directly onto router hardware (LAN Direct / Cloud Tunnel)
    String? directMode;
    try {
      final durationSec = (selectedPlan['durationSeconds'] as num?)?.toInt() ?? 3600;
      final directRes = await RouterDiscoveryService.provisionVoucherDualRoute(
        code: code,
        pass: password,
        profile: RouterDiscoveryService.profileForDuration(durationSec),
        sessionTimeoutSeconds: durationSec,
      );
      if (directRes['success'] == true) {
        directMode = directRes['mode']?.toString();
      }
    } catch (e) {
      debugPrint('Direct router provisioning attempt: $e');
    }

    // 3. Verify before presenting: router-pushed OR cloud-confirmed.
    // Never present an unprovisioned code as valid.
    final provisioned = directMode != null || cloudOk;

    if (!mounted) return;

    // Record voucher in local history
    final durationSec = (selectedPlan['durationSeconds'] as num?)?.toInt() ?? 3600;
    VoucherHistoryService.instance.recordVoucher(
      code: code,
      password: password,
      planTitle: selectedPlan['title']?.toString() ?? 'Pass',
      price: selectedPlan['price']?.toString() ?? '₦0',
      durationSeconds: durationSec,
      directMode: directMode,
      source: 'pos',
      provisioned: provisioned,
    );

    setState(() {
      _isGenerating = false;
      _generatedCode = code;
      _generatedPassword = password;
      _soldGenerated = false;
      _provisioned = provisioned;
      _provisionDetail = directMode != null
          ? "Live on router (${directMode == 'local' ? 'LAN Direct' : 'Tunnel'})${cloudOk ? ' + cloud' : ''}"
          : cloudOk
              ? 'Confirmed in cloud — router will sync'
              : 'Not provisioned anywhere';
      _directProvisionMode = directMode;
      _directProvisionAttempted = true;
    });

    if (!provisioned && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not provision this code on router or cloud. Tap Retry — do not hand it out yet.'),
          backgroundColor: AppColors.accentRed,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    // Auto-print receipt if enabled in printer settings
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('wavepass_auto_print_receipts') ?? true) {
        _handlePrint();
      }
    } catch (_) {}
  }

  /// Re-runs router + cloud provisioning for the currently displayed code.
  Future<void> _retryProvision() async {
    final code = _generatedCode;
    if (code == null || _plans.isEmpty) return;
    setState(() => _retryingProvision = true);
    try {
      final selectedPlan = (_selectedPlanIndex < _plans.length) ? _plans[_selectedPlanIndex] : _plans.first;
      final planId = selectedPlan['id'] as String?;
      final durationSec = (selectedPlan['durationSeconds'] as num?)?.toInt() ?? 3600;

      String? directMode;
      try {
        final directRes = await RouterDiscoveryService.provisionVoucherDualRoute(
          code: code,
          pass: _generatedPassword ?? code,
          profile: RouterDiscoveryService.profileForDuration(durationSec),
          sessionTimeoutSeconds: durationSec,
        );
        if (directRes['success'] == true) directMode = directRes['mode']?.toString();
      } catch (e) {
        debugPrint('Retry router provisioning: $e');
      }

      bool cloudOk = false;
      if (_venueId != null && planId != null && planId.isNotEmpty) {
        try {
          final res = await WavePassApi.instance.uploadVoucherBatch(
            venueId: _venueId!,
            planId: planId,
            codes: [code],
          ).timeout(const Duration(seconds: 8));
          cloudOk = ((res['created'] as num?)?.toInt() ?? 0) > 0;
        } catch (e) {
          debugPrint('Retry cloud upload: $e');
        }
      }

      final provisioned = directMode != null || cloudOk;
      await VoucherHistoryService.instance.updateProvisioned(code, provisioned, directMode: directMode);
      if (!mounted) return;
      setState(() {
        _provisioned = provisioned;
        _provisionDetail = directMode != null
            ? "Live on router (${directMode == 'local' ? 'LAN Direct' : 'Tunnel'})${cloudOk ? ' + cloud' : ''}"
            : cloudOk
                ? 'Confirmed in cloud — router will sync'
                : 'Not provisioned anywhere';
        if (directMode != null) _directProvisionMode = directMode;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provisioned ? 'Code provisioned successfully!' : 'Still not provisioned — check router connection and backend.'),
            backgroundColor: provisioned ? AppColors.accentGreen : AppColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _retryingProvision = false);
    }
  }

  /// Thermal-style receipt preview: exactly what the Bluetooth print outputs.
  void _showPrintPreview() {
    if (_generatedCode == null || _plans.isEmpty) return;
    final selectedPlan = (_selectedPlanIndex < _plans.length) ? _plans[_selectedPlanIndex] : _plans.first;
    final isDual = _generatedPassword != null && _generatedPassword != _generatedCode;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text("Receipt Preview", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
              child: Column(
                children: [
                  Text((_venueName ?? 'WavePass Venue').toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  Text('${_venueSlug ?? 'venue'}.nexawavepass.com', style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
                  const Divider(height: 20),
                  Text(selectedPlan['title']?.toString() ?? 'Pass', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(selectedPlan['price']?.toString() ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(_generatedCode!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'monospace', letterSpacing: 2)),
                  if (isDual) Text('PIN: $_generatedPassword', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                  const Divider(height: 20),
                  const Text('Scan to connect — valid per plan duration', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _handlePrint();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.print, size: 18),
                label: const Text("Print Receipt"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePrint() async {
    if (_generatedCode == null || _plans.isEmpty) return;    final selectedPlan = (_selectedPlanIndex < _plans.length) ? _plans[_selectedPlanIndex] : _plans.first;
    setState(() => _isPrinting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final width = prefs.getInt('wavepass_printer_paper_width') ?? 58;
      final format = width == 80 ? PdfPageFormat.roll80 : PdfPageFormat.roll57;

      final directLoginUrl = 'http://192.168.88.1/login?username=$_generatedCode&password=${_generatedPassword ?? _generatedCode}';
      final isDual = _generatedPassword != null && _generatedPassword != _generatedCode;

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(10),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text('WAVEPASS WI-FI', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(_venueName ?? 'Guest Access', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              if (isDual) ...[
                pw.Text('USERNAME:', style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 2),
                pw.Text(_generatedCode!, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                pw.SizedBox(height: 4),
                pw.Text('PASSWORD / PIN:', style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 2),
                pw.Text(_generatedPassword!, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
              ] else ...[
                pw.Text('PASSCODE:', style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 2),
                pw.Text(_generatedCode!, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
              ],
              pw.SizedBox(height: 6),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: directLoginUrl,
                width: width == 80 ? 75 : 60,
                height: width == 80 ? 75 : 60,
              ),
              pw.SizedBox(height: 3),
              pw.Text('Scan QR to Connect Instantly', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Plan: ${selectedPlan['title']}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Duration: ${selectedPlan['duration']} • Data: ${selectedPlan['data']}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Price: ${selectedPlan['price']}', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Text('Connect to Wi-Fi • Or enter code at 192.168.88.1 / ${_venueSlug ?? 'venue'}.nexawavepass.com', style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
              pw.Text(DateTime.now().toString().split('.')[0], style: const pw.TextStyle(fontSize: 7)),
            ],
          ),
        ),
      );

      final savedUrl = prefs.getString('wavepass_selected_printer_url');
      if (savedUrl != null) {
        final printers = await Printing.listPrinters();
        final matched = printers.where((p) => p.url == savedUrl).firstOrNull;
        if (matched != null) {
          final bytes = await doc.save();
          await Printing.directPrintPdf(printer: matched, onLayout: (_) async => bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Receipt printed to ${matched.name}"), backgroundColor: AppColors.accentGreen),
            );
          }
          return;
        }
      }

      await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Pass_$_generatedCode');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Receipt print job sent to printer spooler."),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Print error: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text("Sell a Cash Pass", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: AppColors.primary),
            tooltip: 'Pass History',
            onPressed: () => VoucherHistorySheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.primary),
            tooltip: 'Customize plan',
            onPressed: () async {
              final ok = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PlanConfiguratorSheet(),
              );
              if (ok == true) _loadPlans();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset + 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_generatedCode == null) ...[
              // Customization Toggle
              InkWell(
                onTap: () => setState(() => _showCustomSettings = !_showCustomSettings),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.containerBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.tune_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "Credentials: $_userMode ($_codeLength chars, $_charPattern)",
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _showCustomSettings ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showCustomSettings) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.containerBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                      isExpanded: true,
                        initialValue: _userMode,
                        decoration: const InputDecoration(labelText: 'Generation Mode', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'Voucher Code', child: Text('Voucher (User = Pass)')),
                          DropdownMenuItem(value: 'Username & Password', child: Text('Username & Password')),
                        ],
                        onChanged: (val) => setState(() => _userMode = val ?? 'Voucher Code'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _prefixCtrl,
                              decoration: const InputDecoration(labelText: 'Prefix', border: OutlineInputBorder(), hintText: 'Optional'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int>(
                      isExpanded: true,
                              initialValue: _codeLength,
                              decoration: const InputDecoration(labelText: 'Length', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 4, child: Text('4 chars')),
                                DropdownMenuItem(value: 6, child: Text('6 chars')),
                                DropdownMenuItem(value: 8, child: Text('8 chars')),
                                DropdownMenuItem(value: 10, child: Text('10 chars')),
                              ],
                              onChanged: (val) => setState(() => _codeLength = val ?? 6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                      isExpanded: true,
                              initialValue: _charPattern,
                              decoration: const InputDecoration(labelText: 'Pattern', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'Numbers Only', child: Text('Numbers (0-9)')),
                                DropdownMenuItem(value: 'Alphanumeric', child: Text('Alpha-Num')),
                                DropdownMenuItem(value: 'Uppercase Only', child: Text('Letters')),
                              ],
                              onChanged: (val) => setState(() => _charPattern = val ?? 'Numbers Only'),
                            ),
                          ),
                        ],
                      ),
                      if (_userMode == 'Username & Password') ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _passPrefixCtrl,
                                decoration: const InputDecoration(labelText: 'PIN Prefix', border: OutlineInputBorder(), hintText: 'Optional'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<int>(
                      isExpanded: true,
                                initialValue: _passLength,
                                decoration: const InputDecoration(labelText: 'PIN Length', border: OutlineInputBorder()),
                                items: const [
                                  DropdownMenuItem(value: 4, child: Text('4 chars')),
                                  DropdownMenuItem(value: 6, child: Text('6 chars')),
                                  DropdownMenuItem(value: 8, child: Text('8 chars')),
                                  DropdownMenuItem(value: 10, child: Text('10 chars')),
                                ],
                                onChanged: (val) => setState(() => _passLength = val ?? 4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: DropdownButtonFormField<String>(
                      isExpanded: true,
                                initialValue: _passPattern,
                                decoration: const InputDecoration(labelText: 'PIN Pattern', border: OutlineInputBorder()),
                                items: const [
                                  DropdownMenuItem(value: 'Numbers Only', child: Text('Numbers')),
                                  DropdownMenuItem(value: 'Alphanumeric', child: Text('Alpha-Num')),
                                  DropdownMenuItem(value: 'Uppercase Only', child: Text('Letters')),
                                  DropdownMenuItem(value: 'Same as Username', child: Text('Same')),
                                ],
                                onChanged: (val) => setState(() => _passPattern = val ?? 'Numbers Only'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      "Select a plan for customer paying cash:",
                      style: TextStyle(fontSize: 13, color: AppColors.textLight),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const PlanConfiguratorSheet(),
                      );
                      if (ok == true) _loadPlans();
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Plan', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadingPlans)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_plans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.containerBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 32, color: AppColors.textLight),
                      const SizedBox(height: 8),
                      const Text('No pricing plans found', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      const SizedBox(height: 4),
                      const Text('Add your first pass manually — duration or per-GB.', style: TextStyle(fontSize: 11, color: AppColors.textLight), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final ok = await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const PlanConfiguratorSheet(),
                          );
                          if (ok == true) _loadPlans();
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Create First Plan'),
                      ),
                    ],
                  ),
                )
              else
                // Plan Cards List
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _plans.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final plan = _plans[index];
                    final isSelected = _selectedPlanIndex == index;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedPlanIndex = index;
                        });
                      },
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.containerBg : AppColors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.cardBorder,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : AppColors.textLight,
                                  width: 2,
                                ),
                                color: isSelected ? AppColors.primary : Colors.transparent,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    plan['title'],
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(plan['subtitle'], style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 6, runSpacing: 6, children: [
                                    _miniChip(plan['duration'], Icons.schedule_rounded),
                                    _miniChip(plan['data'], Icons.storage_rounded),
                                    _miniChip(plan['speed'], Icons.speed_rounded),
                                    _miniChip(plan['devices'], Icons.devices_rounded),
                                  ]),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    plan['price'],
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                                  onPressed: () => showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => PlanConfiguratorSheet(existing: {
                                      'id': plan['id'],
                                      'name': plan['title'],
                                      'priceMinor': plan['priceMinor'] ?? 20000,
                                      'durationSeconds': plan['durationSeconds'] ?? 3600,
                                      'dataLimitBytes': plan['data'] == 'Unlimited' ? null : 1024 * 1024 * 1024,
                                      'rateLimit': plan['speed'],
                                      'simultaneousDevices': 1,
                                    }),
                                  ),
                                  tooltip: 'Edit plan',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: (_isGenerating || _plans.isEmpty) ? null : _handleGenerate,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
                  child: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(_plans.isEmpty ? "Add a Plan to Sell" : "Generate Pass Code"),
                ),
              ),
            ] else ...[
              // ─── RECEIPT VOUCHER CARD ───
              Builder(
                builder: (context) {
                  final plan = (_plans.isNotEmpty && _selectedPlanIndex < _plans.length)
                      ? _plans[_selectedPlanIndex]
                      : {'title': 'Wi-Fi Pass', 'duration': '1 Hour', 'data': 'Unlimited', 'speed': '10 Mbps'};
                  final isUnlimited = plan['data'] == 'Unlimited';

                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.wifi, color: AppColors.primary, size: 36),
                        const SizedBox(height: 12),
                        const Text(
                          "WavePass Wi-Fi Access",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(plan['title'], style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
                        const SizedBox(height: 8),
                        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                          _miniChip(plan['duration'], Icons.schedule_rounded),
                          _miniChip(plan['data'], Icons.storage_rounded),
                          _miniChip(plan['speed'], Icons.speed_rounded),
                        ]),
                        const SizedBox(height: 16),
                        // Data exhaustion ring
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder)),
                          child: Row(children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: Stack(alignment: Alignment.center, children: [
                                CircularProgressIndicator(
                                  value: isUnlimited ? 1 : 0,
                                  strokeWidth: 3,
                                  backgroundColor: AppColors.containerBg,
                                  valueColor: AlwaysStoppedAnimation<Color>(isUnlimited ? AppColors.accentGreen : AppColors.primary),
                                ),
                                Icon(isUnlimited ? Icons.all_inclusive_rounded : Icons.storage_rounded, size: 14, color: AppColors.primary),
                              ]),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(isUnlimited ? 'Unlimited data' : '${plan['data']} • 0% used', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                              const Text('Fresh voucher — 100% available', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                            ])),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.accentGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentGreen, letterSpacing: 0.5))),
                          ]),
                        ),
                        const SizedBox(height: 20),

                        // Big code container
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Column(
                            children: [
                              if (_generatedPassword != null && _generatedPassword != _generatedCode) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "USERNAME & PIN CREDENTIALS",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textLight,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: "Username: $_generatedCode\nPIN: $_generatedPassword"));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Copied Username & PIN to clipboard"), duration: Duration(seconds: 1)),
                                        );
                                      },
                                      icon: const Icon(Icons.copy_all_rounded, size: 14),
                                      label: const Text("Copy Both", style: TextStyle(fontSize: 11)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(10)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("Username", style: TextStyle(fontSize: 10, color: AppColors.textLight, fontWeight: FontWeight.w700)),
                                          Text(
                                            _generatedCode!,
                                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'monospace', color: AppColors.accentRed),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textLight),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: _generatedCode!));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Copied username $_generatedCode"), duration: const Duration(seconds: 1)),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(10)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("Password / PIN", style: TextStyle(fontSize: 10, color: AppColors.textLight, fontWeight: FontWeight.w700)),
                                          Text(
                                            _generatedPassword!,
                                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'monospace', color: AppColors.primary),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textLight),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: _generatedPassword!));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Copied PIN $_generatedPassword"), duration: const Duration(seconds: 1)),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                const Text(
                                  "CUSTOMER VOUCHER CODE",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textLight,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _generatedCode!,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace',
                                      color: AppColors.accentRed,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                              if (_directProvisionAttempted) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (_directProvisionMode != null)
                                        ? AppColors.accentGreen.withValues(alpha: 0.12)
                                        : AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _directProvisionMode != null ? Icons.check_circle_rounded : Icons.cloud_done_rounded,
                                        size: 13,
                                        color: _directProvisionMode != null ? AppColors.accentGreen : AppColors.primary,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        _directProvisionMode == 'local'
                                            ? 'Live on Router Hardware (LAN Direct)'
                                            : (_directProvisionMode == 'tunnel'
                                                ? 'Live on Router Hardware (Cloud Tunnel)'
                                                : 'Queued for Cloud Sync'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _directProvisionMode != null ? AppColors.accentGreen : AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Direct on-screen QR code for customer to login directly to router
                        Center(
                          child: QrCodeWidget(
                            data: 'http://192.168.88.1/login?username=$_generatedCode&password=${_generatedPassword ?? _generatedCode}',
                            size: 130,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Scan QR to Connect Directly to Router",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Or connect to Wi-Fi and enter code at 192.168.88.1 or ${_venueSlug ?? 'venue'}.nexawavepass.com.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, color: AppColors.textLight, height: 1.3),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Provision status: never hand out a code that landed nowhere
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (_provisioned ?? false)
                      ? AppColors.accentGreen.withValues(alpha: 0.12)
                      : AppColors.accentRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (_provisioned ?? false)
                        ? AppColors.accentGreen.withValues(alpha: 0.4)
                        : AppColors.accentRed.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      (_provisioned ?? false) ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                      size: 18,
                      color: (_provisioned ?? false) ? AppColors.accentGreen : AppColors.accentRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (_provisioned ?? false)
                            ? 'Provisioned — ${_provisionDetail ?? ''}'
                            : 'Not provisioned — ${_provisionDetail ?? 'tap Retry below'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: (_provisioned ?? false) ? AppColors.accentGreen : AppColors.accentRed,
                        ),
                      ),
                    ),
                    if (!(_provisioned ?? false))
                      TextButton(
                        onPressed: _retryingProvision ? null : _retryProvision,
                        child: Text(
                          _retryingProvision ? 'Retrying...' : 'Retry',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Sold marker: staff distinguish handed-out passes from displayed ones
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _soldGenerated ? AppColors.accentGreen.withValues(alpha: 0.12) : AppColors.containerBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _soldGenerated ? AppColors.accentGreen.withValues(alpha: 0.4) : AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      _soldGenerated ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: _soldGenerated ? AppColors.accentGreen : AppColors.textLight,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _soldGenerated ? 'Marked as SOLD' : 'Not yet sold',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _soldGenerated ? AppColors.accentGreen : AppColors.textLight),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (_generatedCode == null) return;
                        final next = !_soldGenerated;
                        final ok = await VoucherHistoryService.instance.markSold(_generatedCode!, next);
                        if (ok && mounted) setState(() => _soldGenerated = next);
                      },
                      child: Text(_soldGenerated ? 'Undo' : 'Mark sold', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Action 1: Print Thermal Receipt
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isPrinting ? null : _handlePrint,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  icon: const Icon(Icons.print, size: 20),
                  label: _isPrinting
                      ? const Text("Printing receipt...")
                      : const Text("Print Bluetooth Receipt"),
                ),
              ),
              const SizedBox(height: 12),

              // Action 1b: Thermal receipt preview
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _showPrintPreview(),
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: const Text("Preview Receipt"),
                ),
              ),
              const SizedBox(height: 12),

              // Action 2: Sell Another Pass
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _generatedCode = null;
                      _soldGenerated = false;
                      _provisioned = null;
                      _provisionDetail = null;
                    });
                  },
                  child: const Text("Sell Another Pass"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
