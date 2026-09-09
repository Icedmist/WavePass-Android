import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/router/app_router.dart';
import '../core/services/supabase_service.dart';
import '../core/services/venue_state_service.dart';
import '../core/services/wavepass_api.dart';
import '../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final _venueName = TextEditingController();
  final _venueSlug = TextEditingController();
  final _venueLogo = TextEditingController(text: 'https://nexawavepass.com/logo.png');
  XFile? _pickedLogo;
  String? _uploadedLogoUrl;
  bool _uploadingLogo = false;
  bool _creatingVenue = false;
  String? _venueError;
  String _venueType = 'Café';

  final List<Map<String, dynamic>> _slides = [
    {
      'tag': '01 / DAILY INCOME',
      'title': 'Turn Wi-Fi Into Daily Revenue',
      'subtitle': 'Guests pay on their phone or buy cash passes from staff. No messy passwords.',
      'icon': Icons.wifi_rounded,
      'badge': 'Zero Staff Effort',
    },
    {
      'tag': '02 / PLUG IN',
      'title': 'Plug In Your Router',
      'subtitle': 'Power the MikroTik and plug internet into Port 1 (WAN). One cable, done.',
      'icon': Icons.power_rounded,
      'badge': 'Step 1 • How to Use',
    },
    {
      'tag': '03 / CONNECT',
      'title': 'Connect Phone to Router Wi-Fi',
      'subtitle': 'Join the open SSID (MikroTik) — no password needed for setup.',
      'icon': Icons.phone_iphone_rounded,
      'badge': 'Step 2 • Card by Card',
    },
    {
      'tag': '04 / AUTO-FIND',
      'title': 'Auto-Find in 5 Seconds',
      'subtitle': 'In Router Setup tap “Find My Router” — detects 192.168.88.1 and installs HotSpot.',
      'icon': Icons.radar_rounded,
      'badge': 'Approach 1',
    },
    {
      'tag': '05 / SCAN BARCODE',
      'title': 'Or Scan Box Barcode',
      'subtitle': 'Still boxed? Scan the serial — router self-configures on boot via cloud.',
      'icon': Icons.qr_code_scanner_rounded,
      'badge': 'Approach 2',
    },
    {
      'tag': '06 / SELL & CUSTOMIZE',
      'title': 'Sell Passes — Your Rules',
      'subtitle': 'Choose duration (30m–72h) or per-GB cap, set NGN price, Mbps and devices. Guests pay or get a printed WP-XXXX-XXXX.',
      'icon': Icons.tune_rounded,
      'badge': 'Duration • Per-GB • Price',
    },
    {
      'tag': '07 / CASH OUT',
      'title': 'Print & Cash Out Instantly',
      'subtitle': 'Bluetooth POS prints in 1 tap. Balance lands in your DVA — cash out with your owner password, no admin wait.',
      'icon': Icons.receipt_long_rounded,
      'badge': 'Bluetooth POS Ready',
    },
    {
      'tag': '08 / YOUR VENUE',
      'title': 'Create Your Venue',
      'subtitle': 'Pick a subdomain, upload logo and set your pricing — required to go live.',
      'icon': Icons.store_rounded,
      'badge': 'Subdomain • Logo • Pricing Required',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _venueName.dispose();
    _venueSlug.dispose();
    _venueLogo.dispose();
    super.dispose();
  }

  Future<void> _pickVenueLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (picked != null) {
      setState(() { _pickedLogo = picked; _uploadingLogo = true; });
      try {
        final rawBytes = await picked.readAsBytes();
        // Compress before upload — keep under ~300KB
        final compressed = await FlutterImageCompress.compressWithList(rawBytes, minWidth: 800, minHeight: 800, quality: 70, format: CompressFormat.jpeg);
        final bytes = compressed.isNotEmpty ? compressed : rawBytes;
        final fileName = 'venue-${DateTime.now().millisecondsSinceEpoch}-${picked.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.jpg';
        try {
          await SupabaseService.instance.client.storage.from('venue_logos').uploadBinary(fileName, bytes);
          final url = SupabaseService.instance.client.storage.from('venue_logos').getPublicUrl(fileName);
          setState(() { _uploadedLogoUrl = url; _venueLogo.text = url; });
        } catch (_) {
          try {
            await SupabaseService.instance.client.storage.from('venue-logos').uploadBinary(fileName, bytes);
            final url = SupabaseService.instance.client.storage.from('venue-logos').getPublicUrl(fileName);
            setState(() { _uploadedLogoUrl = url; _venueLogo.text = url; });
          } catch (_) {
            setState(() { _uploadedLogoUrl = null; _venueLogo.text = 'https://nexawavepass.com/logo.png'; });
          }
        }
      } finally {
        setState(() => _uploadingLogo = false);
      }
    }
  }

  Future<void> _createVenueAndFinish() async {
    final logoUrl = _uploadedLogoUrl ?? _venueLogo.text.trim();
    if (_venueName.text.trim().isEmpty || _venueSlug.text.trim().isEmpty || logoUrl.isEmpty) {
      setState(() => _venueError = 'Venue name, subdomain (slug) and logo image are required — your subdomain will be {slug}.nexawavepass.com with your pricing & logo.');
      return;
    }
    if (_pickedLogo == null && _uploadedLogoUrl == null && _venueLogo.text.trim().isEmpty) {
      setState(() => _venueError = 'Please upload a venue logo image.');
      return;
    }
    setState(() { _creatingVenue = true; _venueError = null; });
    try {
      final res = await WavePassApi.instance.createVenue(name: _venueName.text.trim(), slug: _venueSlug.text.trim().toLowerCase(), logoUrl: logoUrl);
      final vId = res['id']?.toString() ?? _venueSlug.text.trim().toLowerCase();
      final vName = _venueName.text.trim();
      final vSlug = _venueSlug.text.trim().toLowerCase();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
      await prefs.setString('wavepass_active_venue_id', vId);
      await prefs.setString('venueId', vId);
      await prefs.setString('wavepass_active_venue_name', vName);
      await prefs.setString('venueName', vName);
      await prefs.setString('wavepass_active_venue_slug', vSlug);
      await prefs.setString('venueSlug', vSlug);
      await prefs.setString('wavepass_active_venue_logo', logoUrl);
      await prefs.setString('venueLogo', logoUrl);

      VenueStateService.instance.venueNotifier.value = {
        'id': vId,
        'name': vName,
        'slug': vSlug,
        'logoUrl': logoUrl,
      };

      if (!mounted) return;
      // If user already signed in, go to dashboard; else to login (which will then go to dashboard after auth)
      final user = SupabaseService.instance.currentUser;
      if (user != null) {
        context.go(AppRouter.dashboard);
      } else {
        context.go(AppRouter.login);
      }
    } catch (e) {
      setState(() => _venueError = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _creatingVenue = false);
    }
  }

  Future<void> _goToLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    context.go(AppRouter.login);
  }

  Future<void> _goToSignup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    context.go(AppRouter.signup);
  }

  Future<void> _finishOnboarding() async {
    if (_currentPage == _slides.length - 1 && _venueName.text.trim().isNotEmpty) {
      await _createVenueAndFinish();
      return;
    }
    await _goToLogin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              // Top Action Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "WavePass",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _goToLogin,
                        child: const Text(
                          "Sign In",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _goToSignup,
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress + estimate
              Row(children: [
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: (_currentPage + 1) / _slides.length, minHeight: 4, backgroundColor: Colors.black12, valueColor: const AlwaysStoppedAnimation(AppColors.accentGreen)))),
                const SizedBox(width: 8),
                Text('${_currentPage + 1}/${_slides.length} • 2 min', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, fontFamily: 'monospace')),
              ]),
              const SizedBox(height: 16),
              // Venue type personalization (on first two cards)
              if (_currentPage <= 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: 6, runSpacing: 6, children: ['Café', 'Hotel', 'Hostel', 'Event'].map((t) => ChoiceChip(label: Text(t, style: const TextStyle(fontSize: 11)), selected: _venueType == t, onSelected: (_) { HapticFeedback.selectionClick(); setState(() => _venueType = t); }, selectedColor: AppColors.primary, labelStyle: TextStyle(color: _venueType == t ? Colors.white : AppColors.primary, fontWeight: FontWeight.w700))).toList()),
                ),

              // Carousel View
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    HapticFeedback.selectionClick();
                    setState(() => _currentPage = index);
                  },
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    final isVenueCard = index == _slides.length - 1;
                    if (isVenueCard) {
                      return SingleChildScrollView(
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(color: AppColors.containerBg, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.cardBorder)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(width: 56, height: 56, decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)), child: Icon(slide['icon'] as IconData, size: 28, color: AppColors.primary)),
                            const SizedBox(height: 16),
                            Text(slide['tag'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'monospace', color: AppColors.accentGreen, letterSpacing: 0.8)),
                            const SizedBox(height: 8),
                            Text(slide['title'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: -0.5)),
                            const SizedBox(height: 8),
                            Text(slide['subtitle'] as String, style: const TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.4)),
                            const SizedBox(height: 16),
                            TextField(controller: _venueName, decoration: const InputDecoration(hintText: 'Venue name (e.g. Cafe Lagos)', labelText: 'Venue Name *')),
                            const SizedBox(height: 10),
                            TextField(controller: _venueSlug, decoration: InputDecoration(hintText: 'my-venue', labelText: 'Subdomain (slug) *', helperText: _venueSlug.text.isEmpty ? 'your-venue.nexawavepass.com' : '${_venueSlug.text.toLowerCase()}.nexawavepass.com'), onChanged: (_) => setState(() {})),
                            const SizedBox(height: 10),
                            // Venue logo upload (not URL)
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Venue Logo *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textMuted)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _pickVenueLogo,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  height: 96,
                                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
                                  child: _pickedLogo != null
                                      ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_pickedLogo!.path), fit: BoxFit.cover, width: double.infinity))
                                      : _uploadedLogoUrl != null
                                          ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_uploadedLogoUrl!, fit: BoxFit.cover, width: double.infinity, errorBuilder: (ctx, err, stack) => const Center(child: Icon(Icons.broken_image_rounded, color: AppColors.textLight))))
                                          : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.upload_rounded, color: AppColors.primary), SizedBox(height: 4), Text('Tap to upload logo', style: TextStyle(fontSize: 11, color: AppColors.textLight))])),
                                ),
                              ),
                              if (_uploadingLogo) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator(minHeight: 2)),
                              const SizedBox(height: 4),
                              const Text('Required — shown on your subdomain portal', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                            ]),
                            if (_venueError != null) ...[
                              const SizedBox(height: 10),
                              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.redTint, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.3))), child: Text(_venueError!, style: const TextStyle(fontSize: 11, color: AppColors.accentRedDark))),
                            ],
                            const SizedBox(height: 12),
                            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)), child: const Text('After venue creation, add at least one pricing plan (duration / per-GB) — required to go live.', style: TextStyle(fontSize: 11, color: AppColors.textLight))),
                            const SizedBox(height: 14),
                            Center(
                              child: TextButton(
                                onPressed: _goToLogin,
                                child: const Text('Already have a venue? Sign In directly →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
                              ),
                            ),
                          ]),
                        ),
                      );
                    }
                    final title = index == 5 && _venueType != 'Café' ? 'Sell Passes for Your $_venueType' : slide['title'] as String;
                    final subtitle = index == 1 ? 'For your $_venueType, setup takes 5 seconds — no typing.' : slide['subtitle'] as String;
                    return Semantics(
                      label: '${slide['title']} — ${slide['subtitle']}',
                      button: false,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: AppColors.containerBg,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppColors.cardBorder),
                                ),
                                child: Icon(
                                  slide['icon'] as IconData,
                                  size: 28,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                slide['tag'] as String,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'monospace',
                                  color: AppColors.accentGreen,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primary,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textLight,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (index == 3 || index == 4)
                                OutlinedButton.icon(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Demo Scan'), content: const Text('Camera would open here — demo captured serial WP-SCAN-1234'), actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Got it'))]));
                                  },
                                  icon: const Icon(Icons.camera_alt_rounded, size: 16),
                                  label: const Text('Try scan demo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                              if (index == 6)
                                Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
                                  child: Row(children: [
                                    const Icon(Icons.trending_up_rounded, size: 18, color: AppColors.accentGreen),
                                    const SizedBox(width: 8),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('Venues like your $_venueType earn ₦24k/day', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
                                      const Text('Live counter • 1,240 venues', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                                    ])),
                                  ]),
                                ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.cardBorder),
                                ),
                                child: Text(
                                  slide['badge'] as String,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Bottom Indicator & Next Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dot Indicators
                  Row(
                    children: List.generate(
                      _slides.length,
                      (i) => Container(
                        margin: const EdgeInsets.only(right: 6),
                        width: _currentPage == i ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _currentPage == i ? AppColors.primary : Colors.black12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  // Button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _creatingVenue
                          ? null
                          : () {
                              if (_currentPage == _slides.length - 1) {
                                _finishOnboarding();
                              } else {
                                _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                              }
                            },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 24)),
                      child: _creatingVenue && _currentPage == _slides.length - 1
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_currentPage == _slides.length - 1 ? "Create Venue →" : "Next →", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Existing operator? ", style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                  GestureDetector(
                    onTap: _goToLogin,
                    child: const Text("Sign In", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ),
                  const Text("  •  ", style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                  GestureDetector(
                    onTap: _goToSignup,
                    child: const Text("Create Account", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
