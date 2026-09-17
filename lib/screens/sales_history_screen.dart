import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/services/supabase_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/theme/app_theme.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _sales = [];
  int _totalMinor = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final vid = VenueStateService.instance.currentVenueId;
      if (vid == null || vid.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final rows = await SupabaseService.instance.client
          .from('Order')
          .select('id, customerRef, amountMinor, createdAt, Plan(name)')
          .eq('venueId', vid)
          .order('createdAt', ascending: false)
          .limit(100);
      final list = List<Map<String, dynamic>>.from(rows);
      int total = 0;
      for (final o in list) {
        total += ((o['amountMinor'] as num?)?.toInt() ?? 0);
      }
      if (mounted) {
        setState(() {
          _sales = list;
          _totalMinor = total;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text('Sales History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: AppColors.primary), tooltip: 'Refresh'),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.containerBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_sales.length} sales', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                Text(
                  '₦${(_totalMinor ~/ 100).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.accentGreen),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                    ? const Center(child: Text('No sales yet.', style: TextStyle(color: AppColors.textLight)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _sales.length,
                        separatorBuilder: (_, _) => const Divider(height: 20, color: Color(0x0F000000)),
                        itemBuilder: (c, i) {
                          final o = _sales[i];
                          final code = (o['customerRef'] ?? o['id'].toString().substring(0, 8).toUpperCase()).toString();
                          final plan = (o['Plan']?['name'] ?? 'Pass').toString();
                          final amount = '₦${(((o['amountMinor'] as num?)?.toInt() ?? 0) ~/ 100)}';
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(code, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'monospace', color: AppColors.primary)),
                                  Text('$plan • ${_timeAgo(o['createdAt']?.toString())}', style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                                ],
                              ),
                              Text(amount, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.accentGreen)),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
