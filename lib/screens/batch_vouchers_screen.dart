import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/router_discovery_service.dart';
import '../core/services/supabase_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/voucher_history_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/theme/app_theme.dart';
import 'voucher_history_sheet.dart';

class BatchVouchersScreen extends StatefulWidget {
  const BatchVouchersScreen({super.key});
  @override
  State<BatchVouchersScreen> createState() => _BatchVouchersScreenState();
}

class _BatchVouchersScreenState extends State<BatchVouchersScreen> {
  final _qtyCtrl = TextEditingController(text: '10');
  final _prefixCtrl = TextEditingController(text: '');
  final _passPrefixCtrl = TextEditingController(text: '');
  final _searchCtrl = TextEditingController();

  int _codeLength = 6;
  String _charPattern = 'Numbers Only'; // 'Numbers Only', 'Alphanumeric', 'Uppercase Only'
  String _userMode = 'Voucher Code'; // 'Voucher Code', 'Username & Password'

  int _passLength = 4;
  String _passPattern = 'Numbers Only'; // 'Numbers Only', 'Alphanumeric', 'Uppercase Only', 'Same as Username'

  String? _selectedVenueId;
  String? _selectedPlanId;
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _generated = [];
  bool _loading = false;
  bool _savingPdf = false;
  String _searchFilter = '';

  // A4 layout customization (preview + PDF share these).
  // Defaults match the cutout grid in the reference photo: compact multi-
  // column cards with venue / voucher / plan / price, no QR.
  String _a4Density = 'Compact'; // Compact, Standard, Large
  int _a4Columns = 5; // 1, 2, 3, 4 or 5 cards per row
  double _a4QrSize = 50; // 38 (S), 50 (M), 64 (L)
  bool _a4ShowQr = false;
  bool _a4ShowPrice = true;
  bool _a4ShowInstructions = true;

  @override
  void initState() {
    super.initState();
    VenueStateService.instance.venueNotifier.addListener(_onVenueChanged);
    VenueStateService.instance.plansNotifier.addListener(_onPlansChanged);
    _searchCtrl.addListener(() {
      if (mounted) {
        setState(() => _searchFilter = _searchCtrl.text.trim().toUpperCase());
      }
    });
    _onVenueChanged();
    _onPlansChanged();
    _loadVenues();
  }

  @override
  void dispose() {
    VenueStateService.instance.venueNotifier.removeListener(_onVenueChanged);
    VenueStateService.instance.plansNotifier.removeListener(_onPlansChanged);
    _qtyCtrl.dispose();
    _prefixCtrl.dispose();
    _passPrefixCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onVenueChanged() {
    final v = VenueStateService.instance.currentVenue;
    if (v != null && mounted) {
      final vId = v['id']?.toString();
      final vSlug = v['slug']?.toString() ?? 'venue';
      final vName = v['name']?.toString() ?? 'WavePass Venue';
      setState(() {
        _venues = [{'id': vId, 'name': vName, 'slug': vSlug}];
        _selectedVenueId = vId;
      });
    }
  }

  void _onPlansChanged() {
    final p = VenueStateService.instance.currentPlans;
    if (mounted) {
      setState(() {
        _plans = p;
        if (_plans.isNotEmpty) {
          final exists = _plans.any((item) => item['id']?.toString() == _selectedPlanId);
          if (!exists) {
            _selectedPlanId = _plans.first['id']?.toString();
          }
        } else {
          _selectedPlanId = null;
        }
      });
    }
  }

  Future<void> _loadVenues() async {
    try {
      var venue = VenueStateService.instance.currentVenue;
      venue ??= await VenueStateService.instance.refreshVenue();

      if (venue != null) {
        final vId = venue['id']?.toString();
        final vSlug = venue['slug']?.toString() ?? 'venue';
        final vName = venue['name']?.toString() ?? 'WavePass Venue';
        final vMap = {'id': vId, 'name': vName, 'slug': vSlug};
        if (!mounted) return;
        setState(() {
          _venues = [vMap];
          _selectedVenueId = vId;
        });
        await VenueStateService.instance.refreshPlans();
      }
    } catch (e) {
      debugPrint('Error loading venues: $e');
    }
  }

  Future<void> _loadPlans(String venueId, {List<dynamic>? preloadedPlans}) async {
    List<Map<String, dynamic>> plans = [];
    if (preloadedPlans != null && preloadedPlans.isNotEmpty) {
      plans = List<Map<String, dynamic>>.from(preloadedPlans);
    } else {
      try {
        plans = await SupabaseService.instance.getActivePlans(venueId);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _plans = plans;
        if (plans.isNotEmpty) {
          _selectedPlanId = plans.first['id']?.toString();
        } else {
          _selectedPlanId = null;
        }
      });
    }
  }

