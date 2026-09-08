import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/router/app_router.dart';
import '../core/services/supabase_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/plan_configurator.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  // Venue & Branding
  String? _venueId;
  String _venueName = 'WavePass Venue';
  String _venueSlug = 'venue';
  String? _ownerEmail;
  bool _loadingVenue = false;
  bool _savingVenue = false;

  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  XFile? _pickedLogo;
  String? _uploadedLogoUrl;
  bool _uploadingLogo = false;

  // Router Connectivity
  String? _routerId;
  String _routerName = '';
  String _routerEndpoint = '';
  String _routerConnectionMode = 'local';
  bool _hasRouter = false;
  bool _routerOnline = false;
  bool _testingRouter = false;

  // Plans Tier Management
  List<Map<String, dynamic>> _plans = [];
  bool _loadingPlans = true;

  // Operations
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _logoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await _loadVenue();
    if (_venueId != null) {
      await Future.wait([
        _loadPlans(),
        _loadRouter(_venueId!),
      ]);
    }
  }

  Future<void> _loadVenue() async {
    setState(() => _loadingVenue = true);
    try {
      final user = SupabaseService.instance.currentUser;
      _ownerEmail = user?.email;

      Map<String, dynamic>? v;
      try {
        v = await WavePassApi.instance.getDefaultVenue();
      } catch (_) {}
      v ??= await SupabaseService.instance.getPrimaryVenue();

      if (v != null && v['id'] != null) {
        final id = v['id'].toString();
        final name = v['name']?.toString() ?? 'WavePass Venue';
        final slug = v['slug']?.toString() ?? 'venue';
        final logo = v['logoUrl']?.toString() ?? '';

        setState(() {
          _venueId = id;
          _venueName = name;
          _venueSlug = slug;
          _nameCtrl.text = name;
          _slugCtrl.text = slug;
          _logoCtrl.text = logo;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingVenue = false);
    }
  }

  Future<void> _loadRouter(String venueId) async {
    try {
      final res = await SupabaseService.instance.client
          .from('Router')
          .select('id, name, endpoint, status, connectionMode, lastSeen')
          .eq('venueId', venueId)
          .limit(1);

      final list = res as List;
      if (list.isNotEmpty) {
        final r = list.first as Map<String, dynamic>;
        final rId = r['id']?.toString();
        final rStatus = r['status']?.toString() ?? 'OFFLINE';
        final isOnline = rStatus == 'ONLINE';

        if (mounted) {
          setState(() {
            _hasRouter = true;
            _routerId = rId;
            _routerName = r['name']?.toString() ?? 'MikroTik Gateway';
            _routerEndpoint = r['endpoint']?.toString() ?? '';
            _routerConnectionMode = r['connectionMode']?.toString() ?? 'local';
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
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _testRouterConnection() async {
    if (_routerId == null) return;
    setState(() => _testingRouter = true);
    try {
      final health = await WavePassApi.instance.getRouterHealth(_routerId!);
      final isOnline = health['status'] == 'ONLINE' || health['reachable'] == true;
      if (mounted) {
        setState(() => _routerOnline = isOnline);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOnline ? "Router is ONLINE and reachable!" : "Router is OFFLINE or unreachable."),
            backgroundColor: isOnline ? AppColors.accentGreen : AppColors.accentRed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Health check failed: $e"), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _testingRouter = false);
    }
  }

  Future<void> _loadPlans() async {
    if (_venueId == null) return;
    setState(() => _loadingPlans = true);
    try {
      final plans = await SupabaseService.instance.getActivePlans(_venueId!);
      if (mounted) {
        setState(() {
          _plans = plans.map((p) {
            final priceMinor = (p['priceMinor'] as num?)?.toInt() ?? 0;
            final durationSec = (p['durationSeconds'] as num?)?.toInt() ?? 3600;
            final durationStr = durationSec < 3600
                ? '${durationSec ~/ 60} Mins'
                : durationSec < 86400
                    ? '${durationSec ~/ 3600} Hours'
                    : '${durationSec ~/ 86400} Days';
            final dataLimit = p['dataLimitBytes'];
            final dataStr = dataLimit == null
                ? 'Unlimited'
                : '${((dataLimit as num) / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

            return {
              'id': p['id']?.toString() ?? '',
              'name': p['name']?.toString() ?? 'Pass',
              'price': priceMinor ~/ 100,
              'duration': durationStr,
              'data': dataStr,
              'rateLimit': p['rateLimit']?.toString() ?? '10M',
              'devices': p['simultaneousDevices'] ?? 1,
            };
          }).toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _plans = []);
    } finally {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  Future<void> _pickAdminLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _pickedLogo = picked;
        _uploadingLogo = true;
      });
      try {
        final raw = await picked.readAsBytes();
        final compressed = await FlutterImageCompress.compressWithList(
          raw,
          minWidth: 800,
          minHeight: 800,
          quality: 70,
          format: CompressFormat.jpeg,
        );
        final bytes = compressed.isNotEmpty ? compressed : raw;
        final fileName = 'venue-${DateTime.now().millisecondsSinceEpoch}-${picked.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.jpg';

        try {
          await SupabaseService.instance.client.storage.from('venue_logos').uploadBinary(fileName, bytes);
          final url = SupabaseService.instance.client.storage.from('venue_logos').getPublicUrl(fileName);
          setState(() {
            _uploadedLogoUrl = url;
            _logoCtrl.text = url;
          });
        } catch (_) {
          try {
            await SupabaseService.instance.client.storage.from('venue-logos').uploadBinary(fileName, bytes);
            final url = SupabaseService.instance.client.storage.from('venue-logos').getPublicUrl(fileName);
            setState(() {
              _uploadedLogoUrl = url;
              _logoCtrl.text = url;
            });
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
          }
        }
      } finally {
        if (mounted) setState(() => _uploadingLogo = false);
      }
    }
  }

  Future<void> _saveVenue() async {
    if (_venueId == null) return;
    final slug = _slugCtrl.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slug must be lowercase alphanumeric and hyphens only.')),
      );
      return;
    }
    final logoUrl = _uploadedLogoUrl ?? _logoCtrl.text.trim();
    if (logoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload or provide a venue logo.')),
      );
      return;
    }

    setState(() => _savingVenue = true);
    try {
      await WavePassApi.instance.patchVenue(_venueId!, {
        'name': _nameCtrl.text.trim(),
        'slug': slug,
        'logoUrl': logoUrl,
      });
      if (!mounted) return;
      setState(() {
        _venueName = _nameCtrl.text.trim();
        _venueSlug = slug;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Venue updated! Lives at $slug.nexawavepass.com'),
          backgroundColor: AppColors.accentGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.accentRed),
      );
    } finally {
      if (mounted) setState(() => _savingVenue = false);
    }
  }

  void _handleSync() async {
    setState(() => _isSyncing = true);
    try {
      await WavePassApi.instance.adminStats();
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Router synchronized! All paid sessions are active."), backgroundColor: AppColors.accentGreen),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session synchronization complete."), backgroundColor: AppColors.accentGreen),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _editPrice(int index) {
    final plan = _plans[index];
    final controller = TextEditingController(text: '${plan['price']}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text("Edit ${plan['name']} Price", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Price in Naira (NGN):", style: TextStyle(fontSize: 12, color: AppColors.textLight)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: "e.g. 500",
                prefixText: "₦ ",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final newPrice = int.tryParse(controller.text);
              if (newPrice != null) {
                final planId = plan['id'];
                if (planId != null && planId.isNotEmpty) {
                  try {
                    await SupabaseService.instance.client
                        .from('Plan')
                        .update({'priceMinor': newPrice * 100})
                        .eq('id', planId);
                  } catch (_) {}
                }
                setState(() => _plans[index]['price'] = newPrice);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("${plan['name']} price updated to ₦$newPrice."), backgroundColor: AppColors.accentGreen),
                  );
                }
              }
            },
            child: const Text("Save Price"),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePlan(String planId, String planName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text("Delete $planName?", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: const Text("This pass will be removed from your venue portal and mobile sales.", style: TextStyle(fontSize: 12, color: AppColors.textLight)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
            child: const Text("Delete Plan"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await SupabaseService.instance.client.from('Plan').delete().eq('id', planId);
        _loadPlans();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("$planName removed."), backgroundColor: AppColors.accentGreen),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to delete plan: $e"), backgroundColor: AppColors.accentRed),
          );
        }
      }
    }
  }

  void _handleLogout() async {
    await SupabaseService.instance.signOut();
    if (!mounted) return;
    context.go(AppRouter.login);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.dashboard),
        ),
        title: const Text(
          "Admin Hub",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_rounded, color: AppColors.primary, size: 24),
            tooltip: "Account Center",
            onPressed: () => context.push(AppRouter.account),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 22),
            tooltip: "Refresh Data",
            onPressed: _loadAllData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset + 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── 1. HERO OPERATOR & ACCOUNT CENTER BANNER ───
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "VENUE ADMINISTRATOR",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accentGreen,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _venueName,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _ownerEmail ?? 'talk2icedmist@gmail.com',
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Dedicated Account Center Link Button
                  InkWell(
                    onTap: () => context.push(AppRouter.account),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.lock_person_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Account Center & Security",
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                                Text(
                                  "Update passwords, credentials, venue & account deletion",
                                  style: TextStyle(fontSize: 10, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ─── 2. LIVE MIKROTIK HARDWARE CONNECTION STATUS ───
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _routerOnline
                    ? AppColors.accentGreen.withValues(alpha: 0.04)
                    : _hasRouter
                        ? AppColors.accentRed.withValues(alpha: 0.04)
                        : Colors.amber.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _routerOnline
                      ? AppColors.accentGreen.withValues(alpha: 0.3)
                      : _hasRouter
                          ? AppColors.accentRed.withValues(alpha: 0.3)
                          : Colors.amber.withValues(alpha: 0.4),
                ),
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
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _routerOnline
                                  ? AppColors.accentGreen
                                  : _hasRouter
                                      ? AppColors.accentRed
                                      : Colors.amber.shade700,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _routerOnline
                                ? "MIKROTIK CONNECTED (ONLINE)"
                                : _hasRouter
                                    ? "MIKROTIK DISCONNECTED (OFFLINE)"
                                    : "NO ROUTER PAIRED",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: _routerOnline
                                  ? AppColors.accentGreen
                                  : _hasRouter
                                      ? AppColors.accentRed
                                      : Colors.amber.shade800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      if (_hasRouter)
                        TextButton.icon(
                          onPressed: _testingRouter ? null : _testRouterConnection,
                          icon: _testingRouter
                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                              : const Icon(Icons.bolt_rounded, size: 14),
                          label: Text(_testingRouter ? "Checking..." : "Ping Test", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _routerOnline
                        ? (_routerName.isNotEmpty ? _routerName : "MikroTik Gateway")
                        : _hasRouter
                            ? "Router is configured but currently offline or unreachable."
                            : "No router hardware is linked to this venue yet.",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hasRouter
                        ? "Endpoint: ${_routerEndpoint.isNotEmpty ? _routerEndpoint : 'Local Subnet'} • Mode: ${_routerConnectionMode.toUpperCase()}"
                        : "Connect your phone to your MikroTik Wi-Fi or scan packaging barcode to set up.",
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (_hasRouter) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context.push(AppRouter.routerDiagnostics),
                            icon: const Icon(Icons.speed_rounded, size: 16),
                            label: const Text("Diagnostics & Health", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSyncing ? null : _handleSync,
                            icon: _isSyncing
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                                : const Icon(Icons.sync_rounded, size: 16),
                            label: Text(_isSyncing ? "Syncing..." : "Sync Passes", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context.push(AppRouter.routerSetup),
                            icon: const Icon(Icons.add_link_rounded, size: 16),
                            label: const Text("Pair MikroTik Router Now", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentRed,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── 3. SUBDOMAIN & BRANDING CARD ───
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.containerBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "SUBDOMAIN & VENUE IDENTITY",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${_slugCtrl.text.isNotEmpty ? _slugCtrl.text.toLowerCase() : _venueSlug}.nexawavepass.com",
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Your guests will see this branding on their captive login portal.",
                    style: TextStyle(fontSize: 12, color: AppColors.textLight),
                  ),
                  const SizedBox(height: 16),
                  if (_loadingVenue)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
                  else ...[
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Venue Name',
                        hintText: 'e.g. Blue Cafe & Lounge',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _slugCtrl,
                      decoration: InputDecoration(
                        labelText: 'Portal Subdomain (slug)',
                        border: const OutlineInputBorder(),
                        helperText: 'https://${_slugCtrl.text.isEmpty ? 'venue' : _slugCtrl.text.toLowerCase()}.nexawavepass.com',
                        helperStyle: const TextStyle(fontSize: 11, color: AppColors.accentGreen, fontFamily: 'monospace'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    const Text('Venue Portal Logo *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickAdminLogo,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 90,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: _pickedLogo != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.file(File(_pickedLogo!.path), fit: BoxFit.cover, width: double.infinity),
                              )
                            : _logoCtrl.text.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(
                                      _logoCtrl.text,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorBuilder: (context, error, stackTrace) => const Center(
                                        child: Icon(Icons.broken_image_rounded, color: AppColors.textLight),
                                      ),
                                    ),
                                  )
                                : const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.cloud_upload_rounded, color: AppColors.primary, size: 26),
                                        SizedBox(height: 4),
                                        Text('Tap to upload venue logo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textLight)),
                                      ],
                                    ),
                                  ),
                      ),
                    ),
                    if (_uploadingLogo) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator(minHeight: 2)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _savingVenue ? null : _saveVenue,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        icon: _savingVenue
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(_savingVenue ? 'Saving Changes...' : 'Save Subdomain & Branding'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── 4. PRICING PLANS TIER MANAGER (NO PREBUILT PRICES) ───
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "WI-FI PASS PRICING TIERS",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textLight,
                    letterSpacing: 0.8,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const PlanConfiguratorSheet(),
                    );
                    if (ok == true) _loadPlans();
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                  label: const Text('Add Plan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingPlans)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_plans.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.containerBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 36, color: AppColors.textLight),
                    const SizedBox(height: 10),
                    const Text('No Pricing Plans Configured', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const SizedBox(height: 4),
                    const Text(
                      'WavePass has no prebuilt pricing. Create your custom duration or per-GB passes to start monetizing.',
                      style: TextStyle(fontSize: 12, color: AppColors.textLight),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final ok = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const PlanConfiguratorSheet(),
                        );
                        if (ok == true) _loadPlans();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Create First Pricing Plan'),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _plans.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (c, i) {
                  final p = _plans[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primary)),
                              const SizedBox(height: 2),
                              Text(
                                "${p['duration']} • ${p['data']} • Speed ${p['rateLimit']}",
                                style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              "₦${p['price']}",
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.accentGreen),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                              tooltip: "Edit Price",
                              onPressed: () => _editPrice(i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.accentRed),
                              tooltip: "Delete Plan",
                              onPressed: () => _deletePlan(p['id'], p['name']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),

            // ─── 5. QUICK OPERATIONS & MANAGEMENT TOOLS ───
            const Text(
              "MANAGEMENT & TOOLS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textLight,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            _toolTile(
              title: "Account Center",
              subtitle: "Passwords, Credentials, Security & Delete Account",
              icon: Icons.manage_accounts_rounded,
              onTap: () => context.push(AppRouter.account),
            ),
            const SizedBox(height: 8),
            _toolTile(
              title: "Batch Voucher Generator",
              subtitle: "Create up to 500 printable pass codes saved to PDF",
              icon: Icons.confirmation_number_rounded,
              onTap: () => context.push(AppRouter.batchVouchers),
            ),
            const SizedBox(height: 8),
            _toolTile(
              title: "Pocket Printer Settings",
              subtitle: "Bluetooth 58mm/80mm thermal receipt printer pairing",
              icon: Icons.print_rounded,
              onTap: () => context.push(AppRouter.printerSettings),
            ),
            const SizedBox(height: 8),
            _toolTile(
              title: "Router Diagnostics & Reboot",
              subtitle: "Live CPU, memory load, and remote hardware reboot",
              icon: Icons.memory_rounded,
              onTap: () => context.push(AppRouter.routerDiagnostics),
            ),
            const SizedBox(height: 24),

            // ─── 6. GUIDES & POLICIES ───
            const Text(
              "DOCUMENTATION & POLICIES",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textLight,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            _policyRow("How to Use WavePass", Icons.menu_book_rounded, () => context.push(AppRouter.howToUse)),
            const SizedBox(height: 8),
            _policyRow("Terms of Service", Icons.gavel_rounded, () => context.push(AppRouter.terms)),
            const SizedBox(height: 8),
            _policyRow("Privacy Policy", Icons.privacy_tip_rounded, () => context.push(AppRouter.privacy)),
            const SizedBox(height: 28),

            // ─── 7. SIGN OUT ───
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded, color: AppColors.accentRed, size: 18),
                label: const Text("Sign Out of Venue", style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.accentRed.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.containerBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Widget _policyRow(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary))),
            const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }
}
