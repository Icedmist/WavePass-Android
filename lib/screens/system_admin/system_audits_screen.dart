import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/system_admin_service.dart';
import '../../core/theme/app_theme.dart';

class SystemAuditsScreen extends StatefulWidget {
  const SystemAuditsScreen({super.key});

  @override
  State<SystemAuditsScreen> createState() => _SystemAuditsScreenState();
}

class _SystemAuditsScreenState extends State<SystemAuditsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];
  String _selectedCategory = 'ALL';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAudits();
  }

  Future<void> _loadAudits() async {
    setState(() => _loading = true);
    final category = _selectedCategory == 'ALL' ? null : _selectedCategory;
    final logs = await SystemAdminService.instance.fetchAuditLogs(category: category);
    if (mounted) {
      setState(() {
        _logs = logs;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    if (_searchQuery.trim().isEmpty) return _logs;
    final q = _searchQuery.toLowerCase().trim();
    return _logs.where((l) {
      final action = (l['action'] ?? '').toString().toLowerCase();
      final actor = (l['actor'] ?? '').toString().toLowerCase();
      final cat = (l['category'] ?? '').toString().toLowerCase();
      return action.contains(q) || actor.contains(q) || cat.contains(q);
    }).toList();
  }

  void _copyAllLogs() {
    final text = const JsonEncoder.withIndent('  ').convert(_filteredLogs);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Audit trail copied to clipboard!"), backgroundColor: AppColors.accentGreen),
    );
  }

  Color _statusColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'SUCCESS':
        return AppColors.accentGreen;
      case 'FAILURE':
      case 'ERROR':
        return AppColors.accentRed;
      default:
        return AppColors.accentOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['ALL', 'ACTIVATION', 'ROUTER', 'AUTH', 'SECURITY', 'SYSTEM'];

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
          "System Audits & Trails",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
        ),
        actions: [
          IconButton(
            onPressed: _copyAllLogs,
            icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
            tooltip: "Copy Logs JSON",
          ),
          IconButton(
            onPressed: _loadAudits,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: "Refresh Logs",
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: "Search audit logs by action or actor...",
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textLight),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textLight, size: 20),
                filled: true,
                fillColor: AppColors.containerBg,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isSelected ? Colors.white : AppColors.primary)),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.containerBg,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _selectedCategory = cat);
                        _loadAudits();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.cardBorder),

          // Log Entries List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredLogs.isEmpty
                    ? const Center(child: Text("No audit records found.", style: TextStyle(color: AppColors.textLight)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _filteredLogs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _filteredLogs[index];
                          final status = item['status']?.toString() ?? 'SUCCESS';
                          final statusColor = _statusColor(status);

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.containerBg,
                              borderRadius: BorderRadius.circular(14),
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
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            item['category']?.toString().toUpperCase() ?? 'GENERAL',
                                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primary),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          item['action']?.toString() ?? 'ACTION',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.primary),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      status,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Actor: ${item['actor'] ?? 'system'}",
                                  style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                                ),
                                if (item['details'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    "Details: ${item['details']}",
                                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.primary),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  item['timestamp']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 10, color: AppColors.textLight),
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
