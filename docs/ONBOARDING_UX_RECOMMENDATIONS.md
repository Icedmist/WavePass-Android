# Onboarding & UX Recommendations — WavePass

## Mobile Onboarding (Current: 7 cards, PageView)

**Keep:** Card-by-card swipe, dots, Skip, progress — already card-by-card as requested.

**Improve:**
- **Progress + time estimate:** Show “2 min • 7 steps” and a thin top progress bar (current 1/7 → `LinearProgressIndicator` 14% width, brand green).
- **Illustrations, not just icons:** Replace `Icons.wifi_rounded` etc. with Lottie/animated `WavePass` illustrations (e.g., router blinking, phone scanning) — 1 JSON per card, 200KB.
- **Interactive demo:** On “Auto-Find” card, add a tappable “Try scan” that opens `BarcodeScannerScreen` in demo mode (no backend), so first-time user learns the flow.
- **Value + social proof:** Add a card after Cash Out: “Venues like yours earn ₦24k/day — see live counter” with `AnimatedCounter` (already in web).
- **Personalization:** Ask venue type on card 2 (Café/Hotel/Hostel/Event) and tailor copy on next cards (“For your café, 1-hour passes sell best”).
- **Accessibility:** Add `Semantics` labels, `PageView` `onPageChanged` announces via `SemanticsService`, and `hapticFeedback` on swipe.

## App UX (Beyond Onboarding)

- **Empty states:** Replace silent offline fallbacks (now cleared) with `EmptyState` widget: illustration + “No plans yet — create your first pass” CTAs linking to `PlanConfigurator`.
- **Loading:** Replace lone `CircularProgressIndicator` with `Shimmer` skeleton for Wallet balance and plan lists.
- **Error:** Use `AppNotifier` toasts with retry action (already added) — keep.
- **Navigation:** Floating pill `NavigationBar` (black active pill) is now correct — add `Hero` logo transition Splash→Dashboard.

## Web UX

- **Portal:** After clearing `FALLBACK_PLANS`, show proper empty: “No plans configured — contact venue” + support link, not silent fallback.
- **Admin:** Replace hardcoded `support@nexawavepass.com` logged-in label with `supabase.auth.getUser().email` (done) — add avatar + venue switcher.

These keep the app production-ready without mock data, and make onboarding feel guided, not static.
