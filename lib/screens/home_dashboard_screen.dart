import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/services/supabase_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/theme/app_theme.dart';
import '../core/router/app_router.dart';
import '../core/services/notification_service.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _activeUsers = 0;
  int _todaySales = 0;
  String _venueName = 'Your Venue';
  String _venueSub = '—';
  bool _hasRouter = false;
  bool _routerOnline = false;
  String _routerName = '';
  String _routerEndpoint = '';
  bool _loadingStats = true;
  String? _venueId;
  List<Map<String, dynamic>> _recentSales = [];

  @override
  void initState() {
    super.initState();
    VenueStateService.instance.venueNotifier.addListener(_onVenueChanged);
    _onVenueChanged();
    _loadDashboard();
  }

  @override
  void dispose() {
    VenueStateService.instance.venueNotifier.removeListener(_onVenueChanged);
    super.dispose();
  }

  void _onVenueChanged() {
    final v = VenueStateService.instance.currentVenue;
    if (v != null && mounted) {
      setState(() {
        _venueName = v['name']?.toString() ?? 'Your Venue';
        _venueSub = v['slug'] != null ? '${v['slug']}.nexawavepass.com' : '—';
      });
    }
  }

  Future<void> _loadDashboard() async {
    try {
      var venue = VenueStateService.instance.currentVenue;
      venue ??= await VenueStateService.instance.refreshVenue();
      String? vid = venue?['id']?.toString();
      if (venue != null) {
        if (!mounted) return;
        setState(() {
          _venueName = venue!['name'] ?? 'Your Venue';
          _venueSub = venue['slug'] != null ? '${venue['slug']}.nexawavepass.com' : '—';
        });
        vid = venue['id'] as String?;
        _venueId = vid;
        if (vid != null) {
          try {
            final plans = await SupabaseService.instance.getActivePlans(vid);
            if (plans.isEmpty) {
              // no predefined pricing — prompt to add
            }
          } catch (_) {}
          try {
            final sessions = await SupabaseService.instance.getActiveSessions(vid);
            if (mounted) setState(() => _activeUsers = sessions.length);
          } catch (_) {}
          try {
            final orders = await SupabaseService.instance.client.from('Order').select('id, customerRef, amountMinor, createdAt, Plan(name)').eq('venueId', vid).order('createdAt', ascending: false).limit(5);
            if (mounted) {
              setState(() => _recentSales = List<Map<String, dynamic>>.from(orders).map((o) => {'code': o['customerRef'] ?? o['id'].toString().substring(0, 8).toUpperCase(), 'plan': o['Plan']?['name'] ?? 'Pass', 'amount': '₦${((o['amountMinor'] as int) ~/ 100)}', 'time': _timeAgo(o['createdAt'])}).toList());
            }
          } catch (_) {}
        }
      }
      try {
        final stats = await WavePassApi.instance.adminStats();
        if (mounted) {
          if (stats['revenue'] != null) setState(() => _todaySales = (stats['revenue']['totalNGN'] as num?)?.toInt() ?? 0);
          if (stats['sessions'] != null && _activeUsers == 0) setState(() => _activeUsers = (stats['sessions']['active'] as num?)?.toInt() ?? _activeUsers);
        }
      } catch (_) {}
      // check router status truthfully from database and hardware health
      try {
        final venueForRouter = venue ?? await SupabaseService.instance.getPrimaryVenue();
        if (venueForRouter != null) {
          final res = await SupabaseService.instance.client
              .from('Router')
              .select('id, name, endpoint, status, connectionMode, lastSeen')
              .eq('venueId', venueForRouter['id'])
              .limit(1);
          final list = res as List;
          if (list.isNotEmpty) {
            final r = list.first as Map<String, dynamic>;
            final rStatus = r['status']?.toString() ?? 'OFFLINE';
            final rId = r['id']?.toString();
            final isOnline = rStatus == 'ONLINE';
            if (mounted) {
              setState(() {
                _hasRouter = true;
                _routerName = r['name']?.toString() ?? 'MikroTik Gateway';
                _routerEndpoint = r['endpoint']?.toString() ?? '';
                _routerOnline = isOnline;
              });
            }
            if (rId != null) {
              WavePassApi.instance.getRouterHealth(rId).then((health) {
                if (mounted && (health['status'] != null || health['reachable'] != null)) {
                  setState(() {
                    _routerOnline = health['status'] == 'ONLINE' || health['reachable'] == true;
                  });
                }
              }).catchError((_) {});
            }
          } else {
            if (mounted) {
              setState(() {
                _hasRouter = false;
                _routerOnline = false;
                _routerName = '';
                _routerEndpoint = '';
              });
            }
          }
        }
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  String _timeAgo(dynamic iso) {
    try {
      final dt = DateTime.parse(iso.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Hero(
                tag: 'wavepass-logo',
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _venueName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _venueSub,
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<List<AppNotification>>(
            valueListenable: AppNotifier.instance.feed,
            builder: (c, items, _) => Stack(children: [
              IconButton(icon: const Icon(Icons.notifications_none_rounded, color: AppColors.primary), tooltip: 'Notifications', onPressed: () => context.push(AppRouter.notifications)),
              if (AppNotifier.instance.unread > 0) Positioned(right: 8, top: 8, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accentRed, shape: BoxShape.circle))),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: AppColors.primary, size: 20),
            tooltip: "How to Use",
            onPressed: () => context.push(AppRouter.howToUse),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: AppColors.primary, size: 22),
            tooltip: "Account Center & Sign Out",
            onPressed: () => context.push(AppRouter.account),
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary, size: 22),
            tooltip: "Admin Control",
            onPressed: () => context.go(AppRouter.admin),
          ),
          InkWell(
            onTap: () {
              if (_hasRouter) {
                context.push(AppRouter.routerDiagnostics);
              } else {
                context.push(AppRouter.routerSetup);
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _routerOnline
                    ? AppColors.accentGreen.withValues(alpha: 0.1)
                    : _hasRouter
                        ? AppColors.accentRed.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _routerOnline
                      ? AppColors.accentGreen.withValues(alpha: 0.3)
                      : _hasRouter
                          ? AppColors.accentRed.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _routerOnline
                          ? AppColors.accentGreen
                          : _hasRouter
                              ? AppColors.accentRed
                              : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _routerOnline
                        ? "ONLINE"
                        : _hasRouter
                            ? "OFFLINE"
                            : "NO ROUTER",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _routerOnline
                          ? AppColors.accentGreen
                          : _hasRouter
                              ? AppColors.accentRed
                              : Colors.orange.shade800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_hasRouter && !_loadingStats)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warmSand.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.warmSand)),
                child: Row(children: [
                  const Icon(Icons.router_rounded, size: 18, color: Color(0xFF92400E)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Router not yet set up — you can skip, but guests cannot connect until a router is added.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF92400E)))),
                  TextButton(onPressed: () => context.push(AppRouter.routerSetup), child: const Text('Set Up', style: TextStyle(fontSize: 11))),
                ]),
              ),
            // ─── CARD 1: TODAY REVENUE & SUMMARY ───
            InkWell(
              onTap: () => _showSalesBreakdownSheet(context),
              borderRadius: BorderRadius.circular(26),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.containerBg,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "TODAY'S WI-FI EARNINGS",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textLight,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Breakdown",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "₦${_todaySales.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}",
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "NGN",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "+18% from yesterday",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentGreen,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            "${_recentSales.isNotEmpty ? _recentSales.length : 24} paid passes sold",
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── ROW STATS: PEOPLE ONLINE & ROUTER HEALTH ───
            Row(
              children: [
                // STAT 1: ACTIVE USERS
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "PEOPLE ONLINE",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textLight,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "$_activeUsers",
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppColors.accentGreen,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Using Wi-Fi now",
                          style: TextStyle(fontSize: 11, color: AppColors.textLight),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // STAT 2: ROUTER CONNECTIVITY STATUS (REAL HARDWARE STATE)
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (_hasRouter) {
                        context.push(AppRouter.routerDiagnostics);
                      } else {
                        context.push(AppRouter.routerSetup);
                      }
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _routerOnline
                              ? AppColors.accentGreen.withValues(alpha: 0.3)
                              : _hasRouter
                                  ? AppColors.accentRed.withValues(alpha: 0.3)
                                  : AppColors.cardBorder,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "MIKROTIK ROUTER",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textLight,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _routerOnline
                                      ? AppColors.accentGreen
                                      : _hasRouter
                                          ? AppColors.accentRed
                                          : Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _routerOnline
                                ? "ONLINE"
                                : _hasRouter
                                    ? "OFFLINE"
                                    : "UNLINKED",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _routerOnline
                                  ? AppColors.accentGreen
                                  : _hasRouter
                                      ? AppColors.accentRed
                                      : Colors.orange.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _routerOnline
                                ? (_routerName.isNotEmpty
                                    ? (_routerEndpoint.isNotEmpty
                                        ? "$_routerName • ${_routerEndpoint.replaceAll('http://', '').replaceAll('https://', '')}"
                                        : "$_routerName • Connected")
                                    : "RouterOS • Connected")
                                : _hasRouter
                                    ? "Tap to check health"
                                    : "Tap to pair router",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ─── PRIMARY 1-TAP CASH PASS ACTION ───
            InkWell(
              onTap: () => context.go(AppRouter.sellPass),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.accentRed,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentRed.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text("Sell a Cash Pass", maxLines: 1, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white))),
                          SizedBox(height: 2),
                          Text("8-letter code & print receipt in 1 tap", maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.3)),
                        ],
                      ),
                    ),
                    SizedBox(width: 20, child: Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ─── SECTION TITLE ───
            const Text(
              "QUICK ACTIONS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),

            // ─── FEATURE ACTIONS GRID ───
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                // ACTION 1: ROUTER SETUP
                _buildActionCard(
                  title: "Set Up a Router",
                  subtitle: "Wi-Fi auto-find & barcode scan",
                  icon: Icons.router,
                  onTap: () => context.push(AppRouter.routerSetup),
                ),

                // ACTION 2: ACTIVE DEVICES
                _buildActionCard(
                  title: "Active Devices",
                  subtitle: "$_activeUsers people connected",
                  icon: Icons.devices,
                  onTap: () => context.go(AppRouter.activeDevices),
                ),

                // ACTION 3: ROUTER HEALTH
                _buildActionCard(
                  title: "Router Health",
                  subtitle: "Live CPU & memory load",
                  icon: Icons.speed,
                  onTap: () => context.push(AppRouter.routerDiagnostics),
                ),

                // ACTION 4: BLUETOOTH PRINTER
                _buildActionCard(
                  title: "Pocket Printer",
                  subtitle: "Bluetooth thermal receipt",
                  icon: Icons.print,
                  onTap: () => context.push(AppRouter.printerSettings),
                ),

                // ACTION 5: VENUE WALLET & CASHOUTS
                _buildActionCard(
                  title: "Venue Wallet",
                  subtitle: "Virtual account & cashouts",
                  icon: Icons.account_balance_wallet,
                  onTap: () => context.go(AppRouter.wallet),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ─── RECENT CASH PASS TRANSACTIONS ───
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Recent Sales Today",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      InkWell(
                        onTap: () => _showSalesBreakdownSheet(context),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Analytics",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_recentSales.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No sales yet — sell your first pass above.', style: TextStyle(fontSize: 12, color: AppColors.textLight), textAlign: TextAlign.center),
                    )
                  else
                    ..._recentSales.asMap().entries.expand((e) => [
                          _buildSaleRow(e.value['code'], e.value['plan'], e.value['amount'], e.value['time']),
                          if (e.key != _recentSales.length - 1) const Divider(height: 20, color: Color(0x0F000000)),
                        ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleRow(String code, String plan, String amount, String time) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              code,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                color: AppColors.primary,
              ),
            ),
            Text(
              plan,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              amount,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.accentGreen,
              ),
            ),
            Text(
              time,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showSalesBreakdownSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SalesBreakdownSheet(
        venueId: _venueId,
        initialRecentSales: _recentSales,
        todaySales: _todaySales,
      ),
    );
  }
}

