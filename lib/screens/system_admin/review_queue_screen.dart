import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/system_admin_service.dart';
import '../../core/theme/app_theme.dart';

/// Manual review triage: refund-required orders, stuck provisioning,
/// failed payments, and reversed/refunded payments with verify action.
class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  bool _loading = true;
  Map<String, dynamic> _queue = {};
  String _filter = 'ALL';
  String? _verifyingId;
  String? _verifyResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _verifyResult = null;
    });
    final data = await SystemAdminService.instance.fetchReviewQueue();
    if (mounted) {
      setState(() {
        _queue = data;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _items(String key) {
    final list = _queue[key];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> get _filtered {
    const keys = ['refundRequired', 'stuckProvisioning', 'failedPayments', 'reversedPayments'];
    final all = <Map<String, dynamic>>[];
    for (final k in keys) {
      if (_filter == 'ALL' || _filter == k) {
        for (final item in _items(k)) {
          all.add({'_kind': k, ...item});
        }
      }
    }
    return all;
  }

  String _referenceOf(Map<String, dynamic> item) {
    final payment = item['payment'];
    if (payment is Map) {
      return (payment['providerReference'] ?? item['providerReference'] ?? '').toString();
    }
    return (item['providerReference'] ?? '').toString();
  }

  String _venueOf(Map<String, dynamic> item) {
    final venue = item['venue'] ?? item['order']?['venue'];
    if (venue is Map) return (venue['name'] ?? venue['id'] ?? '').toString();
    return (item['venueId'] ?? item['order']?['venueId'] ?? '').toString();
  }

  String _amountOf(Map<String, dynamic> item) {
    final minor = (item['amountMinor'] as num?)?.toInt() ??
        ((item['order']?['amountMinor'] as num?)?.toInt() ?? 0);
    return '₦${(minor ~/ 100).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'refundRequired':
        return 'REFUND REQUIRED';
      case 'stuckProvisioning':
        return 'STUCK PROVISIONING';
      case 'failedPayments':
        return 'FAILED PAYMENT';
      case 'reversedPayments':
        return 'REVERSED';
      default:
        return kind.toUpperCase();
    }
  }

  Future<void> _verify(Map<String, dynamic> item) async {
    final ref = _referenceOf(item);
    if (ref.isEmpty) {
      setState(() => _verifyResult = 'No payment reference on this item to verify.');
      return;
    }
    setState(() {
      _verifyingId = item['id']?.toString();
      _verifyResult = null;
    });
    final res = await SystemAdminService.instance.verifyPayment(ref);
    if (!mounted) return;
    setState(() {
      _verifyingId = null;
      final verified = res['verified'] == true;
      _verifyResult = verified
          ? 'Verified live on Paystack: ${res['paystack']?['status'] ?? 'success'} (${res['paystack']?['channel'] ?? ''}) — local: ${res['local']?['status'] ?? 'n/a'}.'
          : 'Verification failed: ${res['error'] ?? 'not successful on Paystack'}.';
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final counts = _queue['counts'] as Map? ?? {};
    final total = (counts['total'] as num?)?.toInt() ?? 0;
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text('Review Queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, color: AppColors.primary), tooltip: 'Refresh'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    total == 0 ? 'All clear — nothing needs review' : '$total case${total == 1 ? '' : 's'} need review',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          if (_verifyResult != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Text(_verifyResult!, style: const TextStyle(fontSize: 11, color: AppColors.primary)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: ['ALL', 'refundRequired', 'stuckProvisioning', 'failedPayments', 'reversedPayments'].map((filter) {
                final isSelected = _filter == filter;
                final count = filter == 'ALL' ? total : ((counts[filter] as num?)?.toInt() ?? 0);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$filter ($count)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isSelected ? Colors.white : AppColors.primary)),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.containerBg,
                    onSelected: (sel) {
                      if (sel) setState(() => _filter = filter);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('Nothing here.', style: TextStyle(color: AppColors.textLight)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = _filtered[index];
                          final kind = item['_kind']?.toString() ?? '';
                          final ref = _referenceOf(item);
                          final busy = _verifyingId != null && _verifyingId == item['id']?.toString();
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.containerBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentRed.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _kindLabel(kind),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.accentRed),
                                      ),
                                    ),
                                    Text(
                                      _amountOf(item),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Venue: ${_venueOf(item)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                if (ref.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Ref: $ref',
                                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textLight),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy_rounded, size: 14, color: AppColors.textLight),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: ref));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Reference copied'), duration: Duration(seconds: 1)),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (ref.isNotEmpty)
                                      TextButton.icon(
                                        onPressed: busy ? null : () => _verify(item),
                                        icon: busy
                                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.verified_rounded, size: 15, color: AppColors.accentGreen),
                                        label: const Text('Verify live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentGreen)),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
