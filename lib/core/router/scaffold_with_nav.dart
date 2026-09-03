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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _go,
          backgroundColor: AppColors.white,
          indicatorColor: AppColors.primary.withValues(alpha: 0.10),
          elevation: 0,
          height: 72,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.dashboard_outlined, color: AppColors.textLight), selectedIcon: Icon(Icons.dashboard, color: AppColors.primary), label: 'Home'),
            const NavigationDestination(icon: Icon(Icons.devices_outlined, color: AppColors.textLight), selectedIcon: Icon(Icons.devices, color: AppColors.primary), label: 'Devices'),
            NavigationDestination(
              icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.accentRed, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long, color: Colors.white, size: 22)),
              selectedIcon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.accentRed, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long, color: Colors.white, size: 22)),
              label: 'Sell',
            ),
            const NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined, color: AppColors.textLight), selectedIcon: Icon(Icons.account_balance_wallet, color: AppColors.primary), label: 'Wallet'),
            const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined, color: AppColors.textLight), selectedIcon: Icon(Icons.admin_panel_settings, color: AppColors.primary), label: 'Admin'),
          ],
        ),
      ),
    );
  }
}