  String _generateRandomSegment(int length, String pattern) {
    String charset;
    if (pattern == 'Numbers Only') {
      charset = '0123456789';
    } else if (pattern == 'Uppercase Only' || pattern == 'Letters Only') {
      charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    } else {
      // Numbers in combination with letters without dashes
      charset = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    }
    final rnd = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => charset.codeUnitAt(rnd.nextInt(charset.length))),
    );
  }

  Future<void> _generateBatch() async {
    if (_selectedVenueId == null || _selectedPlanId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a venue and pricing plan before generating vouchers.')),
      );
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    if (qty < 1 || qty > 500) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantity must be between 1 and 500')));
      return;
    }

    setState(() => _loading = true);
    final prefix = _prefixCtrl.text.trim().toUpperCase().replaceAll('-', '');

    try {
      final Set<String> uniqueCodes = {};
      int attempts = 0;
      final maxAttempts = qty * 50;
      while (uniqueCodes.length < qty && attempts < maxAttempts) {
        attempts++;
        final seg = _generateRandomSegment(_codeLength, _charPattern);
        uniqueCodes.add('$prefix$seg'.replaceAll('-', ''));
      }
      final List<String> rawCodes = uniqueCodes.toList();

      final List<Map<String, dynamic>> compiled = [];
      final passPrefix = _passPrefixCtrl.text.trim().replaceAll('-', '');
      for (int i = 0; i < rawCodes.length; i++) {
        final code = rawCodes[i].replaceAll('-', '');
        String password = code;
        if (_userMode == 'Username & Password') {
          if (_passPattern == 'Same as Username') {
            password = code;
          } else {
            final seg = _generateRandomSegment(_passLength, _passPattern);
            password = '$passPrefix$seg'.replaceAll('-', '');
          }
        }
        compiled.add({
          'code': code,
          'password': password,
          'status': 'ISSUED',
        });
      }

      // Retrieve selected plan duration and rate profile
      final selectedPlan = _plans.firstWhere(
        (p) => p['id']?.toString() == _selectedPlanId?.toString(),
        orElse: () => {'name': 'Pass', 'priceMinor': 0, 'durationSeconds': 3600},
      );
      final planName = selectedPlan['name']?.toString() ?? 'Pass';
      final price = '₦${((selectedPlan['priceMinor'] as num?)?.toInt() ?? 0) ~/ 100}';
      final durationSec = (selectedPlan['durationSeconds'] as num?)?.toInt() ?? 3600;
      final profileName = RouterDiscoveryService.profileForDuration(durationSec);

      // Synchronously provision batch vouchers to router hardware (LAN Direct / Cloud Tunnel)
      int routerPushed = 0;
      String? routerMode;
      for (final item in compiled) {
        try {
          final res = await RouterDiscoveryService.provisionVoucherDualRoute(
            code: item['code'] as String,
            pass: item['password'] as String?,
            profile: profileName,
            sessionTimeoutSeconds: durationSec,
          );
          if (res['success'] == true) {
            routerPushed++;
            routerMode = res['mode']?.toString();
          }
        } catch (_) {}
      }

      // Upload the exact codes to cloud so records match app + router.
      // Best-effort: router-pushed codes work regardless; cloud enables
      // portal redeem, retrieve-voucher, and success-page verification.
      final Set<String> cloudConfirmed = {};
      if (_selectedVenueId != null && _selectedPlanId != null) {
        try {
          final res = await WavePassApi.instance.uploadVoucherBatch(
            venueId: _selectedVenueId!,
            planId: _selectedPlanId!,
            codes: compiled.map((e) => e['code'] as String).toList(),
          ).timeout(const Duration(seconds: 15));
          final list = res['vouchers'];
          if (list is List) {
            for (final v in list) {
              final c = (v is Map ? v['code'] : null)?.toString().toUpperCase();
              if (c != null && c.isNotEmpty) cloudConfirmed.add(c);
            }
          }
        } catch (e) {
          debugPrint('Cloud batch upload failed: $e');
        }
      }

      // Record batch vouchers in local history
      for (final item in compiled) {
        final code = item['code'] as String;
        final pass = item['password'] as String?;
        VoucherHistoryService.instance.recordVoucher(
          code: code,
          password: pass,
          planTitle: planName,
          price: price,
          durationSeconds: durationSec,
          directMode: routerMode,
          source: 'batch',
          provisioned: cloudConfirmed.contains(code.toUpperCase()),
        );
      }

      // Mark router-pushed codes provisioned regardless of cloud outcome.
      if (routerPushed > 0) {
        for (final item in compiled) {
          await VoucherHistoryService.instance.updateProvisioned(
            item['code'] as String,
            true,
            directMode: routerMode,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _generated = compiled;
      });

      if (mounted) {
        final routerInfo = routerPushed > 0
            ? " ($routerPushed live on router via ${routerMode == 'local' ? 'LAN Direct' : 'Tunnel'})"
            : '';
        final cloudInfo = cloudConfirmed.isNotEmpty
            ? ' (${cloudConfirmed.length} confirmed in cloud)'
            : ' (cloud sync failed)';
        final allLanded = routerPushed == compiled.length || cloudConfirmed.length == compiled.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${_generated.length} vouchers successfully!$routerInfo$cloudInfo'),
            backgroundColor: allLanded ? AppColors.accentGreen : AppColors.accentRed,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generation failed: $e'), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Exports printable A4 Cutout Cards (Mikhmon-style grid with dashed borders and individual QR codes).
  Future<void> _saveCutoutCardsPdf() async {
    if (_generated.isEmpty) return;
    setState(() => _savingPdf = true);
    try {
      final pdf = pw.Document();
      final venue = _venues.firstWhere((v) => v['id']?.toString() == _selectedVenueId?.toString(), orElse: () => {'name': 'WavePass Venue', 'slug': 'venue'});
      final venueName = venue['name']?.toString() ?? 'WavePass Venue';

      final plan = _plans.firstWhere((p) => p['id']?.toString() == _selectedPlanId?.toString(), orElse: () => {'name': 'Pass'});
      final planName = plan['name']?.toString() ?? 'Pass';
      final priceMinor = (plan['priceMinor'] as num?)?.toInt() ?? 0;
      final priceStr = '₦${priceMinor ~/ 100}';

      final durationSec = (plan['durationSeconds'] as num?)?.toInt() ?? 3600;
      final durationStr = durationSec < 3600
          ? '${durationSec ~/ 60}m'
          : durationSec < 86400
              ? '${durationSec ~/ 3600}h'
              : '${durationSec ~/ 86400}d';
      final dataLimit = plan['dataLimitBytes'];
      final dataStr = dataLimit == null
          ? 'Unlimited'
          : '${((dataLimit as num) / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';

      pw.Widget buildCard(Map<String, dynamic> item) {
        final code = item['code']?.toString() ?? '';
        final pass = item['password']?.toString() ?? '';
        final isDual = _userMode == 'Username & Password' && pass != code;
        final compact = _a4Density == 'Compact';
        final large = _a4Density == 'Large';
        final dateStr = DateTime.now().toLocal().toString().split('.')[0];

        // Grid cutout (3-5 columns): matches the reference photo — centered
        // stack of venue / voucher / plan-duration-data / price, no QR.
        if (_a4Columns >= 3) {
          final gridCodeSize = compact ? 9.5 : large ? 12.0 : 11.0;
          final gridTitleSize = compact ? 7.5 : large ? 9.5 : 8.5;
          final gridSmallSize = compact ? 5.5 : large ? 7.0 : 6.5;
          return pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.all(2.5),
            padding: pw.EdgeInsets.symmetric(horizontal: 5, vertical: compact ? 5 : 7),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(venueName.toUpperCase(),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: gridTitleSize, color: PdfColors.black),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1),
                pw.Text('WavePass Wi-Fi Slip • $planName',
                    style: pw.TextStyle(fontSize: gridSmallSize, color: PdfColors.grey800),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1),
                if (_a4ShowQr) ...[
                  pw.SizedBox(height: 3),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: 'http://192.168.88.1/login?username=$code&password=$pass',
                    width: _a4QrSize * 0.75,
                    height: _a4QrSize * 0.75,
                  ),
                ],
                pw.SizedBox(height: 3),
                pw.Text(isDual ? 'USER: $code' : code,
                    style: pw.TextStyle(fontSize: gridCodeSize, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold()),
                    textAlign: pw.TextAlign.center),
                if (isDual)
                  pw.Text('PIN: $pass',
                      style: pw.TextStyle(fontSize: gridCodeSize - 1, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold()),
                      textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 1),
                pw.Text('$planName • $durationStr • $dataStr',
                    style: pw.TextStyle(fontSize: gridSmallSize + 0.5, color: PdfColors.grey800),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1),
                if (_a4ShowPrice)
                  pw.Text(priceStr,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: gridTitleSize, color: PdfColors.black),
                      textAlign: pw.TextAlign.center),
                if (_a4ShowInstructions) ...[
                  pw.SizedBox(height: 2),
                  pw.Text('Connect to Wi-Fi • Enter code at 192.168.88.1',
                      style: pw.TextStyle(fontSize: gridSmallSize - 0.5, color: PdfColors.grey600),
                      textAlign: pw.TextAlign.center,
                      maxLines: 2),
                  pw.Text(dateStr, style: pw.TextStyle(fontSize: gridSmallSize - 0.5, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
                ],
              ],
            ),
          );
        }

        final vPad = compact ? 4.0 : large ? 10.0 : 7.0;
        final hPad = compact ? 7.0 : large ? 13.0 : 10.0;
        final qr = _a4ShowQr ? _a4QrSize : 0.0;
        final codeSize = compact ? 11.0 : large ? 15.0 : 13.0;
        final titleSize = compact ? 9.0 : large ? 11.0 : 10.0;

        return pw.Container(
          width: double.infinity,
          margin: pw.EdgeInsets.symmetric(vertical: compact ? 2.5 : 3.5, horizontal: _a4Columns == 2 ? 3 : 0),
          padding: pw.EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(
              color: PdfColors.grey500,
              width: 1,
              style: pw.BorderStyle.dashed,
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // 1. QR Code (optional)
              if (_a4ShowQr)
                pw.Container(
                  padding: const pw.EdgeInsets.all(3),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: 'http://192.168.88.1/login?username=${item['code']}&password=${item['password'] ?? item['code']}',
                    width: qr,
                    height: qr,
                  ),
                ),
              if (_a4ShowQr) pw.SizedBox(width: 12),

              // 2. Plan & Venue Details
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          venueName.toUpperCase(),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: titleSize, color: PdfColors.black),
                          maxLines: 1,
                        ),
                        pw.SizedBox(width: 6),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.black,
                            borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                          ),
                          child: pw.Text(
                            'WI-FI SLIP',
                            style: pw.TextStyle(color: PdfColors.white, fontSize: 6.5, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      '$planName  •  $durationStr  •  $dataStr',
                      style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
                    ),
                    if (_a4ShowInstructions) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Connect to Wi-Fi & scan QR or enter code at 192.168.88.1',
                        style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
                      ),
                    ],
                  ],
                ),
              ),

              pw.SizedBox(width: 8),

              // 3. Price & Voucher Code Box
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (_a4ShowPrice)
                      pw.Text(
                        priceStr,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.red800),
                      ),
                    if (_a4ShowPrice) pw.SizedBox(height: 3),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: isDual
                          ? pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text('USER: $code', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold())),
                                pw.Text('PIN: $pass', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold())),
                              ],
                            )
                          : pw.Text(
                              code,
                              style: pw.TextStyle(
                                fontSize: codeSize,
                                fontWeight: pw.FontWeight.bold,
                                font: pw.Font.courierBold(),
                                letterSpacing: 1.0,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          header: (ctx) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('WAVEPASS VOUCHER SLIPS', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('$venueName • $planName • ${DateTime.now().toLocal().toString().split(' ')[0]}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
          build: (ctx) {
            final cards = _generated.map((item) => buildCard(item)).toList();
            if (_a4Columns <= 1) return cards;
            final cols = _a4Columns.clamp(2, 5);
            final rows = <pw.Widget>[];
            for (var i = 0; i < cards.length; i += cols) {
              final cells = <pw.Widget>[];
              for (var c = 0; c < cols; c++) {
                if (c > 0) cells.add(pw.SizedBox(width: cols >= 3 ? 3 : 6));
                cells.add(pw.Expanded(
                  child: i + c < cards.length ? cards[i + c] : pw.Container(),
                ));
              }
              rows.add(
                pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: cells),
              );
            }
            return rows;
          },
        ),
      );

      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/wavepass_cutout_cards_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);

      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dl = File('${extDir.path}/wavepass_cutout_cards_${DateTime.now().millisecondsSinceEpoch}.pdf');
          await dl.writeAsBytes(bytes);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cutout cards saved: ${dl.path}')));
          await OpenFile.open(dl.path);
          return;
        }
      } catch (_) {}

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cutout cards saved: ${file.path}')));
      await OpenFile.open(file.path);
      await Printing.sharePdf(bytes: bytes, filename: 'wavepass_cutout_cards.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF generation failed: $e')));
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  int _a4EstimatedPages() {
    // Grid cards are shorter: ~8 rows/page compact, 6 standard, 4 large.
    final rows = _a4Density == 'Compact' ? 8 : _a4Density == 'Large' ? 4 : 6;
    final perPage = rows * _a4Columns.clamp(1, 5);
    if (_generated.isEmpty || perPage <= 0) return 0;
    return ((_generated.length + perPage - 1) ~/ perPage);
  }

  /// Live A4 preview + layout customization sheet. What you see is what the
  /// saved PDF looks like: card size, columns, QR size and visible fields.
  Future<void> _showA4PreviewSheet() async {
    if (_generated.isEmpty) return;
    final venue = _venues.firstWhere((v) => v['id']?.toString() == _selectedVenueId?.toString(), orElse: () => {'name': 'WavePass Venue'});
    final venueName = venue['name']?.toString() ?? 'WavePass Venue';
    final plan = _plans.firstWhere((p) => p['id']?.toString() == _selectedPlanId?.toString(), orElse: () => {'name': 'Pass'});
    final planName = plan['name']?.toString() ?? 'Pass';
    final priceMinor = (plan['priceMinor'] as num?)?.toInt() ?? 0;
    final priceStr = '₦${priceMinor ~/ 100}';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void sync(void Function() fn) {
            setSheet(fn);
            setState(fn);
          }

          final previewItems = _generated.take(_a4Columns >= 3 ? 10 : 4).toList();
          final pages = _a4EstimatedPages();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.92,
            minChildSize: 0.6,
            maxChildSize: 0.96,
            builder: (_, ctrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ListView(
                controller: ctrl,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('A4 Preview & Layout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary)),
                      Text('$pages page${pages == 1 ? '' : 's'} • ${_generated.length} slips',
                          style: const TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Customize, preview, then save the PDF to your phone.',
                      style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                  const SizedBox(height: 14),
                  const Text('CARD SIZE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Compact', label: Text('Compact')),
                      ButtonSegment(value: 'Standard', label: Text('Standard')),
                      ButtonSegment(value: 'Large', label: Text('Large')),
                    ],
                    selected: {_a4Density},
                    onSelectionChanged: (s) => sync(() => _a4Density = s.first),
                  ),
                  const SizedBox(height: 12),
                  const Text('COLUMNS ON A4', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                      ButtonSegment(value: 4, label: Text('4')),
                      ButtonSegment(value: 5, label: Text('5')),
                    ],
                    selected: {_a4Columns.clamp(2, 5)},
                    onSelectionChanged: (s) => sync(() => _a4Columns = s.first),
                  ),
                  TextButton(
                    onPressed: () => sync(() => _a4Columns = 1),
                    child: Text(_a4Columns == 1 ? '✓ Single-column list mode' : 'Use single-column list instead',
                        style: const TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 12),
                  const Text('QR CODE SIZE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 38, label: Text('S')),
                      ButtonSegment(value: 50, label: Text('M')),
                      ButtonSegment(value: 64, label: Text('L')),
                    ],
                    selected: {_a4QrSize},
                    onSelectionChanged: (s) => sync(() => _a4QrSize = s.first),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Show QR code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    value: _a4ShowQr,
                    onChanged: (v) => sync(() => _a4ShowQr = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Show price', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    value: _a4ShowPrice,
                    onChanged: (v) => sync(() => _a4ShowPrice = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Show instruction line', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    value: _a4ShowInstructions,
                    onChanged: (v) => sync(() => _a4ShowInstructions = v),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.containerBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LIVE PREVIEW (first slips, as on A4)',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.6)),
                        const SizedBox(height: 8),
                        ..._a4PreviewRows(previewItems, venueName, planName, priceStr),
                        if (_generated.length > previewItems.length)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('+ ${_generated.length - previewItems.length} more slips in the PDF…',
                                style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _savingPdf
                          ? null
                          : () {
                              Navigator.of(ctx).pop();
                              _saveCutoutCardsPdf();
                            },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: Text(_savingPdf ? 'Saving…' : 'Save A4 PDF to Phone ($pages page${pages == 1 ? '' : 's'})'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Flutter approximation of one PDF slip for the live preview.
  Widget _a4PreviewCard(Map<String, dynamic> item, String venueName, String planName, String priceStr) {
    final code = item['code']?.toString() ?? '';
    final pass = item['password']?.toString() ?? code;
    final isDual = _userMode == 'Username & Password' && pass != code;
    final compact = _a4Density == 'Compact';
    final large = _a4Density == 'Large';
    final qrBox = (_a4QrSize / 2.2).clamp(20.0, 34.0);
    // Grid mode (>=3 cols): centered stack like the reference photo, no QR.
    if (_a4Columns >= 3) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 6 : large ? 10 : 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade500, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(venueName.toUpperCase(),
                style: TextStyle(fontSize: compact ? 8 : large ? 10 : 9, fontWeight: FontWeight.w900),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
            Text('WavePass Wi-Fi Slip • $planName',
                style: const TextStyle(fontSize: 7, color: AppColors.textLight),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
            if (_a4ShowQr) ...[
              const SizedBox(height: 4),
              Icon(Icons.qr_code_2_rounded, size: qrBox, color: AppColors.primary),
            ],
            const SizedBox(height: 4),
            Text(isDual ? 'USER: $code' : code,
                style: TextStyle(fontSize: compact ? 10 : large ? 13 : 11.5, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                textAlign: TextAlign.center),
            if (isDual)
              Text('PIN: $pass',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                  textAlign: TextAlign.center),
            if (_a4ShowPrice)
              Text(priceStr, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
            if (_a4ShowInstructions)
              const Text('Enter code at 192.168.88.1',
                  style: TextStyle(fontSize: 7, color: AppColors.textLight), textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 6 : large ? 12 : 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid, width: 1),
      ),
      child: Row(
        children: [
          if (_a4ShowQr)
            Container(
              width: qrBox + 10,
              height: qrBox + 10,
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.qr_code_2_rounded, size: qrBox, color: AppColors.primary),
            ),
          if (_a4ShowQr) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(venueName.toUpperCase(),
                    style: TextStyle(fontSize: compact ? 10 : large ? 13 : 11.5, fontWeight: FontWeight.w900, color: AppColors.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(planName, style: TextStyle(fontSize: compact ? 10 : 11.5, color: AppColors.textLight)),
                if (_a4ShowInstructions)
                  const Text('Scan QR or enter code at 192.168.88.1',
                      style: TextStyle(fontSize: 9, color: AppColors.textLight)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_a4ShowPrice)
                Text(priceStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.accentRed)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                child: Text(isDual ? 'USER: $code\nPIN: $pass' : code,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontSize: compact ? 11 : large ? 14 : 12.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        height: 1.3)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _a4PreviewRows(List<Map<String, dynamic>> items, String venueName, String planName, String priceStr) {
    final cards = items.map((e) => _a4PreviewCard(e, venueName, planName, priceStr)).toList();
    final cols = _a4Columns.clamp(1, 5);
    if (cols <= 1) return [for (final c in cards) ...[c, const SizedBox(height: 8)]];
    final gap = cols >= 3 ? 4.0 : 8.0;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += cols) {
      final cells = <Widget>[];
      for (var c = 0; c < cols; c++) {
        if (c > 0) cells.add(SizedBox(width: gap));
        cells.add(Expanded(child: i + c < cards.length ? cards[i + c] : const SizedBox()));
      }
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells));
      rows.add(SizedBox(height: gap));
    }
    return rows;
  }

  /// Exports printable 58/80mm thermal cutout slips (one mini-printer slip per
  /// voucher — replaces A4-only output for pocket POS printers).
  Future<void> _saveThermalCutoutSlips() async {
    if (_generated.isEmpty) return;
    setState(() => _savingPdf = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final width = prefs.getInt('wavepass_printer_paper_width') ?? 58;
      final format = width == 80 ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
      final qrSize = width == 80 ? 78.0 : 62.0;

      final venue = _venues.firstWhere((v) => v['id'] == _selectedVenueId, orElse: () => {'name': 'WavePass Venue', 'slug': 'venue'});
      final venueName = (venue['name']?.toString() ?? 'WavePass Venue').toUpperCase();

      final plan = _plans.firstWhere((p) => p['id'] == _selectedPlanId, orElse: () => {'name': 'Pass'});
      final planName = plan['name']?.toString() ?? 'Pass';
      final priceMinor = (plan['priceMinor'] as num?)?.toInt() ?? 0;
      final priceStr = '₦${priceMinor ~/ 100}';
      final durationSec = (plan['durationSeconds'] as num?)?.toInt() ?? 3600;
      final durationStr = durationSec < 3600
          ? '${durationSec ~/ 60}m'
          : durationSec < 86400
              ? '${durationSec ~/ 3600}h'
              : '${durationSec ~/ 86400}d';
      final dataLimit = plan['dataLimitBytes'];
      final dataStr = dataLimit == null
          ? 'Unlimited'
          : '${((dataLimit as num) / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
      final dateStr = DateTime.now().toLocal().toString().split('.')[0];

      final pdf = pw.Document();
      for (final item in _generated) {
        final code = item['code']?.toString() ?? '';
        final pass = item['password']?.toString() ?? code;
        final isDual = _userMode == 'Username & Password' && pass != code;
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(venueName,
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                    maxLines: 2),
                pw.SizedBox(height: 1),
                pw.Text('WavePass Wi-Fi Slip • $planName',
                    style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 3),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: 'http://192.168.88.1/login?username=$code&password=$pass',
                  width: qrSize,
                  height: qrSize,
                ),
                pw.SizedBox(height: 4),
                if (isDual) ...[
                  pw.Text('USER: $code',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold())),
                  pw.SizedBox(height: 2),
                  pw.Text('PIN: $pass',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold())),
                ] else
                  pw.Text(code,
                      style: pw.TextStyle(
                          fontSize: 15, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold())),
                pw.SizedBox(height: 3),
                pw.Text('$planName • $durationStr • $dataStr',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center),
                pw.Text(priceStr,
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Divider(thickness: 0.5),
                pw.Text('Connect to Wi-Fi • Enter code at 192.168.88.1',
                    style: const pw.TextStyle(fontSize: 6.5), textAlign: pw.TextAlign.center),
                pw.Text(dateStr, style: const pw.TextStyle(fontSize: 6.5)),
                pw.SizedBox(height: 4),
                pw.Text('- - - - - - - - - - - - - - ✂ - - - - - - - - - - - - - -',
                    style: const pw.TextStyle(fontSize: 6)),
              ],
            ),
          ),
        );
      }

      final bytes = await pdf.save();
      final savedUrl = prefs.getString('wavepass_selected_printer_url');
      if (savedUrl != null) {
        try {
          final printers = await Printing.listPrinters();
          final matched = printers.where((p) => p.url == savedUrl).firstOrNull;
          if (matched != null) {
            await Printing.directPrintPdf(printer: matched, onLayout: (_) async => bytes);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        '${_generated.length} thermal slips (${width}mm) sent to ${matched.name}'),
                    backgroundColor: AppColors.accentGreen),
              );
            }
            return;
          }
        } catch (_) {}
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/wavepass_thermal_slips_${width}mm_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Thermal slips (${width}mm) saved: ${file.path}')));
      }
      await Printing.sharePdf(bytes: bytes, filename: 'wavepass_thermal_slips_${width}mm.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Thermal PDF failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  /// Exports a clean summary audit table.
  Future<void> _saveAuditTablePdf() async {
    if (_generated.isEmpty) return;
    setState(() => _savingPdf = true);
    try {
      final pdf = pw.Document();
      final venueName = _venues.firstWhere((v) => v['id'] == _selectedVenueId, orElse: () => {'name': 'WavePass Venue'})['name'];
      final planName = _plans.firstWhere((p) => p['id'] == _selectedPlanId, orElse: () => {'name': 'Pass'})['name'];

      final isDual = _userMode == 'Username & Password';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('WavePass Voucher Audit Report', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text(DateTime.now().toLocal().toString().split(' ')[0], style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ]),
          build: (ctx) => [
            pw.SizedBox(height: 8),
            pw.Text('Venue: $venueName • Plan: $planName • Total: ${_generated.length} vouchers', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: isDual ? ['#', 'Username / Code', 'Password', 'Status'] : ['#', 'Voucher Code', 'Status'],
              data: List.generate(_generated.length, (i) {
                final item = _generated[i];
                if (isDual) {
                  return ['${i + 1}', item['code'].toString(), item['password']?.toString() ?? '', 'ISSUED'];
                } else {
                  return ['${i + 1}', item['code'].toString(), 'ISSUED'];
                }
              }),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey900),
              cellStyle: const pw.TextStyle(fontSize: 9),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
              cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.center, 2: pw.Alignment.center, 3: pw.Alignment.center},
            ),
            pw.SizedBox(height: 16),
            pw.Text('Generated by WavePass Operator App. Confidential record for venue accounting.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      );

      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/wavepass_audit_table_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);

      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dl = File('${extDir.path}/wavepass_audit_table_${DateTime.now().millisecondsSinceEpoch}.pdf');
          await dl.writeAsBytes(bytes);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audit table saved: ${dl.path}')));
          await OpenFile.open(dl.path);
          return;
        }
      } catch (_) {}

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audit table saved: ${file.path}')));
      await OpenFile.open(file.path);
      await Printing.sharePdf(bytes: bytes, filename: 'wavepass_audit_table.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF failed: $e')));
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _searchFilter.isEmpty
        ? _generated
        : _generated.where((item) {
            final c = item['code']?.toString().toUpperCase() ?? '';
            final p = item['password']?.toString().toUpperCase() ?? '';
            return c.contains(_searchFilter) || p.contains(_searchFilter);
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text('Batch Vouchers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: AppColors.primary),
            tooltip: 'Voucher History',
            onPressed: () => VoucherHistorySheet.show(context),
          ),
          if (_generated.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.print_rounded, color: AppColors.primary),
              tooltip: 'Print & Export Options',
              onSelected: (val) {
                if (val == 'thermal') _saveThermalCutoutSlips();
                if (val == 'cutout') _showA4PreviewSheet();
                if (val == 'table') _saveAuditTablePdf();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'cutout',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Save A4 PDF (Default)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'thermal',
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Thermal Slips (58/80mm)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'table',
                  child: Row(
                    children: [
                      Icon(Icons.table_chart_rounded, size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Export Audit Table (A4)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.containerBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text('Generator Parameters', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                      child: const Text('MIKHMON PARITY', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Customize voucher prefix, length, and printable card grid.', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                const SizedBox(height: 16),

                // Venue Selection
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('venue_$_selectedVenueId'),
                  initialValue: (_selectedVenueId != null && _venues.any((v) => v['id']?.toString() == _selectedVenueId))
                      ? _selectedVenueId
                      : null,
                  decoration: const InputDecoration(labelText: 'Venue', border: OutlineInputBorder()),
                  items: () {
                    final seen = <String>{};
                    final items = <DropdownMenuItem<String>>[];
                    for (final v in _venues) {
                      final id = v['id']?.toString() ?? '';
                      if (id.isEmpty || seen.contains(id)) continue;
                      seen.add(id);
                      final name = v['name']?.toString() ?? id;
                      items.add(DropdownMenuItem(value: id, child: Text(name)));
                    }
                    return items;
                  }(),
                  onChanged: (val) {
                    setState(() => _selectedVenueId = val);
                    if (val != null) _loadPlans(val);
                  },
                ),
                const SizedBox(height: 12),

                // Plan Selection
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('plan_$_selectedPlanId'),
                  initialValue: (_selectedPlanId != null && _plans.any((p) => p['id']?.toString() == _selectedPlanId))
                      ? _selectedPlanId
                      : null,
                  decoration: const InputDecoration(labelText: 'Pricing Plan', border: OutlineInputBorder()),
                  items: () {
                    final seen = <String>{};
                    final items = <DropdownMenuItem<String>>[];
                    for (final p in _plans) {
                      final id = p['id']?.toString() ?? '';
                      if (id.isEmpty || seen.contains(id)) continue;
                      seen.add(id);
                      final name = p['name']?.toString() ?? 'Pass';
                      final price = ((p['priceMinor'] as num?)?.toInt() ?? 0) ~/ 100;
                      items.add(DropdownMenuItem(value: id, child: Text('$name — ₦$price')));
                    }
                    return items;
                  }(),
                  onChanged: (val) => setState(() => _selectedPlanId = val),
                ),
                const SizedBox(height: 12),

                // Row: Quantity + Prefix
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Quantity (1-500)', border: OutlineInputBorder(), hintText: '10'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _prefixCtrl,
                        decoration: const InputDecoration(labelText: 'Prefix', border: OutlineInputBorder(), hintText: 'Optional'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Row: Code Length & Character Set
                Row(
                  children: [
                    Expanded(
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                  isExpanded: true,
                        initialValue: _charPattern,
                        decoration: const InputDecoration(labelText: 'Charset', border: OutlineInputBorder()),
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
                const SizedBox(height: 12),

                // User Mode Selector
                DropdownButtonFormField<String>(
                      isExpanded: true,
                  initialValue: _userMode,
                  decoration: const InputDecoration(labelText: 'User Mode', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Voucher Code', child: Text('Voucher (User = Pass)')),
                    DropdownMenuItem(value: 'Username & Password', child: Text('Username & Password')),
                  ],
                  onChanged: (val) => setState(() => _userMode = val ?? 'Voucher Code'),
                ),

                // Password Customization Parameters (if Username & Password mode)
                if (_userMode == 'Username & Password') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Password / PIN Customization',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
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
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                  isExpanded: true,
                                initialValue: _passPattern,
                                decoration: const InputDecoration(labelText: 'PIN Pattern', border: OutlineInputBorder()),
                                items: const [
                                  DropdownMenuItem(value: 'Numbers Only', child: Text('Numbers')),
                                  DropdownMenuItem(value: 'Alphanumeric', child: Text('Alpha-Num')),
                                  DropdownMenuItem(value: 'Uppercase Only', child: Text('Letters')),
                                  DropdownMenuItem(value: 'Same as Username', child: Text('Same as Code')),
                                ],
                                onChanged: (val) => setState(() => _passPattern = val ?? 'Numbers Only'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passPrefixCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Password Prefix (Optional)',
                            border: OutlineInputBorder(),
                            hintText: 'e.g. PIN-',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Generate Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _generateBatch,
                    icon: _loading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.confirmation_number_rounded),
                    label: Text(_loading ? 'Generating Batch...' : 'Generate ${(_qtyCtrl.text.isEmpty ? 10 : int.tryParse(_qtyCtrl.text) ?? 10)} Vouchers'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Generated Vouchers Header & Export Buttons
          if (_generated.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_generated.length} Vouchers Generated',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      Text(
                        _userMode == 'Username & Password' ? 'Dual Mode' : 'Voucher Mode',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textLight),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Default: A4 preview + customize, then save PDF on the phone.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _savingPdf ? null : _showA4PreviewSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.preview_rounded, size: 16),
                      label: const Text('Preview A4 Layout & Save PDF',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Saved to your phone • share or print anywhere',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: AppColors.textLight),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _savingPdf ? null : _saveThermalCutoutSlips,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.receipt_long_rounded, size: 16),
                          label: const Text('Thermal (58/80mm)', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _savingPdf ? null : _saveAuditTablePdf,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.table_chart_rounded, size: 16),
                          label: const Text('Audit Table (A4)', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search filter field
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search voucher codes...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchFilter.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchCtrl.clear())
                    : null,
                filled: true,
                fillColor: AppColors.containerBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            const SizedBox(height: 10),

            // Voucher List
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredList.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0x0F000000)),
                itemBuilder: (c, i) {
                  final item = filteredList[i];
                  final code = item['code']?.toString() ?? '';
                  final pass = item['password']?.toString() ?? '';
                  final isDual = _userMode == 'Username & Password' && pass != code;

                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                      child: Center(
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    title: Text(code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 14)),
                    subtitle: isDual ? Text('Password: $pass', style: const TextStyle(fontSize: 11, color: AppColors.textLight)) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accentGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: const Text('ACTIVE', style: TextStyle(color: AppColors.accentGreen, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textLight),
                          tooltip: 'Copy Code',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Voucher $code copied to clipboard'),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: AppColors.primary,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
