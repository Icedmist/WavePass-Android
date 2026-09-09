import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';
import '../core/services/supabase_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/theme/app_theme.dart';

class BatchVouchersScreen extends StatefulWidget {
  const BatchVouchersScreen({super.key});
  @override
  State<BatchVouchersScreen> createState() => _BatchVouchersScreenState();
}

class _BatchVouchersScreenState extends State<BatchVouchersScreen> {
  final _qtyCtrl = TextEditingController(text: '10');
  final _prefixCtrl = TextEditingController(text: 'WP-');
  final _searchCtrl = TextEditingController();

  int _codeLength = 6;
  String _charPattern = 'Alphanumeric'; // 'Alphanumeric', 'Numbers Only', 'Uppercase Only'
  String _userMode = 'Voucher Code'; // 'Voucher Code', 'Username & Password'

  String? _selectedVenueId;
  String? _selectedVenueSlug;
  String? _selectedPlanId;
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _generated = [];
  bool _loading = false;
  bool _savingPdf = false;
  String _searchFilter = '';

  @override
  void initState() {
    super.initState();
    VenueStateService.instance.venueNotifier.addListener(_onVenueChanged);
    VenueStateService.instance.plansNotifier.addListener(_onPlansChanged);
    _searchCtrl.addListener(() {
      setState(() => _searchFilter = _searchCtrl.text.trim().toUpperCase());
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
        _selectedVenueSlug = vSlug;
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
          _selectedVenueSlug = vSlug;
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
    } else if (pattern == 'Uppercase Only') {
      charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    } else {
      // Alphanumeric, excluding ambiguous chars (0, O, 1, I)
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
    final prefix = _prefixCtrl.text.trim().toUpperCase();

    try {
      List<String> rawCodes = [];

      // Attempt Cloud Generation first
      try {
        final res = await http.post(
          Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/vouchers/batches'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'venueId': _selectedVenueId,
            'planId': _selectedPlanId,
            'quantity': qty,
          }),
        ).timeout(const Duration(seconds: 12));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body);
          final list = (data is List ? data : data['codes'] ?? data) as List;
          rawCodes = list.map((e) => e is String ? e : e['code']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        }
      } catch (cloudErr) {
        debugPrint('Cloud batch generate fallback: $cloudErr');
      }

      // Offline / custom format fallback if cloud returned fewer than requested
      while (rawCodes.length < qty) {
        final seg = _generateRandomSegment(_codeLength, _charPattern);
        rawCodes.add('$prefix$seg');
      }

      final List<Map<String, dynamic>> compiled = [];
      for (int i = 0; i < rawCodes.length; i++) {
        final code = rawCodes[i];
        final password = _userMode == 'Username & Password'
            ? _generateRandomSegment(4, 'Numbers Only')
            : code;
        compiled.add({
          'code': code,
          'password': password,
          'status': 'ISSUED',
        });
      }

      if (!mounted) return;
      setState(() {
        _generated = compiled;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${_generated.length} vouchers successfully!'),
            backgroundColor: AppColors.accentGreen,
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
      final venue = _venues.firstWhere((v) => v['id'] == _selectedVenueId, orElse: () => {'name': 'WavePass Venue', 'slug': 'venue'});
      final venueName = venue['name']?.toString() ?? 'WavePass Venue';
      final slug = venue['slug']?.toString() ?? _selectedVenueSlug ?? 'venue';

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

      // Group cards into pairs for 2-column rows
      final pairs = <List<Map<String, dynamic>>>[];
      for (int i = 0; i < _generated.length; i += 2) {
        pairs.add([
          _generated[i],
          if (i + 1 < _generated.length) _generated[i + 1],
        ]);
      }

      pw.Widget buildCard(Map<String, dynamic> item) {
        final code = item['code']?.toString() ?? '';
        final pass = item['password']?.toString() ?? '';
        final isDual = _userMode == 'Username & Password' && pass != code;
        final loginUrl = 'http://$slug.nexawavepass.com/login?code=$code';

        return pw.Container(
          width: 260,
          height: 156,
          margin: const pw.EdgeInsets.all(6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(
              color: PdfColors.grey500,
              width: 1,
              style: pw.BorderStyle.dashed,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Venue Header & Wi-Fi badge
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      venueName.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.black),
                      maxLines: 1,
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.black,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      'WI-FI TICKET',
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.SizedBox(height: 2),

              // Middle: QR Code + Plan & Price Info
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(2),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: loginUrl,
                      width: 50,
                      height: 50,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          planName,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.black),
                          maxLines: 1,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          priceStr,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.red800),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '$durationStr • $dataStr',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),

              // Voucher Code Box
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: isDual
                    ? pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('USER: $code', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold())),
                          pw.Text('PIN: $pass', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold())),
                        ],
                      )
                    : pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('VOUCHER:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                          pw.Text(
                            code,
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              font: pw.Font.courierBold(),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
              ),
              pw.Spacer(),
              pw.Text(
                'Connect to Wi-Fi • Scan QR or enter code on login page',
                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
                textAlign: pw.TextAlign.center,
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
              pw.Text('WAVEPASS CUTOUT VOUCHERS', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('$venueName • $planName • ${DateTime.now().toLocal().toString().split(' ')[0]}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
          build: (ctx) => pairs.map((pair) {
            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                buildCard(pair[0]),
                if (pair.length > 1) buildCard(pair[1]) else pw.SizedBox(width: 260),
              ],
            );
          }).toList(),
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Batch Vouchers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [
          if (_generated.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.print_rounded, color: AppColors.primary),
              tooltip: 'Print & Export Options',
              onSelected: (val) {
                if (val == 'cutout') _saveCutoutCardsPdf();
                if (val == 'table') _saveAuditTablePdf();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'cutout',
                  child: Row(
                    children: [
                      Icon(Icons.grid_view_rounded, size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Print Cutout Cards (A4)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
                    const Text('Generator Parameters', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.primary)),
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
                  key: ValueKey('venue_$_selectedVenueId'),
                  initialValue: (_selectedVenueId != null && _venues.any((v) => v['id'] == _selectedVenueId))
                      ? _selectedVenueId
                      : null,
                  decoration: const InputDecoration(labelText: 'Venue', border: OutlineInputBorder()),
                  items: _venues.map((v) => DropdownMenuItem(value: v['id'] as String, child: Text(v['name'] ?? v['id']))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedVenueId = val);
                    if (val != null) _loadPlans(val);
                  },
                ),
                const SizedBox(height: 12),

                // Plan Selection
                DropdownButtonFormField<String>(
                  key: ValueKey('plan_$_selectedPlanId'),
                  initialValue: (_selectedPlanId != null && _plans.any((p) => p['id'] == _selectedPlanId))
                      ? _selectedPlanId
                      : null,
                  decoration: const InputDecoration(labelText: 'Pricing Plan', border: OutlineInputBorder()),
                  items: _plans.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text('${p['name']} — ₦${(p['priceMinor'] as int) ~/ 100}'))).toList(),
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
                        decoration: const InputDecoration(labelText: 'Prefix', border: OutlineInputBorder(), hintText: 'WP-'),
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
                        initialValue: _codeLength,
                        decoration: const InputDecoration(labelText: 'Length', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 4, child: Text('4 chars')),
                          DropdownMenuItem(value: 6, child: Text('6 chars')),
                          DropdownMenuItem(value: 8, child: Text('8 chars')),
                        ],
                        onChanged: (val) => setState(() => _codeLength = val ?? 6),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _charPattern,
                        decoration: const InputDecoration(labelText: 'Charset', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'Alphanumeric', child: Text('Alpha-Num')),
                          DropdownMenuItem(value: 'Numbers Only', child: Text('Numbers')),
                          DropdownMenuItem(value: 'Uppercase Only', child: Text('Letters')),
                        ],
                        onChanged: (val) => setState(() => _charPattern = val ?? 'Alphanumeric'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // User Mode Selector
                DropdownButtonFormField<String>(
                  initialValue: _userMode,
                  decoration: const InputDecoration(labelText: 'User Mode', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Voucher Code', child: Text('Voucher (User = Pass)')),
                    DropdownMenuItem(value: 'Username & Password', child: Text('Username & Password')),
                  ],
                  onChanged: (val) => setState(() => _userMode = val ?? 'Voucher Code'),
                ),
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
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _savingPdf ? null : _saveCutoutCardsPdf,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.grid_view_rounded, size: 16),
                          label: const Text('Print Cutout Cards (A4)', style: TextStyle(fontSize: 11)),
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
