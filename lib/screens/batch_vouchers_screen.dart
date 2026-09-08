import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
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
  State<BatchVouchersScreen> createState() => _SState();
}

class _SState extends State<BatchVouchersScreen> {
  final _qtyCtrl = TextEditingController(text: '10');
  String? _selectedVenueId;
  String? _selectedPlanId;
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _generated = [];
  bool _loading = false;
  bool _savingPdf = false;

  @override
  void initState() {
    super.initState();
    VenueStateService.instance.venueNotifier.addListener(_onVenueChanged);
    VenueStateService.instance.plansNotifier.addListener(_onPlansChanged);
    _onVenueChanged();
    _onPlansChanged();
    _loadVenues();
  }

  @override
  void dispose() {
    VenueStateService.instance.venueNotifier.removeListener(_onVenueChanged);
    VenueStateService.instance.plansNotifier.removeListener(_onPlansChanged);
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _onVenueChanged() {
    final v = VenueStateService.instance.currentVenue;
    if (v != null && mounted) {
      final vId = v['id']?.toString();
      final vName = v['name']?.toString() ?? 'WavePass Venue';
      setState(() {
        _venues = [{'id': vId, 'name': vName}];
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
        final vName = venue['name']?.toString() ?? 'WavePass Venue';
        final vMap = {'id': vId, 'name': vName};
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
    try {
      final res = await http.post(
        Uri.parse('${ApiConstants.cloudBaseUrl}/api/v1/vouchers/batches'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'venueId': _selectedVenueId,
          'planId': _selectedPlanId,
          'quantity': qty,
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode >= 400) {
        throw Exception('Server error ${res.statusCode}: ${res.body}');
      }
      final data = jsonDecode(res.body);
      final list = (data is List ? data : data['codes'] ?? data) as List;
      setState(() {
        _generated = list.map((e) => e is String ? {'code': e} : Map<String, dynamic>.from(e)).toList();
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

  Future<void> _savePdf() async {
    if (_generated.isEmpty) return;
    setState(() => _savingPdf = true);
    try {
      final pdf = pw.Document();
      final venueName = _venues.firstWhere((v) => v['id'] == _selectedVenueId, orElse: () => {'name': 'WavePass Venue'})['name'];
      final planName = _plans.firstWhere((p) => p['id'] == _selectedPlanId, orElse: () => {'name': 'Pass'})['name'];
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('WavePass Vouchers', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(DateTime.now().toLocal().toString().split(' ')[0], style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          ]),
          build: (ctx) => [
            pw.SizedBox(height: 8),
            pw.Text('Venue: $venueName • Plan: $planName • ${DateTime.now().toLocal()}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['#', 'Voucher Code', 'Status'],
              data: List.generate(_generated.length, (i) => ['${i + 1}', _generated[i]['code'].toString(), 'ISSUED']),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey900),
              cellStyle: const pw.TextStyle(fontSize: 9),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
              cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.center, 2: pw.Alignment.center},
              columnWidths: {0: const pw.FixedColumnWidth(40), 2: const pw.FixedColumnWidth(80)},
            ),
            pw.SizedBox(height: 16),
            pw.Text('Instructions: Guest connects to venue Wi-Fi, enters code on portal. One-time use. Keep secure.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      );

      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/wavepass_vouchers_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);
      // also try downloads on Android
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dl = File('${extDir.path}/wavepass_vouchers_${DateTime.now().millisecondsSinceEpoch}.pdf');
          await dl.writeAsBytes(bytes);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF saved: ${dl.path}')));
          await OpenFile.open(dl.path);
          return;
        }
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF saved: ${file.path}')));
      await OpenFile.open(file.path);
      // also offer print/share
      await Printing.sharePdf(bytes: bytes, filename: 'wavepass_vouchers.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF failed: $e')));
    } finally {
      setState(() => _savingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Batch Vouchers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [if (_generated.isNotEmpty) IconButton(icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary), onPressed: _savingPdf ? null : _savePdf, tooltip: 'Save PDF')],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Create Multiple Vouchers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const SizedBox(height: 4),
              const Text('Select venue & plan, set quantity (1-500), generate codes, then save as PDF to device.', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
              const SizedBox(height: 16),
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
              DropdownButtonFormField<String>(
                key: ValueKey('plan_$_selectedPlanId'),
                initialValue: (_selectedPlanId != null && _plans.any((p) => p['id'] == _selectedPlanId))
                    ? _selectedPlanId
                    : null,
                decoration: const InputDecoration(labelText: 'Plan', border: OutlineInputBorder()),
                items: _plans.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text('${p['name']} — ₦${(p['priceMinor'] as int) ~/ 100}'))).toList(),
                onChanged: (val) => setState(() => _selectedPlanId = val),
              ),
              const SizedBox(height: 12),
              TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity (1-500)', border: OutlineInputBorder(), hintText: '10')),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _generateBatch,
                  icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.confirmation_number_rounded),
                  label: Text(_loading ? 'Generating...' : 'Generate ${(_qtyCtrl.text.isEmpty ? 10 : int.tryParse(_qtyCtrl.text) ?? 10)} Vouchers'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (_generated.isNotEmpty) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${_generated.length} Vouchers Ready', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
              FilledButton.icon(onPressed: _savingPdf ? null : _savePdf, icon: _savingPdf ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16), label: const Text('Save PDF to Device')),
            ]),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _generated.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0x0F000000)),
                itemBuilder: (c, i) => ListTile(
                  dense: true,
                  leading: Container(width: 28, height: 28, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)), child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))),
                  title: Text(_generated[i]['code'].toString(), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 13)),
                  trailing: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textLight),
                  onTap: () {
                    // copy to clipboard
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
