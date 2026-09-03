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
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 32, spreadRadius: 2, offset: const Offset(0, 12)), BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              backgroundColor: AppColors.white,
              indicatorColor: Colors.transparent,
              elevation: 0,
              height: 68,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_rounded, color: AppColors.textLight),
                  selectedIcon: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.home_rounded, color: Colors.white, size: 20)),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.devices_other_rounded, color: AppColors.textLight),
                  selectedIcon: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.devices_other_rounded, color: Colors.white, size: 20)),
                  label: 'Devices',
                ),
                NavigationDestination(
                  icon: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: AppColors.accentRed, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 20)),
                  selectedIcon: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 20)),
                  label: 'Sell',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.textLight),
                  selectedIcon: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20)),
                  label: 'Wallet',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.textLight),
                  selectedIcon: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 20)),
                  label: 'Admin',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
