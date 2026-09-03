import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class ScaffoldWithNav extends StatelessWidget {
  const ScaffoldWithNav({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  void _go(int i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              backgroundColor: AppColors.white,
              indicatorColor: AppColors.primary.withValues(alpha: 0.08),
              elevation: 0,
              height: 68,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_rounded, color: AppColors.textLight),
                  selectedIcon: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.home_rounded, color: Colors.white, size: 18), SizedBox(width: 6), Text('Home', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))])),
                  label: 'Home',
                ),
                const NavigationDestination(icon: Icon(Icons.devices_other_rounded, color: AppColors.textLight), selectedIcon: Icon(Icons.devices_other_rounded, color: AppColors.primary), label: 'Devices'),
                NavigationDestination(
                  icon: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: AppColors.accentRed, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Color(0x4DDC2626), blurRadius: 12, offset: Offset(0, 4))]), child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 20)),
                  selectedIcon: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 20)),
                  label: 'Sell',
                ),
                const NavigationDestination(icon: Icon(Icons.account_balance_wallet_rounded, color: AppColors.textLight), selectedIcon: Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary), label: 'Wallet'),
                const NavigationDestination(icon: Icon(Icons.admin_panel_settings_rounded, color: AppColors.textLight), selectedIcon: Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary), label: 'Admin'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