class _PlanStat {
  int count;
  int revenue;
  _PlanStat({required this.count, required this.revenue});
}

enum _SalesPeriod { today, week, month }

class _SalesBreakdownSheet extends StatefulWidget {
  final String? venueId;
  final List<Map<String, dynamic>> initialRecentSales;
  final int todaySales;

  const _SalesBreakdownSheet({
    this.venueId,
    required this.initialRecentSales,
    required this.todaySales,
  });

  @override
  State<_SalesBreakdownSheet> createState() => _SalesBreakdownSheetState();
}

class _SalesBreakdownSheetState extends State<_SalesBreakdownSheet> {
  _SalesPeriod _period = _SalesPeriod.today;
  bool _loading = false;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final vid = widget.venueId;
    if (vid == null) return;
    setState(() => _loading = true);
    try {
      final res = await SupabaseService.instance.client
          .from('Order')
          .select('id, customerRef, amountMinor, status, createdAt, Plan(name)')
          .eq('venueId', vid)
          .order('createdAt', ascending: false)
          .limit(200);
      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(res);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_orders.isEmpty && widget.initialRecentSales.isNotEmpty && _period == _SalesPeriod.today) {
      return widget.initialRecentSales;
    }
    final now = DateTime.now();
    return _orders.where((o) {
      final rawDate = o['createdAt'];
      if (rawDate == null) return false;
      final dt = DateTime.tryParse(rawDate.toString())?.toLocal();
      if (dt == null) return false;
      switch (_period) {
        case _SalesPeriod.today:
          return dt.year == now.year && dt.month == now.month && dt.day == now.day;
        case _SalesPeriod.week:
          return dt.isAfter(now.subtract(const Duration(days: 7)));
        case _SalesPeriod.month:
          return dt.isAfter(now.subtract(const Duration(days: 30)));
      }
    }).toList();
  }

  int get _totalRevenueNgn {
    final list = _filteredOrders;
    int total = 0;
    for (final o in list) {
      if (o.containsKey('amountMinor')) {
        total += ((o['amountMinor'] as num?)?.toInt() ?? 0) ~/ 100;
      } else if (o.containsKey('amount')) {
        final amtStr = o['amount'].toString().replaceAll(RegExp(r'[^\d]'), '');
        total += int.tryParse(amtStr) ?? 0;
      }
    }
    if (total == 0 && _period == _SalesPeriod.today && widget.todaySales > 0) {
      return widget.todaySales;
    }
    return total;
  }

  int get _passesCount => _filteredOrders.length;

  int get _avgTicketNgn {
    final count = _passesCount;
    if (count == 0) return 0;
    return _totalRevenueNgn ~/ count;
  }

  Map<String, _PlanStat> get _planBreakdown {
    final Map<String, _PlanStat> stats = {};
    for (final o in _filteredOrders) {
      String planName = 'Standard Pass';
      if (o['Plan'] != null && o['Plan'] is Map && o['Plan']['name'] != null) {
        planName = o['Plan']['name'].toString();
      } else if (o['plan'] != null) {
        planName = o['plan'].toString();
      }
      int amt = 0;
      if (o.containsKey('amountMinor')) {
        amt = ((o['amountMinor'] as num?)?.toInt() ?? 0) ~/ 100;
      } else if (o.containsKey('amount')) {
        final amtStr = o['amount'].toString().replaceAll(RegExp(r'[^\d]'), '');
        amt = int.tryParse(amtStr) ?? 0;
      }
      if (!stats.containsKey(planName)) {
        stats[planName] = _PlanStat(count: 0, revenue: 0);
      }
      stats[planName]!.count += 1;
      stats[planName]!.revenue += amt;
    }
    return stats;
  }

  String _formatNgn(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _formatDate(dynamic iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final planMap = _planBreakdown;
    final totalRev = _totalRevenueNgn;
    final passesSold = _passesCount;
    final filtered = _filteredOrders;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Sales Analytics",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Revenue and voucher performance breakdown",
                            style: TextStyle(fontSize: 12, color: AppColors.textLight),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.primary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    _buildPeriodTab(_SalesPeriod.today, "Today"),
                    const SizedBox(width: 8),
                    _buildPeriodTab(_SalesPeriod.week, "Last 7 Days"),
                    const SizedBox(width: 8),
                    _buildPeriodTab(_SalesPeriod.month, "This Month"),
                  ],
                ),
              ),
              const Divider(height: 16),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricTile(
                                  label: "TOTAL REVENUE",
                                  value: "₦${_formatNgn(totalRev)}",
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildMetricTile(
                                  label: "PASSES SOLD",
                                  value: "$passesSold",
                                  color: AppColors.accentGreen,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildMetricTile(
                                  label: "AVG TICKET",
                                  value: "₦${_formatNgn(_avgTicketNgn)}",
                                  color: AppColors.textLight,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            "PLAN DISTRIBUTION",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textLight,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (planMap.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.containerBg,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Text(
                                  "No sales recorded for this period.",
                                  style: TextStyle(fontSize: 12, color: AppColors.textLight),
                                ),
                              ),
                            )
                          else
                            ...planMap.entries.map((entry) {
                              final pName = entry.key;
                              final stat = entry.value;
                              final pct = totalRev > 0 ? (stat.revenue / totalRev) : 0.0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.cardBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          pName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        Text(
                                          "₦${_formatNgn(stat.revenue)}",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "${stat.count} passes sold",
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textLight,
                                          ),
                                        ),
                                        Text(
                                          "${(pct * 100).toStringAsFixed(0)}% of sales",
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.accentGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: pct.clamp(0.0, 1.0),
                                        minHeight: 6,
                                        backgroundColor: AppColors.cardBorder,
                                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          const SizedBox(height: 22),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "SALES TRANSACTIONS",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textLight,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              Text(
                                "${filtered.length} total",
                                style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (filtered.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.containerBg,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Text(
                                  "No individual transactions found.",
                                  style: TextStyle(fontSize: 12, color: AppColors.textLight),
                                ),
                              ),
                            )
                          else
                            ...filtered.asMap().entries.map((e) {
                              final o = e.value;
                              final code = o['customerRef'] ?? o['code'] ?? (o['id']?.toString().substring(0, 8).toUpperCase() ?? 'PASS');
                              final plan = o['Plan']?['name'] ?? o['plan'] ?? 'Pass';
                              final amt = o.containsKey('amountMinor')
                                  ? '₦${_formatNgn(((o['amountMinor'] as num?)?.toInt() ?? 0) ~/ 100)}'
                                  : (o['amount']?.toString() ?? '₦0');
                              final time = o.containsKey('createdAt')
                                  ? _formatDate(o['createdAt'])
                                  : (o['time']?.toString() ?? '—');
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.containerBg,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          code.toString(),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'monospace',
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        Text(
                                          plan.toString(),
                                          style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          amt,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.accentGreen,
                                          ),
                                        ),
                                        Text(
                                          time,
                                          style: const TextStyle(fontSize: 10, color: AppColors.textLight),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          const SizedBox(height: 16),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodTab(_SalesPeriod period, String label) {
    final active = _period == period;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _period = period),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.containerBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.white : AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppColors.textLight,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
