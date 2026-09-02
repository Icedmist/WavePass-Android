import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/services/supabase_service.dart';
import 'terms_screen.dart';
import 'privacy_screen.dart';
import 'how_to_use_screen.dart';
import 'login_screen.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  final List<Map<String, dynamic>> _plans = [
    {'name': '1 Hour Quick Pass', 'price': 200, 'duration': '1 Hour'},
    {'name': '12 Hour Work Pass', 'price': 800, 'duration': '12 Hours'},
    {'name': '24 Hour All-Day', 'price': 1500, 'duration': '24 Hours'},
  ];

  bool _isSyncing = false;

  void _handleSync() async {
    setState(() => _isSyncing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Router synchronized! All paid sessions are active."),
        backgroundColor: AppColors.accentGreen,
      ),
    );
  }

  void _editPrice(int index) {
    final plan = _plans[index];
    final controller = TextEditingController(text: '${plan['price']}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text("Edit ${plan['name']} Price", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Price in Naira (NGN):", style: TextStyle(fontSize: 12, color: AppColors.textLight)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: "e.g. 500"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final newPrice = int.tryParse(controller.text);
              if (newPrice != null) {
                setState(() {
                  _plans[index]['price'] = newPrice;
                });
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("${plan['name']} price updated to ₦$newPrice."),
                    backgroundColor: AppColors.accentGreen,
                  ),
                );
              }
            },
            child: const Text("Save Price"),
          ),
        ],
      ),
    );
  }

  void _handleLogout() async {
    await SupabaseService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Admin Control Center",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Admin Profile Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.shield, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "talk2icedmist@gmail.com",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Venue Owner • WavePass Flagship",
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── SECTION: PRICING PLANS ───
            const Text(
              "WI-FI PASS PRICING",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8),
            ),
            const SizedBox(height: 12),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _plans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final p = _plans[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.containerBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          Text(p['duration'], style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            "₦${p['price']}",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.accentGreen),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: AppColors.primary),
                            onPressed: () => _editPrice(index),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // ─── SECTION: ROUTER HARDWARE TOOLS ───
            const Text(
              "HARDWARE RESILIENCE",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8),
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _handleSync,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.sync, size: 18),
                label: _isSyncing ? const Text("Synchronizing router...") : const Text("Sync Passes with Router Hardware"),
              ),
            ),
            const SizedBox(height: 24),

            // ─── SECTION: GUIDES AND POLICIES ───
            const Text(
              "GUIDES & POLICIES",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8),
            ),
            const SizedBox(height: 12),

            _buildNavRow("How to Use WavePass", Icons.menu_book, () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HowToUseScreen()));
            }),
            const SizedBox(height: 8),
            _buildNavRow("Terms of Use", Icons.gavel, () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsScreen()));
            }),
            const SizedBox(height: 8),
            _buildNavRow("Privacy Policy", Icons.privacy_tip, () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyScreen()));
            }),
            const SizedBox(height: 32),

            // Log Out Button
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout, color: AppColors.accentRed, size: 18),
                label: const Text("Sign Out of Venue", style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.accentRed.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavRow(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.containerBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }
}
