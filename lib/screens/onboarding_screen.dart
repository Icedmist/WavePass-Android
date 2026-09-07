import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/router/app_router.dart';
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
  final _venueLogo = TextEditingController(text: 'https://wavepass-web.vercel.app/logo.png');
  bool _creatingVenue = false;
  String? _venueError;

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

  Future<void> _createVenueAndFinish() async {
    if (_venueName.text.trim().isEmpty || _venueSlug.text.trim().isEmpty || _venueLogo.text.trim().isEmpty) {
      setState(() => _venueError = 'Venue name, subdomain (slug) and logo URL are required — your subdomain will be {slug}.wavepass.com with your pricing & logo.');
      return;
    }
    setState(() { _creatingVenue = true; _venueError = null; });
    try {
      await WavePassApi.instance.createVenue(name: _venueName.text.trim(), slug: _venueSlug.text.trim().toLowerCase(), logoUrl: _venueLogo.text.trim());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
      if (!mounted) return;
      context.go(AppRouter.login);
    } catch (e) {
      setState(() => _venueError = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _creatingVenue = false);
    }
  }

  Future<void> _finishOnboarding() async {
    if (_currentPage == _slides.length - 1) {
      // last card is venue creation — require it
      await _createVenueAndFinish();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    context.go(AppRouter.login);
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
              // Top Skip Row
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
                  TextButton(
                    onPressed: _finishOnboarding,
                    child: const Text(
                      "Skip",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Carousel View
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
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
                            TextField(controller: _venueSlug, decoration: InputDecoration(hintText: 'my-venue', labelText: 'Subdomain (slug) *', helperText: _venueSlug.text.isEmpty ? 'your-venue.wavepass.com' : '${_venueSlug.text.toLowerCase()}.wavepass.com'), onChanged: (_) => setState(() {})),
                            const SizedBox(height: 10),
                            TextField(controller: _venueLogo, decoration: const InputDecoration(hintText: 'https://.../logo.png', labelText: 'Logo URL *', helperText: 'Required — shown on your subdomain')),
                            if (_venueError != null) ...[
                              const SizedBox(height: 10),
                              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.redTint, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.3))), child: Text(_venueError!, style: const TextStyle(fontSize: 11, color: AppColors.accentRedDark))),
                            ],
                            const SizedBox(height: 12),
                            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)), child: const Text('After venue creation, add at least one pricing plan (duration / per-GB) — required to go live.', style: TextStyle(fontSize: 11, color: AppColors.textLight))),
                          ]),
                        ),
                      );
                    }
                    return Center(
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
                              slide['title'] as String,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              slide['subtitle'] as String,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textLight,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
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
                      onPressed: () {
                        if (_currentPage == _slides.length - 1) {
                          _finishOnboarding();
                        } else {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                      ),
                      child: Text(
                        _currentPage == _slides.length - 1 ? "Get Started" : "Next →",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ),
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
