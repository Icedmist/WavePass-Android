import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/system_admin_service.dart';
import '../../core/theme/app_theme.dart';

class ActivationRequestsScreen extends StatefulWidget {
  const ActivationRequestsScreen({super.key});

  @override
  State<ActivationRequestsScreen> createState() => _ActivationRequestsScreenState();
}

class _ActivationRequestsScreenState extends State<ActivationRequestsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];
  String _filter = 'PENDING'; // ALL, PENDING, GRANTED, REJECTED

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await SystemAdminService.instance.fetchActivationRequests();
    if (mounted) {
      setState(() {
        _requests = list;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'ALL') return _requests;
    return _requests.where((r) => (r['status'] ?? '').toString().toUpperCase() == _filter).toList();
  }

  int get _pendingCount =>
      _requests.where((r) => (r['status'] ?? '').toString().toUpperCase() == 'PENDING').length;

  Future<void> _grantCodeDialog(Map<String, dynamic> item) async {
    String kind = 'LICENSE';
    final daysCtrl = TextEditingController(text: "30");
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Grant Activation Code", style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "To: ${item['name'] ?? item['email']} (${item['email']})${item['venueName'] != null ? '\nVenue: ${item['venueName']}' : ''}",
                  style: const TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text("CODE TYPE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'LICENSE', child: Text("LICENSE — 1 venue")),
                    DropdownMenuItem(value: 'MASTER', child: Text("MASTER — multi-use")),
                    DropdownMenuItem(value: 'TRIAL', child: Text("TRIAL — short")),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setDialogState(() {
                      kind = v;
                      if (v == 'TRIAL') daysCtrl.text = "7";
                      if (v == 'LICENSE') daysCtrl.text = "30";
                      if (v == 'MASTER') daysCtrl.text = "0";
                    });
                  },
                ),
                const SizedBox(height: 12),
                const Text("DAYS VALID (0 = LIFETIME)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                TextField(controller: daysCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 12),
                const Text("NOTE (OPTIONAL)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                TextField(controller: noteCtrl, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Grant Code", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final res = await SystemAdminService.instance.approveActivationRequest(
      item['id'].toString(),
      mode: 'code',
      kind: kind,
      durationDays: int.tryParse(daysCtrl.text.trim()),
      reviewNote: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );
    await _load();
    if (!mounted) return;
    if (res['ok'] == true && res['code'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Code granted: ${res['code']} — share it with ${item['email']}"),
          backgroundColor: AppColors.accentGreen,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'COPY',
            textColor: Colors.white,
            onPressed: () => Clipboard.setData(ClipboardData(text: res['code'].toString())),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Grant failed: ${res['error'] ?? 'unknown error'}"), backgroundColor: AppColors.accentRed),
      );
    }
  }

  Future<void> _grantDirectDialog(Map<String, dynamic> item) async {
    final daysCtrl = TextEditingController(text: "30");
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Grant Direct Access", style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${item['email']} gets immediate access for a given time — no code needed.",
              style: const TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text("DAYS OF ACCESS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textLight)),
            const SizedBox(height: 6),
            TextField(controller: daysCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Grant Access", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await SystemAdminService.instance.approveActivationRequest(
      item['id'].toString(),
      mode: 'direct',
      durationDays: int.tryParse(daysCtrl.text.trim()) ?? 30,
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['ok'] == true
            ? (res['message']?.toString() ?? 'Direct access granted.')
            : "Grant failed: ${res['error'] ?? 'unknown error'}"),
        backgroundColor: res['ok'] == true ? AppColors.accentGreen : AppColors.accentRed,
      ),
    );
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final res = await SystemAdminService.instance.rejectActivationRequest(item['id'].toString());
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['ok'] == true ? "Request rejected." : "Reject failed: ${res['error'] ?? 'unknown error'}"),
        backgroundColor: res['ok'] == true ? AppColors.primary : AppColors.accentRed,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return const Color(0xFFD97706);
      case 'GRANTED':
        return AppColors.accentGreen;
      case 'REJECTED':
        return AppColors.accentRed;
      default:
        return AppColors.primary;
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
        title: const Text("Code Requests", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: AppColors.primary), tooltip: "Refresh"),
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
                    "$_pendingCount pending • ${_requests.length} total",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: ['PENDING', 'GRANTED', 'REJECTED', 'ALL'].map((filter) {
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(child: Text("No $_filter requests.", style: const TextStyle(color: AppColors.textLight)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = _filtered[index];
                          final status = (item['status'] ?? '').toString().toUpperCase();
                          final isPending = status == 'PENDING';
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
                                    Expanded(
                                      child: Text(
                                        item['name']?.toString().isNotEmpty == true
                                            ? item['name'].toString()
                                            : item['email']?.toString() ?? 'Unknown',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _statusColor(status))),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(item['email']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                                if (item['phone'] != null) Text("Phone: ${item['phone']}", style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                                if (item['venueName'] != null)
                                  Text("Venue: ${item['venueName']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                if (item['message'] != null && (item['message'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text('"${item['message']}"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textLight)),
                                ],
                                if (isPending) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _grantCodeDialog(item),
                                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                          icon: const Icon(Icons.vpn_key_rounded, size: 15, color: Colors.white),
                                          label: const Text("Grant Code", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _grantDirectDialog(item),
                                          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.primary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                          icon: const Icon(Icons.bolt_rounded, size: 15, color: AppColors.primary),
                                          label: const Text("Direct Access", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        onPressed: () => _reject(item),
                                        icon: const Icon(Icons.close_rounded, color: AppColors.accentRed),
                                        tooltip: "Reject",
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
