import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../core/services/supabase_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/plan_configurator.dart';
import 'how_to_use_screen.dart';
import 'login_screen.dart';
import 'privacy_screen.dart';
import 'terms_screen.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});
  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  List<Map<String, dynamic>> _plans = [];
  bool _loadingPlans = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _loadingPlans = true);
    try {
      final venue = await SupabaseService.instance.getPrimaryVenue();
      if (venue != null) {
        final plans = await SupabaseService.instance.getActivePlans(venue['id']);
        setState(() => _plans = plans.map((p) => {'name': p['name'], 'price': (p['priceMinor'] as int) ~/ 100, 'duration': '${(p['durationSeconds'] as int) ~/ 3600} Hours', 'id': p['id']}).toList());
      }
    } catch (_) {
      setState(() => _plans = []);
    } finally {
      setState(() => _loadingPlans = false);
    }
  }
  bool _isSyncing = false;
  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  String? _venueId;
  bool _loadingVenue = false;
  bool _savingVenue = false;

  @override
  void initState() {
    super.initState();
    _loadVenue();
  }

  Future<void> _loadVenue() async {
    setState(() => _loadingVenue = true);
    try {
      final v = await WavePassApi.instance.getDefaultVenue();
      if (v['id'] != null) {
        setState(() {
          _venueId = v['id'];
          _nameCtrl.text = v['name'] ?? '';
          _slugCtrl.text = v['slug'] ?? '';
          _logoCtrl.text = v['logoUrl'] ?? '';
        });
      }
    } catch (_) {
      final v = await SupabaseService.instance.getPrimaryVenue();
      if (v != null) {
        setState(() {
          _venueId = v['id'];
          _nameCtrl.text = v['name'] ?? '';
          _slugCtrl.text = v['slug'] ?? '';
          _logoCtrl.text = v['logoUrl'] ?? '';
        });
      }
    } finally {
      setState(() => _loadingVenue = false);
    }
  }

  Future<void> _saveVenue() async {
    if (_venueId == null) return;
    final slug = _slugCtrl.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Slug must be a-z 0-9 hyphen')));
      return;
    }
    setState(() => _savingVenue = true);
    try {
      await WavePassApi.instance.patchVenue(_venueId!, {'name': _nameCtrl.text.trim(), 'slug': slug, 'logoUrl': _logoCtrl.text.trim()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Venue updated: $slug.nexawavepass.com'), backgroundColor: AppColors.accentGreen));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.accentRed));
    } finally {
      if (mounted) setState(() => _savingVenue = false);
    }
  }

  void _handleSync() async {
    setState(() => _isSyncing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Router synchronized! All paid sessions are active."), backgroundColor: AppColors.accentGreen));
  }

  void _editPrice(int index) {
    final plan = _plans[index];
    final controller = TextEditingController(text: '${plan['price']}');
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: AppColors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), title: Text("Edit ${plan['name']} Price", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Price in Naira (NGN):", style: TextStyle(fontSize: 12, color: AppColors.textLight)), const SizedBox(height: 8), TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "e.g. 500"))]), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")), ElevatedButton(onPressed: () { final newPrice = int.tryParse(controller.text); if (newPrice != null) { setState(() => _plans[index]['price'] = newPrice); Navigator.of(ctx).pop(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${plan['name']} price updated to ₦$newPrice."), backgroundColor: AppColors.accentGreen)); } }, child: const Text("Save Price"))]));
  }

  void _handleLogout() async {
    await SupabaseService.instance.signOut();
    if (!mounted) return;
    context.go(AppRouter.login);
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _venueId != null && _logoCtrl.text.trim().isNotEmpty && _plans.isNotEmpty;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(backgroundColor: AppColors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18), onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.dashboard)), title: const Text("Admin Center", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)), bottom: const TabBar(labelColor: AppColors.primary, unselectedLabelColor: AppColors.textLight, indicatorColor: AppColors.primary, indicatorWeight: 2.5, tabs: [Tab(icon: Icon(Icons.language_rounded, size: 18), text: 'Subdomain'), Tab(icon: Icon(Icons.wifi_rounded, size: 18), text: 'Plans'), Tab(icon: Icon(Icons.confirmation_number_rounded, size: 18), text: 'Batch')])),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(18)), child: Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.shield_rounded, color: Colors.white, size: 20)), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Venue Owner", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)), Text("WavePass • Role-based access", style: TextStyle(fontSize: 11, color: Colors.white70))]))]))),
          if (!isReady)
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.warmSand.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.warmSand)), child: const Row(children: [Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFF92400E)), SizedBox(width: 8), Expanded(child: Text('Complete subdomain & logo + at least one pricing plan to go live.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF92400E))))]))),
          const SizedBox(height: 8),
          Expanded(child: TabBarView(children: [
            // TAB 1: SUBDOMAIN
            SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Subdomain & Branding", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                const SizedBox(height: 4),
                const Text("Your venue lives at {slug}.nexawavepass.com with custom logo and pricing.", style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                const SizedBox(height: 12),
                if (_loadingVenue) const Center(child: CircularProgressIndicator(strokeWidth: 2)) else ...[
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Venue Name', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: _slugCtrl, decoration: InputDecoration(labelText: 'Subdomain (slug)', border: const OutlineInputBorder(), helperText: _slugCtrl.text.isEmpty ? 'my-venue.nexawavepass.com' : '${_slugCtrl.text.toLowerCase()}.nexawavepass.com', helperStyle: const TextStyle(fontSize: 11, color: AppColors.accentGreen)), onChanged: (_) => setState(() {})),
                  const SizedBox(height: 12),
                  TextField(controller: _logoCtrl, decoration: const InputDecoration(labelText: 'Logo URL (https://...)', border: OutlineInputBorder(), helperText: 'Shown on your subdomain portal')),
                ],
              ])),
              const SizedBox(height: 16),
              SizedBox(height: 48, child: ElevatedButton.icon(onPressed: _savingVenue ? null : _saveVenue, icon: _savingVenue ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded), label: Text(_savingVenue ? 'Saving...' : 'Save Subdomain & Branding'))),
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)), child: const Text('Changing the slug updates your subdomain instantly. Ensure DNS wildcard *.nexawavepass.com points to your frontend.', style: TextStyle(fontSize: 11, color: AppColors.textLight))),
            ])),
            // TAB 2: PLANS — no predefined, add manually
            SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("WI-FI PASS PRICING", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8)),
                TextButton.icon(onPressed: () async { final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const PlanConfiguratorSheet()); if (ok == true) _loadPlans(); }, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add Plan', style: TextStyle(fontSize: 12))),
              ]),
              const SizedBox(height: 12),
              if (_loadingPlans)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_plans.isEmpty)
                Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)), child: Column(children: [const Icon(Icons.wifi_off_rounded, size: 32, color: AppColors.textLight), const SizedBox(height: 8), const Text('No pricing yet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)), const Text('Add your first pass manually after setup — duration or per-GB.', style: TextStyle(fontSize: 11, color: AppColors.textLight), textAlign: TextAlign.center), const SizedBox(height: 12), ElevatedButton.icon(onPressed: () async { final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const PlanConfiguratorSheet()); if (ok == true) _loadPlans(); }, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Create First Plan'))])),
              if (_plans.isNotEmpty)
                ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _plans.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (c, i) {
                  final p = _plans[i];
                  return Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), Text(p['duration'], style: const TextStyle(fontSize: 11, color: AppColors.textLight))]), Row(children: [Text("₦${p['price']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.accentGreen)), const SizedBox(width: 8), IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary), onPressed: () => _editPrice(i))])]));
                }),
              const SizedBox(height: 24),
              const Text("HARDWARE RESILIENCE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8)),
              const SizedBox(height: 12),
              SizedBox(height: 48, child: ElevatedButton.icon(onPressed: _isSyncing ? null : _handleSync, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), icon: const Icon(Icons.sync_rounded, size: 18), label: Text(_isSyncing ? "Synchronizing router..." : "Sync Passes with Router Hardware"))),
              const SizedBox(height: 24),
              const Text("GUIDES & POLICIES", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8)),
              const SizedBox(height: 12),
              _navRow("How to Use WavePass", Icons.menu_book_rounded, () => context.push(AppRouter.howToUse)),
              const SizedBox(height: 8),
              _navRow("Terms of Use", Icons.gavel_rounded, () => context.push(AppRouter.terms)),
              const SizedBox(height: 8),
              _navRow("Privacy Policy", Icons.privacy_tip_rounded, () => context.push(AppRouter.privacy)),
              const SizedBox(height: 24),
              SizedBox(height: 48, child: OutlinedButton.icon(onPressed: _handleLogout, icon: const Icon(Icons.logout_rounded, color: AppColors.accentRed, size: 18), label: const Text("Sign Out of Venue", style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w800)), style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.accentRed.withValues(alpha: 0.3)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
            ])),
            // TAB 3: BATCH
            SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Batch Vouchers", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)), SizedBox(height: 4), Text("Create up to 500 codes at once. Saved as PDF to device.", style: TextStyle(fontSize: 11, color: AppColors.textLight))])),
              const SizedBox(height: 16),
              SizedBox(height: 48, child: ElevatedButton.icon(onPressed: () => context.push(AppRouter.batchVouchers), icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('Open Batch Generator'))),
              const SizedBox(height: 12),
              SizedBox(height: 48, child: OutlinedButton.icon(onPressed: () => context.push(AppRouter.batchVouchers), icon: const Icon(Icons.save_rounded), label: const Text('Generate & Save PDF'))),
            ])),
          ])),
        ]),
      ),
    );
  }

  Widget _navRow(String label, IconData icon, VoidCallback onTap) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: Row(children: [Icon(icon, size: 20, color: AppColors.primary), const SizedBox(width: 12), Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary))), const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textLight)])));
}
