import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/system_admin_service.dart';
import '../../core/theme/app_theme.dart';

class ActivationCodesScreen extends StatefulWidget {
  const ActivationCodesScreen({super.key});

  @override
  State<ActivationCodesScreen> createState() => _ActivationCodesScreenState();
}

class _ActivationCodesScreenState extends State<ActivationCodesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _codes = [];
  String _filter = 'ALL'; // ALL, AUTHORIZED, USED, REVOKED
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    setState(() => _loading = true);
    final list = await SystemAdminService.instance.fetchActivationCodes();
    if (mounted) {
      setState(() {
        _codes = list;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredCodes {
    if (_filter == 'ALL') return _codes;
    return _codes.where((c) => (c['status'] ?? '').toString().toUpperCase() == _filter).toList();
  }

  Future<void> _showGenerateDialog() async {
    int count = 1;
    String kind = 'LICENSE';
    final noteCtrl = TextEditingController(text: "Venue License");
    final venueCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: "30");

    String durationHint() {
      switch (kind) {
        case 'MASTER':
          return "Days valid (0 = lifetime)";
        case 'TRIAL':
          return "Days valid (default 7)";
        default:
          return "Days valid (default 30, monthly)";
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            "Generate Activation Codes",
            style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Each activation code is strictly limited to 1 venue. Codes carry their own expiry date — expired venues pause all activity until a fresh code is redeemed.",
                  style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                ),
                const SizedBox(height: 16),
                const Text("NUMBER OF CODES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  initialValue: count,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [1, 5, 10, 25, 50].map((n) => DropdownMenuItem(value: n, child: Text("$n Codes"))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => count = val);
                  },
                ),
                const SizedBox(height: 12),
                const Text("NOTE / CLIENT ASSIGNEE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "e.g. September rotation", isDense: true),
                ),
                const SizedBox(height: 12),
                const Text("VENUE IDS (OPTIONAL, COMMA-SEPARATED)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                TextField(
                  controller: venueCtrl,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "One code per venue; leave empty for unassigned", isDense: true),
                ),
                const SizedBox(height: 12),
                const Text("CODE TYPE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'LICENSE', child: Text("LICENSE — 1 venue, monthly")),
                    DropdownMenuItem(value: 'MASTER', child: Text("MASTER — multi-use, any venue")),
                    DropdownMenuItem(value: 'TRIAL', child: Text("TRIAL — short-lived, 1 use")),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        kind = val;
                        if (val == 'TRIAL') durationCtrl.text = "7";
                        if (val == 'LICENSE') durationCtrl.text = "30";
                        if (val == 'MASTER') durationCtrl.text = "0";
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                Text(durationHint(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "e.g. 30", isDense: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Generate Codes", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      setState(() => _isGenerating = true);
      final venueIds = venueCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final durationDays = int.tryParse(durationCtrl.text.trim());
      final generated = await SystemAdminService.instance.generateActivationCodes(
        count: count,
        note: noteCtrl.text.trim(),
        quota: kind == 'MASTER' ? 5 : 1,
        kind: kind,
        durationDays: durationDays,
        venueIds: venueIds.isEmpty ? null : venueIds,
      );
      await _loadCodes();
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Generated ${generated.length} activation codes successfully!"),
            backgroundColor: AppColors.accentGreen,
          ),
        );
      }
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> item) async {
    final code = item['code']?.toString() ?? '';
    final currentStatus = (item['status'] ?? '').toString().toUpperCase();
    if (currentStatus == 'USED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot modify a code that has already been redeemed."), backgroundColor: AppColors.primary),
      );
      return;
    }

    final nextStatus = currentStatus == 'AUTHORIZED' ? 'REVOKED' : 'AUTHORIZED';
    final ok = await SystemAdminService.instance.authorizeActivationCode(code, nextStatus);
    if (ok) {
      setState(() {
        item['status'] = nextStatus;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Code $code marked $nextStatus!"), backgroundColor: nextStatus == 'AUTHORIZED' ? AppColors.accentGreen : AppColors.accentOrange),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'AUTHORIZED':
        return AppColors.accentGreen;
      case 'USED':
        return AppColors.textLight;
      case 'REVOKED':
        return AppColors.accentRed;
      case 'EXPIRED':
        return const Color(0xFFD97706);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authCount = _codes.where((c) => (c['status'] ?? '').toString().toUpperCase() == 'AUTHORIZED').length;
    final usedCount = _codes.where((c) => (c['status'] ?? '').toString().toUpperCase() == 'USED').length;
    final expiredCount = _codes.where((c) => (c['status'] ?? '').toString().toUpperCase() == 'EXPIRED').length;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          "Activation Codes Engine",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
        ),
        actions: [
          IconButton(
            onPressed: _loadCodes,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: "Refresh Codes",
          ),
        ],
      ),
      body: Column(
        children: [
          // Action Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${_codes.length} Total Codes • $authCount Authorized • $usedCount Used • $expiredCount Expired",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                      const Text(
                        "1 venue per activation code limit enforced",
                        style: TextStyle(fontSize: 10, color: AppColors.textLight),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _showGenerateDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isGenerating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                  label: const Text("Generate", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: ['ALL', 'AUTHORIZED', 'USED', 'REVOKED', 'EXPIRED'].map((filter) {
                final isSelected = _filter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isSelected ? Colors.white : AppColors.primary)),
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
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.cardBorder),

          // Codes List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCodes.isEmpty
                    ? Center(
                        child: Text("No $_filter activation codes found.", style: const TextStyle(color: AppColors.textLight)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _filteredCodes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = _filteredCodes[index];
                          final code = item['code']?.toString() ?? '';
                          final status = (item['status'] ?? '').toString().toUpperCase();
                          final statusColor = _statusColor(status);
                          final redeemedBy = item['redeemedBy']?.toString();
                          final venueId = item['venueId']?.toString();
                          final notes = item['notes']?.toString();
                          final expiresAt = item['expiresAt']?.toString();
                          final kindLabel = (item['kind']?.toString() ?? 'LICENSE').toUpperCase();

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
                                    Row(
                                      children: [
                                        Text(
                                          code,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'monospace',
                                            letterSpacing: 1.5,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: "Copy Code",
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: code));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text("Code $code copied!"), backgroundColor: AppColors.accentGreen, duration: const Duration(seconds: 1)),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            kindLabel,
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (notes != null && notes.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    "Note: $notes (1 Venue License)",
                                    style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                                  ),
                                ],
                                if (expiresAt != null && expiresAt.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_month_rounded, size: 12, color: Color(0xFFD97706)),
                                      const SizedBox(width: 4),
                                      Text(
                                        "Expires: $expiresAt",
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                                      ),
                                    ],
                                  ),
                                ],
                                if (status == 'USED') ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Redeemed by: ${redeemedBy ?? 'Unknown'}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                        if (venueId != null)
                                          Text("Venue ID: $venueId", style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () => _toggleStatus(item),
                                        child: Text(
                                          status == 'AUTHORIZED' ? "Revoke Authorization" : "Authorize Code",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: status == 'AUTHORIZED' ? AppColors.accentRed : AppColors.accentGreen,
                                          ),
                                        ),
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
  }
}
