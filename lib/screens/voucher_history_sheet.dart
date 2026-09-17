import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/router_discovery_service.dart';
import '../core/services/voucher_history_service.dart';
import '../core/theme/app_theme.dart';

class VoucherHistorySheet extends StatefulWidget {
  const VoucherHistorySheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoucherHistorySheet(),
    );
  }

  @override
  State<VoucherHistorySheet> createState() => _VoucherHistorySheetState();
}

class _VoucherHistorySheetState extends State<VoucherHistorySheet> {
  List<VoucherRecord> _vouchers = [];
  bool _loading = true;
  String _filter = 'unused'; // 'unused' (inactive available), 'in_use', 'all', 'expired'
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final history = await VoucherHistoryService.instance.fetchFullVoucherActivity();
    if (mounted) {
      setState(() {
        _vouchers = history;
        _loading = false;
      });
    }
  }

  Future<void> _checkLifecycle() async {
    setState(() => _isRefreshing = true);
    await VoucherHistoryService.instance.checkVoucherLifecycle(mounted ? context : null);
    final history = await VoucherHistoryService.instance.fetchFullVoucherActivity();
    if (mounted) {
      setState(() {
        _vouchers = history;
        _isRefreshing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Hardware & cloud activity synced! All active sessions up to date."),
          backgroundColor: AppColors.accentGreen,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isPurging = false;

  Future<void> _handlePurgeExpired() async {
    final expiredCount = _vouchers.where((v) => v.status == 'expired').length;
    if (expiredCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No expired vouchers to remove."),
          backgroundColor: AppColors.primary,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isPurging = true);
    final count = await VoucherHistoryService.instance.purgeExpiredVouchers();
    await _loadData();
    if (mounted) {
      setState(() {
        _isPurging = false;
        if (_filter == 'expired') _filter = 'unused';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Removed $count expired vouchers from device and router hardware!"),
          backgroundColor: AppColors.accentGreen,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  List<VoucherRecord> get _filteredVouchers {
    if (_filter == 'all') {
      return _vouchers;
    }
    return _vouchers.where((v) => v.status == _filter).toList();
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in_use':
        return AppColors.accentGreen;
      case 'expired':
        return AppColors.textLight;
      default:
        return AppColors.primary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_use':
        return 'IN USE (ACTIVE)';
      case 'expired':
        return 'EXPIRED';
      default:
        return 'INACTIVE (AVAILABLE)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _vouchers.where((v) => v.status == 'in_use').length;
    final unusedCount = _vouchers.where((v) => v.status == 'unused').length;
    final expiredCount = _vouchers.where((v) => v.status == 'expired').length;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag Handle
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                "Voucher & Pass History",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primary,
                                ),
                              ),
                              if (activeCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentGreen.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "$activeCount ACTIVE",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.accentGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "$unusedCount inactive (available) • $activeCount in use • $expiredCount expired",
                            style: const TextStyle(fontSize: 12, color: AppColors.textLight),
                          ),
                          const SizedBox(height: 6),
                          _RouterTargetRow(onReset: _loadData),
                        ],
                      ),
                    ),
                    if (expiredCount > 0)
                      IconButton(
                        onPressed: _isPurging ? null : _handlePurgeExpired,
                        icon: _isPurging
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.delete_sweep_rounded, color: AppColors.accentRed),
                        tooltip: "Remove Expired Vouchers",
                      ),
                    IconButton(
                      onPressed: _isRefreshing ? null : _checkLifecycle,
                      icon: _isRefreshing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync_rounded, color: AppColors.primary),
                      tooltip: "Sync with Router Hardware",
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildFilterChip('all', 'All Activity (${_vouchers.length})'),
                    const SizedBox(width: 8),
                    _buildFilterChip('unused', 'Available ($unusedCount)'),
                    const SizedBox(width: 8),
                    _buildFilterChip('in_use', 'In Use ($activeCount)'),
                    const SizedBox(width: 8),
                    _buildFilterChip('expired', 'Expired ($expiredCount)'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.cardBorder),

              // List of Vouchers
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredVouchers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.confirmation_number_outlined, size: 48, color: AppColors.cardBorder),
                                const SizedBox(height: 12),
                                Text(
                                  _filter == 'all' ? "No voucher activity found" : "No $_filter passes found",
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textLight),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(20),
                            itemCount: _filteredVouchers.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = _filteredVouchers[index];
                              final statusColor = _statusColor(item.status);
                              final isDual = item.isDualCredential;

                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.containerBg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: item.status == 'in_use'
                                        ? AppColors.accentGreen.withValues(alpha: 0.3)
                                        : AppColors.cardBorder,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: isDual
                                              ? Row(
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            const Text(
                                                              "USER: ",
                                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight),
                                                            ),
                                                            Text(
                                                              item.code,
                                                              style: const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight: FontWeight.w900,
                                                                fontFamily: 'monospace',
                                                                color: AppColors.primary,
                                                              ),
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(Icons.copy_rounded, size: 14, color: AppColors.textLight),
                                                              visualDensity: VisualDensity.compact,
                                                              padding: EdgeInsets.zero,
                                                              onPressed: () {
                                                                Clipboard.setData(ClipboardData(text: item.code));
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(content: Text("Copied username ${item.code}"), duration: const Duration(seconds: 1)),
                                                                );
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                        Row(
                                                          children: [
                                                            const Text(
                                                              "PIN:    ",
                                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight),
                                                            ),
                                                            Text(
                                                              item.effectivePassword,
                                                              style: const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight: FontWeight.w900,
                                                                fontFamily: 'monospace',
                                                                color: AppColors.primary,
                                                              ),
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(Icons.copy_rounded, size: 14, color: AppColors.textLight),
                                                              visualDensity: VisualDensity.compact,
                                                              padding: EdgeInsets.zero,
                                                              onPressed: () {
                                                                Clipboard.setData(ClipboardData(text: item.effectivePassword));
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(content: Text("Copied PIN ${item.effectivePassword}"), duration: const Duration(seconds: 1)),
                                                                );
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                )
                                              : Row(
                                                  children: [
                                                    Text(
                                                      item.code,
                                                      style: const TextStyle(
                                                        fontSize: 17,
                                                        fontWeight: FontWeight.w900,
                                                        fontFamily: 'monospace',
                                                        letterSpacing: 1.0,
                                                        color: AppColors.primary,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    IconButton(
                                                      icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textLight),
                                                      visualDensity: VisualDensity.compact,
                                                      padding: EdgeInsets.zero,
                                                      onPressed: () {
                                                        Clipboard.setData(ClipboardData(text: item.code));
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(
                                                            content: Text("Copied ${item.code} to clipboard"),
                                                            duration: const Duration(seconds: 1),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _statusLabel(item.status),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5,
                                              color: statusColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        if (!item.provisioned)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            margin: const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: AppColors.accentRed.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'UNSYNCED',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.5,
                                                color: AppColors.accentRed,
                                              ),
                                            ),
                                          ),
                                        InkWell(
                                          onTap: () async {
                                            final ok = await VoucherHistoryService.instance.markSold(item.code, !item.sold);
                                            if (ok) {
                                              setState(() => item.sold = !item.sold);
                                            }
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: (item.sold ? AppColors.accentGreen : AppColors.textLight).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              item.sold ? 'SOLD' : 'UNSOLD',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.5,
                                                color: item.sold ? AppColors.accentGreen : AppColors.textLight,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "${item.planTitle} • ${item.price}",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            if (item.source != null && item.source != 'local') ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                margin: const EdgeInsets.only(right: 6),
                                                decoration: BoxDecoration(
                                                  color: AppColors.cardBorder,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  item.source!.toUpperCase(),
                                                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.textLight),
                                                ),
                                              ),
                                            ],
                                            Text(
                                              _formatTime(item.createdAt),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textLight,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (item.status == 'in_use') ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentGreen.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.wifi_tethering_rounded, size: 14, color: AppColors.accentGreen),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    "Active: MAC ${item.mac ?? 'Unknown'} • IP ${item.ip ?? '—'}",
                                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accentGreen),
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () async {
                                                    await VoucherHistoryService.instance.expireVoucher(item.code);
                                                    _loadData();
                                                  },
                                                  child: const Text("Disconnect", style: TextStyle(fontSize: 10, color: AppColors.accentRed)),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                const SizedBox(width: 20),
                                                Text(
                                                  "Uptime: ${item.uptimeFormatted}  •  Data: ${item.dataTransferredFormatted}",
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else if (item.status == 'expired') ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.history_rounded, size: 12, color: AppColors.textLight),
                                          const SizedBox(width: 4),
                                          Text(
                                            "Used: ${item.uptimeFormatted}  •  Transferred: ${item.dataTransferredFormatted}",
                                            style: const TextStyle(fontSize: 10, color: AppColors.textLight),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _filter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          color: isSelected ? AppColors.white : AppColors.primary,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.containerBg,
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (_) => setState(() => _filter = key),
    );
  }

}

/// Shows which router address voucher ops target, with validation state and
/// one-tap reset. A stale address (e.g. an ISP gateway) silently breaks all
/// router monitoring, retrieval, and provisioning.
class _RouterTargetRow extends StatefulWidget {
  const _RouterTargetRow({required this.onReset});
  final VoidCallback onReset;

  @override
  State<_RouterTargetRow> createState() => _RouterTargetRowState();
}

class _RouterTargetRowState extends State<_RouterTargetRow> {
  String _target = '192.168.88.1';
  bool? _valid;
  String? _identity;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final t = await RouterDiscoveryService.effectiveRouterTarget();
    if (mounted) setState(() => _target = t);
  }

  Future<void> _validate() async {
    setState(() {
      _checking = true;
      _valid = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final res = await RouterDiscoveryService.validateRouterTarget(
        ip: _target,
        username: prefs.getString(RouterDiscoveryService.keyRouterUsername) ?? 'admin',
        password: prefs.getString(RouterDiscoveryService.keyRouterPassword) ?? '',
      );
      if (mounted) {
        setState(() {
          _valid = res['ok'] == true;
          _identity = res['identity']?.toString();
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _reset() async {
    await RouterDiscoveryService.resetRouterTarget();
    await _refresh();
    setState(() {
      _valid = null;
      _identity = null;
    });
    widget.onReset();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Router target reset to 192.168.88.1'), backgroundColor: AppColors.accentGreen, duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _valid == null
        ? AppColors.textLight
        : _valid!
            ? AppColors.accentGreen
            : AppColors.accentRed;
    return InkWell(
      onTap: _checking ? null : _validate,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _valid == null ? Icons.router_outlined : _valid! ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _valid == true && _identity != null ? 'Router $_target ($_identity)' : 'Router: $_target',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _checking ? 'checking…' : 'tap to verify',
            style: const TextStyle(fontSize: 10, color: AppColors.textLight),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, size: 15, color: AppColors.textLight),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Reset to 192.168.88.1',
            onPressed: _reset,
          ),
        ],
      ),
    );
  }
}

