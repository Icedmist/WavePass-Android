# WavePass Mobile — Android Operator & POS Terminal (Flutter)

[![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11.4-0175C2?logo=dart)](https://dart.dev)
[![Analysis](https://img.shields.io/badge/Analysis-0%20Issues-brightgreen)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-Proprietary-black)]()

Official Flutter Android application for venue operators, retail managers, and hotspot cashiers running the **WavePass Wi-Fi Monetization Platform**. Sell thermal paper guest passes, generate encrypted voucher batches, auto-discover and manage MikroTik RouterOS gateways, audit active client sessions in real time, and cash out revenue to your bank account via dedicated virtual accounts.

![WavePass Logo](assets/images/logo.png)

---

## 🚀 Key Features

### 1. Cash Pass Sales & Instant Thermal Printing (`/sell-pass`)
- **Zero Horizontal Pixel Overflow**: Form factors dynamically scale from small 360dp screens to tablets using responsive flex layouts (`Expanded`, `FittedBox`).
- **Cloud-Backed Voucher Generation**: Generates cryptographically secure single-use voucher codes directly on the backend (`POST /api/v1/vouchers/batches`), with offline SHA-256 fallback when connectivity is interrupted.
- **Auto-Print Thermal Receipts**: Supports 58mm (pocket mobile) and 80mm (countertop) thermal rolls with instant ESC/POS spooling via `package:printing` and `package:pdf`.

### 2. High-Volume Batch Voucher Production (`/batch-vouchers`)
- **Bulk Code Generation**: Produce 1 to 500 pre-paid voucher cards simultaneously for any venue pricing plan.
- **Dynamic Form Selectors**: Venue and Plan dropdowns dynamically synchronize state via reactive `ValueKey` bindings without deprecated properties.
- **Export & Share**: Formats complete voucher sets into printable A4 / POS PDF documents, saved to device storage and immediately opened or shared.

### 3. Real Gateway Diagnostics & Health Telemetry (`/router-health`)
- **Real Backend Telemetry**: Direct integration with `WavePassApi` (`GET /api/v1/routers`, `GET /api/v1/routers/:id/health`, `POST /api/v1/routers/:id/test`).
- **Live Hardware Ping**: Live connectivity testing to physical gateways with instant status indicators (`ONLINE` / `OFFLINE`).
- **Local Subnet Interrogation**: Queries local MikroTik RouterOS v7 REST endpoints (`http://192.168.88.1/rest/system/resource`) for true CPU load, memory utilization, and hardware uptime.
- **Provisioning Script Generator**: Fetches and inspects dynamic RouterOS terminal configuration scripts (`GET /api/v1/routers/:id/provision.rsc`) with one-tap clipboard copy.
- **Clean Empty States**: Renders guided empty-state UI when no router is linked, directing operators to `/setup-router`.

### 4. Thermal Printer Setup & Hardware Pairing (`/printer-settings`)
- **Hardware Discovery**: Queries Bluetooth and network receipt printers using `Printing.listPrinters()`.
- **Hardware Feed Check**: Generates real 58mm/80mm layout test tickets to verify alignment and cutter function.
- **Configurable Preferences**: Persists default printer URL, paper width (58mm vs 80mm), and automated printing toggles in `SharedPreferences`.

### 5. Single-Key DVA Wallet & Automated Payouts (`/wallet`)
- **Dedicated Virtual Accounts**: Venue virtual bank accounts created on Nexa's single Paystack merchant key.
- **Graceful Paystack Detection**: If Paystack is not configured on the backend (`mock: true`), the screen explicitly displays **"Wallet Not Available"**, explains server setup requirements, and disables cashout operations to prevent operator confusion.
- **Password-Confirmed Cashout**: Operators verify their personal password to disburse venue revenue to their registered NUBAN bank account without manual platform admin approval.

### 6. Seamless Onboarding & Authentication
- **Unrestricted Authentication Access**: Prominent `Sign In` and `Sign Up` buttons in the top AppBar and bottom footer of the onboarding carousel (`/onboarding`), ensuring existing venue owners are never trapped.
- **Session Auto-Restoration**: Splash screen (`/`) verifies active Supabase sessions and stored admin tokens, immediately routing authenticated operators to the dashboard (`/dashboard`).
- **Account Management**: Profile and session center (`/account`) with complete sign-out cache invalidation.

---

## 📁 Project Structure

```
wavepass-android/
├── analysis_options.yaml       # Dart analysis & strict linter rules (0 issues)
├── assets/
│   └── images/
│       └── logo.png            # Official black squircle logo mark (1254x1254)
├── lib/
│   ├── main.dart               # Entry point, Supabase initialization, Root App
│   ├── core/
│   │   ├── constants/
│   │   │   └── api_constants.dart       # API base URLs, Supabase credentials, endpoints
│   │   ├── navigation/
│   │   │   ├── app_router.dart          # Centralized GoRouter declarations & transitions
│   │   │   └── scaffold_with_nav.dart   # Floating pill bottom navigation shell
│   │   ├── services/
│   │   │   ├── notification_service.dart # Toast & in-app notification manager
│   │   │   ├── router_discovery_service.dart # MikroTik REST subnet probe & reboot
│   │   │   ├── supabase_service.dart    # Supabase Client, Auth, Venue, Plan & Session queries
│   │   │   └── wavepass_api.dart        # NestJS REST Client (Routers, DVA, Cashouts, Stats)
│   │   ├── theme/
│   │   │   └── app_theme.dart           # Nexa dark/light palette, typography & radii
│   │   └── widgets/
│   │       ├── empty_state.dart         # Universal empty illustration component
│   │       ├── plan_configurator.dart   # Duration/Data slider modal for pass creation
│   │       └── shimmer.dart             # Skeleton loading boxes
│   └── screens/
│       ├── account_center_screen.dart   # Profile, venue settings, legal & sign out
│       ├── active_devices_screen.dart   # Connected client sessions & countdowns
│       ├── admin_management_screen.dart # Subdomain, logo branding, and pricing rules
│       ├── barcode_scanner_screen.dart  # Camera barcode reader for router serials
│       ├── batch_vouchers_screen.dart   # Bulk voucher generation & PDF exporter
│       ├── home_dashboard_screen.dart   # Live revenue, active users, router status & shortcuts
│       ├── how_to_use_screen.dart       # Operator manual & hardware hookup guide
│       ├── login_screen.dart            # Operator email & password authentication
│       ├── notifications_screen.dart    # System alerts & activity log
│       ├── onboarding_screen.dart       # Interactive intro & venue creation wizard
│       ├── printer_settings_screen.dart # Bluetooth thermal printer pairing & test print
│       ├── privacy_screen.dart          # Privacy policy & data protection terms
│       ├── router_diagnostics_screen.dart# Real router health, ping test, & ROS scripts
│       ├── router_setup_screen.dart     # Auto-find on Wi-Fi or barcode serial provision
│       ├── sell_pass_screen.dart        # Cash pass POS checkout & instant receipt printing
│       ├── signup_screen.dart           # Operator account registration
│       ├── splash_screen.dart           # Session check & animated splash gate
│       ├── terms_screen.dart            # Platform terms of service
│       └── wallet_screen.dart           # DVA balance, bank registration & cashouts
├── pubspec.yaml                # Flutter dependencies & asset declarations
└── test/
    └── widget_test.dart        # Widget & screen smoke test suite
```

---

## 🗺️ Navigation & Route Map

Navigation is managed via `go_router` with a floating pill bottom navigation shell (`ScaffoldWithNav`).

| Route Name | Path | Description |
|---|---|---|
| `AppRouter.splash` | `/` | Checks existing auth session and redirects to dashboard or onboarding |
| `AppRouter.onboarding` | `/onboarding` | 8-step visual walkthrough and new venue provisioning form |
| `AppRouter.login` | `/login` | Email / password login with fallback to backend verification |
| `AppRouter.signup` | `/signup` | Operator account registration |
| `AppRouter.dashboard` | `/dashboard` | Main telemetry hub (Today's Sales, Active Users, Gateway Status) |
| `AppRouter.activeDevices` | `/active-devices` | Real-time list of connected guests with countdown timers |
| `AppRouter.sellPass` | `/sell-pass` | POS terminal for cash sales, plan selection, and receipt printing |
| `AppRouter.batchVouchers` | `/batch-vouchers` | High-volume batch voucher generation and PDF exporter |
| `AppRouter.routerDiagnostics` | `/router-health` | Gateway health metrics, live ping tests, and RouterOS scripts |
| `AppRouter.routerSetup` | `/setup-router` | Auto-discovery (192.168.88.1) and serial barcode provisioning |
| `AppRouter.printerSettings` | `/printer-settings` | Bluetooth / network thermal printer pairing and paper width setup |
| `AppRouter.wallet` | `/wallet` | DVA virtual account details, balance, and owner cashouts |
| `AppRouter.admin` | `/admin` | Venue subdomain, logo branding, and pricing plan editor |
| `AppRouter.account` | `/account` | Operator profile, venue info, and sign out |
| `AppRouter.notifications` | `/notifications` | Live push and alert history |
| `AppRouter.howToUse` | `/how-to-use` | Hardware setup and operator walkthrough |
| `AppRouter.terms` | `/terms` | Terms of service |
| `AppRouter.privacy` | `/privacy` | Privacy policy |

---

## 🛠️ Build & Verification

```bash
# Get dependencies
flutter pub get

# Run static analysis (0 warnings, 0 errors)
flutter analyze

# Launch on connected Android device or emulator
flutter run -d android

# Build release APK
flutter build apk --release

# Build release App Bundle for Google Play
flutter build appbundle --release
```

---

## 🔐 Credentials & Environment Setup

Configure `lib/core/constants/api_constants.dart`:
- `cloudBaseUrl`: Base URL of the NestJS backend (`https://api.nexawavepass.com` or `http://10.0.2.2:3000` for Android emulator).
- `supabaseUrl`: Supabase project URL (`https://vvoenmdzavyzlisykhks.supabase.co`).
- `supabaseAnonKey`: Supabase public anonymous API key.
