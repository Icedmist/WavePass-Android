import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';

class PlanConfiguratorSheet extends StatefulWidget {
  const PlanConfiguratorSheet({super.key, this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<PlanConfiguratorSheet> createState() => _PState();
}

class _PState extends State<PlanConfiguratorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _speed;
  late final TextEditingController _daysCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _gigsCtrl;
  late double _hours;
  late double _gb;
  late double _devices;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final durSec = (e?['durationSeconds'] as int?) ?? 7200;
    _hours = durSec / 3600;
    final limitBytes = e?['dataLimitBytes'];
    _gb = limitBytes == null ? 0 : (limitBytes as num).toDouble() / (1024 * 1024 * 1024);
    _devices = ((e?['simultaneousDevices'] as int?) ?? 1).toDouble();
    _name = TextEditingController(text: e?['name'] ?? 'Custom Pass');
    _price = TextEditingController(text: e != null ? ((e['priceMinor'] as int) ~/ 100).toString() : '500');
    _speed = TextEditingController(text: e?['rateLimit'] ?? '10M');
    _daysCtrl = TextEditingController(text: (_hours / 24).toStringAsFixed(2));
    _hoursCtrl = TextEditingController(text: _hours.toStringAsFixed(1));
    _gigsCtrl = TextEditingController(text: _gb == 0 ? '' : _gb.toStringAsFixed(1));
  }

  @override
  void dispose() { _name.dispose(); _price.dispose(); _speed.dispose(); _daysCtrl.dispose(); _hoursCtrl.dispose(); _gigsCtrl.dispose(); super.dispose(); }

  void _syncFromDays(String v) {
    final d = double.tryParse(v) ?? 0;
    setState(() { _hours = (d * 24).clamp(0.5, 72); _hoursCtrl.text = _hours.toStringAsFixed(1); _daysCtrl.text = v; });
  }

  void _syncFromHours(String v) {
    final h = double.tryParse(v) ?? 0;
    setState(() { _hours = h.clamp(0.5, 72); _daysCtrl.text = (_hours / 24).toStringAsFixed(2); });
  }

  void _syncFromGigs(String v) {
    if (v.trim().isEmpty) { setState(() => _gb = 0); return; }
    final g = double.tryParse(v) ?? 0;
    setState(() => _gb = g.clamp(0, 50));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final venue = await SupabaseService.instance.getPrimaryVenue();
      final venueId = venue?['id'] as String? ?? 'default';
      final priceMinor = (int.tryParse(_price.text) ?? 0) * 100;
      final durationSeconds = (_hours * 3600).round();
      final dataLimitBytes = _gb == 0 ? null : (_gb * 1024 * 1024 * 1024).round();
      final payload = {
        'venueId': venueId,
        'name': _name.text.trim().isEmpty ? 'Custom Pass' : _name.text.trim(),
        'priceMinor': priceMinor,
        'durationSeconds': durationSeconds,
        'dataLimitBytes': dataLimitBytes,
        'rateLimit': _speed.text.trim().isEmpty ? null : _speed.text.trim(),
        'simultaneousDevices': _devices.round(),
        'mode': 'ELAPSED',
        'active': true,
      };
      if (widget.existing != null) {
        await SupabaseService.instance.client.from('Plan').update(payload).eq('id', widget.existing!['id']);
      } else {
        await SupabaseService.instance.client.from('Plan').insert(payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.existing != null ? 'Plan updated' : 'Custom plan created'), backgroundColor: AppColors.accentGreen));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.accentRed));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95, builder: (c, ctrl) => Container(decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))), child: ListView(controller: ctrl, padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), children: [
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      const Text('Customize What You Sell', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
      const Text('Set duration or per-GB cap, price, speed and devices.', style: TextStyle(fontSize: 12, color: AppColors.textLight)),
      const SizedBox(height: 16),
      _field('Plan name', _name),
      _field('Price (NGN)', _price, type: TextInputType.number),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field('Days', _daysCtrl, type: TextInputType.number, onChanged: _syncFromDays)),
        const SizedBox(width: 12),
        Expanded(child: _field('Hours', _hoursCtrl, type: TextInputType.number, onChanged: _syncFromHours)),
      ]),
      Text('Duration: ${_hours.toStringAsFixed(1)}h (${(_hours/24).toStringAsFixed(2)} days)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      Slider(value: _hours, min: 0.5, max: 72, divisions: 143, label: '${_hours.toStringAsFixed(1)}h', onChanged: (v) => setState(() { _hours = v; _hoursCtrl.text = v.toStringAsFixed(1); _daysCtrl.text = (v/24).toStringAsFixed(2); })),
      Row(children: [
        Expanded(child: _field('Data gigs (empty = Unlimited)', _gigsCtrl, type: TextInputType.number, onChanged: _syncFromGigs)),
        const SizedBox(width: 12),
        Expanded(child: _field('Speed (e.g. 10M)', _speed)),
      ]),
      Text('Data cap: ${_gb == 0 ? "Unlimited" : "${_gb.toStringAsFixed(1)} GB"}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      Slider(value: _gb, min: 0, max: 50, divisions: 50, label: _gb == 0 ? 'Unlimited' : '${_gb.toStringAsFixed(1)}GB', onChanged: (v) => setState(() { _gb = v; _gigsCtrl.text = v == 0 ? '' : v.toStringAsFixed(1); })),
      Text('Devices: ${_devices.round()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      Slider(value: _devices, min: 1, max: 5, divisions: 4, label: '${_devices.round()}', onChanged: (v) => setState(() => _devices = v)),
      const SizedBox(height: 16),
      SizedBox(height: 52, child: ElevatedButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.existing != null ? 'Save Changes' : 'Create Custom Plan', style: const TextStyle(fontWeight: FontWeight.w800)))),
    ])));
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type, ValueChanged<String>? onChanged}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textMuted)), const SizedBox(height: 6), TextField(controller: c, keyboardType: type, onChanged: onChanged, decoration: InputDecoration(hintText: label))]));
  static Future<bool?> open(BuildContext c) => showModalBottomSheet<bool>(context: c, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const PlanConfiguratorSheet());
}
