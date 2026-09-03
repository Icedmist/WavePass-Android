import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';

class PlanConfiguratorSheet extends StatefulWidget {
  const PlanConfiguratorSheet({super.key});
  @override
  State<PlanConfiguratorSheet> createState() => _PState();
}

class _PState extends State<PlanConfiguratorSheet> {
  final _name = TextEditingController(text: 'Custom Pass');
  final _price = TextEditingController(text: '500');
  double _hours = 2;
  double _gb = 0; // 0 = unlimited
  final _speed = TextEditingController(text: '10M');
  double _devices = 1;
  bool _saving = false;

  @override
  void dispose() { _name.dispose(); _price.dispose(); _speed.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final venue = await SupabaseService.instance.getPrimaryVenue();
      final venueId = venue?['id'] as String? ?? 'default';
      final priceMinor = (int.tryParse(_price.text) ?? 0) * 100;
      final durationSeconds = (_hours * 3600).round();
      final dataLimitBytes = _gb == 0 ? null : (_gb * 1024 * 1024 * 1024).round();
      // Supabase insert Plan
      await SupabaseService.instance.client.from('Plan').insert({
        'venueId': venueId,
        'name': _name.text.trim().isEmpty ? 'Custom Pass' : _name.text.trim(),
        'priceMinor': priceMinor,
        'durationSeconds': durationSeconds,
        'dataLimitBytes': dataLimitBytes,
        'rateLimit': _speed.text.trim().isEmpty ? null : _speed.text.trim(),
        'simultaneousDevices': _devices.round(),
        'mode': 'ELAPSED',
        'active': true,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom plan created'), backgroundColor: AppColors.accentGreen));
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
      const SizedBox(height: 12),
      Text('Duration: ${_hours.toStringAsFixed(1)}h', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      Slider(value: _hours, min: 0.5, max: 72, divisions: 143, label: '${_hours}h', onChanged: (v) => setState(() => _hours = v)),
      Text('Data cap: ${_gb == 0 ? "Unlimited" : "${_gb.toStringAsFixed(1)} GB"}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      Slider(value: _gb, min: 0, max: 50, divisions: 50, label: _gb == 0 ? 'Unlimited' : '${_gb}GB', onChanged: (v) => setState(() => _gb = v)),
      _field('Speed (e.g. 10M)', _speed),
      Text('Devices: ${_devices.round()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      Slider(value: _devices, min: 1, max: 5, divisions: 4, label: '${_devices.round()}', onChanged: (v) => setState(() => _devices = v)),
      const SizedBox(height: 16),
      SizedBox(height: 52, child: ElevatedButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Custom Plan', style: TextStyle(fontWeight: FontWeight.w800)))),
    ])));
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textMuted)), const SizedBox(height: 6), TextField(controller: c, keyboardType: type, decoration: InputDecoration(hintText: label))]));
  static Future<bool?> open(BuildContext c) => showModalBottomSheet<bool>(context: c, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const PlanConfiguratorSheet());
}
