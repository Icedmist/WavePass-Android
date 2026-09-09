# WavePass Android — Implementation Progress Log

## Status Overview
- **Repository**: `Icedmist/WavePass-Android`
- **Framework**: Flutter 3.41 / Dart 3.11.4
- **State Management & Routing**: `go_router` + `StatefulShellRoute` + `ValueNotifier`
- **Backend Services**: NestJS Fastify API (`api.nexawavepass.com`) + Supabase PostgreSQL
- **Static Analysis**: **0 warnings, 0 errors** (`flutter analyze` clean)
- **Unit & Widget Tests**: **All tests passing** (`flutter test` clean)

---

## Logged Milestones & Completed Tasks

### 1. Navigation Architecture & Shell Structure
- [x] Implemented unified `AppRouter` using `go_router` v14 with custom slide-fade transition animations (`Cubic(0.16, 1, 0.3, 1)`).
- [x] Designed floating pill bottom navigation shell (`ScaffoldWithNav`) hosting 5 primary tabs: Home, Active Devices, Sell Pass (prominent accent pill), Wallet, and Admin.
- [x] Resolved screen collisions by adjusting content padding (`bottomInset + 88dp`) across all root views.

### 2. Authentication & Onboarding Gate
- [x] **Session Auto-Restoration (`splash_screen.dart`)**: Checks existing Supabase auth session (`currentUser`) and stored admin credentials before onboarding logic, preventing authenticated users from being redirected to the onboarding carousel.
- [x] **Sign In / Sign Up Accessibility (`onboarding_screen.dart`)**:
  - Added prominent `Sign In` and `Sign Up` action buttons in the top AppBar.
  - Added direct `"Already have a venue? Sign In directly →"` text button on Slide 8 (venue creation step).
  - Added bottom footer row: `"Existing operator? Sign In • Create Account"`.
- [x] **Account Center Trigger (`home_dashboard_screen.dart`)**: Added an Account icon button in the dashboard AppBar navigating directly to `AppRouter.account`.
- [x] **Sign Out Cache Cleanup (`account_center_screen.dart`)**: Invalidates `sb-user-email` and `admin_token` in `SharedPreferences` upon sign-out.

### 3. POS Cash Pass Terminal & Thermal Printing (`sell_pass_screen.dart`)
- [x] **Horizontal Layout Overflows**: Fixed render overflow on narrow Android displays by wrapping plan descriptions and attributes in flexible `Expanded` and `FittedBox` containers.
- [x] **Cloud Voucher Generation**: Wired passcode generation directly to backend `POST /api/v1/vouchers/batches` with `{ venueId, planId, quantity: 1 }`, ensuring generated codes exist in the database with corresponding SHA-256 hashes.
- [x] **Robust Offline Fallback**: Generates deterministic alphanumeric fallback passes (`WP-XXXX-XXXX`) when internet connectivity is interrupted.
- [x] **Index Safety**: Clamped plan selections against runtime plan lists, resolving `RangeError (index): Invalid value: Valid value range is empty: 0`.
- [x] **ESC/POS Thermal Printing with QR Codes**: Built dynamic PDF receipt generation formatted for 58mm and 80mm thermal rolls via `package:printing` and `package:pdf`, embedding direct login QR codes (`pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: loginUrl)`).
- [x] **Cashier Screen QR Display**: Added pure Flutter `QrCodeWidget` rendered via `package:barcode` and `CustomPainter` directly on the screen so customers can scan the cashier's phone to connect and log in instantly.

### 4. High-Volume Batch Voucher Production & Mikhmon Parity (`batch_vouchers_screen.dart`)
- [x] **Multi-Source Data Loading**: Queries `WavePassApi.getDefaultVenue()` and Supabase to populate venues and active pricing tiers.
- [x] **Reactive Dropdown Bindings**: Replaced static dropdown initial values with dynamic `ValueKey` bindings, ensuring dropdowns populate properly upon asynchronous loading.
- [x] **Batch Generation (`POST /api/v1/vouchers/batches`)**: Generates 1 to 500 voucher codes in a single request.
- [x] **Customizable Generator Parameters (Mikhmon Style)**:
  - Custom Voucher Prefix (e.g. `WP-`, `VIP-`, or venue initials).
  - Configurable Code Length (4, 6, 8 characters).
  - Configurable Character Sets: `Alphanumeric` (excluding ambiguous characters), `Numbers Only`, and `Uppercase Letters`.
  - Mode Selection: `Voucher Code (Username = Password)` vs `Username & Password` (with separate generated passwords).
- [x] **Printable Cutout Cards (A4 Grid Template)**:
  - 2-column grid layout (8 cards per page) with dashed cut lines (`pw.BorderStyle.dashed`).
  - Venue name header with `WI-FI TICKET` badge.
  - Individual QR code per card encoding `http://$slug.nexawavepass.com/login?code=$code`.
  - Plan name, price badge (`₦X`), and duration/data limit.
  - Bold monospace credentials box (`VOUCHER: WP-XXXX` or dual `USER / PIN`).
  - Guest connection instructions.
- [x] **Audit Summary Table (A4)**: Clean tabular report for venue accounting and bookkeeping.
- [x] **Real-Time Voucher Filter**: Instant search filter to find vouchers by code prefix or number.
- [x] **One-Tap Clipboard Copy**: Tap any voucher code to copy with confirmation feedback.

### 5. Zero-Failure MikroTik Router Setup (`router_setup_screen.dart`, `router_discovery_service.dart`)
- [x] **Android 9+ Cleartext HTTP Traffic**: Added `android:usesCleartextTraffic="true"` and network permissions in `android/app/src/main/AndroidManifest.xml` so local subnet REST queries to `http://192.168.88.1` succeed in production release builds.
- [x] **Automated 1-Tap RouterOS REST Provisioning**:
  - Programmatically updates router system identity (`/rest/system/identity` -> `WavePass-$slug`).
  - Creates/updates hotspot profile (`/rest/ip/hotspot/profile` -> DNS `$slug.nexawavepass.com`, login-by `http-chap,http-pap,mac-cookie`).
  - Registers cloud walled garden domains (`/rest/ip/hotspot/walled-garden` -> `*.nexawavepass.com`, `*.paystack.co`, `*.supabase.co`).
  - Ensures hotspot server is bound and enabled on interface `wlan1`.
- [x] **Graceful Fallback**: If RouterOS REST API is disabled on older RouterOS v6 devices, the app automatically falls back to generating the copyable RouterOS `.rsc` provisioning script for Terminal.
- [x] **Barcode Scanner Error Handling (`barcode_scanner_screen.dart`)**:
  - Sanitizes serial numbers (`.trim().toUpperCase()`).
  - Replaced swallowed exceptions with informative error dialogs and retry capability.
  - Automatically resets `_isProcessing` state upon dismissal so the scanner remains responsive.
- [x] **Active Hotspot Session Telemetry & Hardware Disconnect**:
  - Added `fetchActiveHotspotUsers()` to query live client leases from `/rest/ip/hotspot/active`.
  - Added `disconnectHotspotUser()` to instantly kick abusive or expired clients directly at the router hardware.

### 6. Real Thermal Printer Discovery & Setup (`printer_settings_screen.dart`)
- [x] **Hardware Discovery**: Scans and lists actual paired Bluetooth and network printers using `Printing.listPrinters()`.
- [x] **Printer Selection & Persistence**: Saves selected printer URI, name, and paper width (58mm vs 80mm) in `SharedPreferences`.
- [x] **Hardware Test Receipt**: Dispatches a genuine formatting and feed check receipt to the selected thermal printer.
- [x] **Auto-Print Preference**: Persists `wavepass_auto_print_receipts` toggle to automatically trigger print jobs upon cash pass sales.

### 7. Dedicated Virtual Account Wallet & Paystack Guard (`wallet_screen.dart`)
- [x] **Paystack Mock Status Detection**: Checks `_virtualAccount?['metadata']?['mock']` and `_virtualAccount?['bankName']`.
- [x] **"Wallet Not Available" Banner**: If Paystack is not configured on the backend server, displays a clear **"Wallet Not Available"** banner explaining that active `PAYSTACK_SECRET_KEY` credentials are required.
- [x] **Action Guarding**: Disables "Add Bank" and "Cash Out" buttons and rejects execution if Paystack is unconfigured, preventing user confusion.
- [x] **Password-Confirmed Cashout**: Operators verify their personal password to disburse venue funds via Paystack transfer.

### 8. Stability Hardening & Loop Prevention
- [x] **Socket Resource Leak Resolution (`router_discovery_service.dart`)**: Wrapped all `http.Client()` calls with `try-finally` to ensure `.close()` is called on every subnet probe, active user query, and reboot command.
- [x] **Subnet & Venue State Key Synchronization (`venue_state_service.dart`, `onboarding_screen.dart`)**: Fixed mismatch where venue ID was passed instead of subdomain slug, and synced active & legacy SharedPreferences keys across onboarding and session start.
- [x] **Asynchronous State Hazards Cleared**: Resolved unmounted `setState()` across all screens.
- [x] **Auto-Refresh Loop Guard (`active_devices_screen.dart`)**: Added concurrency flag `_isRefreshing` to prevent overlapping 15-second timer requests during slow network conditions.
- [x] **Navigation Shell Pop Protection (`active_devices_screen.dart`)**: Replaced raw `Navigator.pop()` with `canPop() ? pop() : context.go('/dashboard')`.
- [x] **Provision Dialog Stack Safety (`router_diagnostics_screen.dart`)**: Added `PopScope` and dialog state tracking.
- [x] **Auth Gate Verification Loop Prevention (`signup_screen.dart`)**: Redirects to `/login` with an email confirmation prompt when session is null instead of redirecting to an unauthenticated dashboard.

### 9. Multi-Repository Agent Workflow Protocol
- [x] Created and merged `AGENT_WORKFLOW.md` across all four ecosystem repositories:
  - `Icedmist/WavePass-Android` (PR #3)
  - `Icedmist/WavePass-Backend` (PR #4)
  - `Icedmist/WavePass-Web` (PR #2)
  - `Icedmist/wavepass` (PR #2)
- [x] Established strict protocol: Issue Creation -> Feature/Fix Branch -> Verification -> Conventional Commit with `icedmist <talk2icedmist@gmail.com>` -> Pull Request -> Squash Merge -> Local Sync.

### 10. Low-RAM MikroTik Router Memory Cleanup & Rate-Limit Profiles (`router_discovery_service.dart`)
- [x] **2-Hour Auto-Cleanup Script & Scheduler (Mikhmon Parity)**:
  - Injected `/system/script` (`wavepass-cleanup` with `/ip hotspot user remove [find comment="expired"]`) and `/system/scheduler` (running every 2 hours) during `installHotspotOnRouter()`.
  - Guarantees zero out-of-memory crashes on entry-level RouterOS hardware (hAP mini, hEX lite with 32MB/64MB RAM) by automatically evicting expired hotspot user records.
- [x] **Hardware Rate-Limit User Profiles**:
  - Automatically provisions standard bandwidth tiers in RouterOS (`profile_1h` at `10M/5M`, `profile_12h` at `15M/5M`, `profile_1d` at `20M/10M`) with `shared-users=1` during 1-tap setup.
  - Enforces hardware-level traffic shaping directly through RouterOS Simple Queues.

### 11. Interactive Sales & Revenue Analytics Sheet (`home_dashboard_screen.dart`)
- [x] **Interactive Dashboard Earnings Card**:
  - Made "TODAY'S WI-FI EARNINGS" card tappable with an explicit `"Breakdown"` action pill.
  - Added an `"Analytics"` link button in the "Recent Sales Today" header.
- [x] **Comprehensive Sales Breakdown Bottom Sheet (`_SalesBreakdownSheet`)**:
  - **Dynamic Timeframe Filters**: Filter sales records across `Today`, `Last 7 Days`, and `This Month`.
  - **High-Level Financial KPI Tiles**: Total Revenue (`₦...`), Paid Passes Sold, and Average Ticket Size (`₦...`).
  - **Plan Distribution Breakdown**: Groups orders by pricing tier/plan name, showing pass count, total revenue, and visual percentage progress bars.
  - **Voucher Sales Ledger**: Complete scrollable transaction ledger displaying voucher code/customer reference, plan name, green formatted amount, and relative or formatted timestamps.
  - **Resilient Fallback**: Gracefully parses Supabase orders with fallback to local cached recent sales if offline.

### 12. Full Ecosystem Cross-Repository Parity Achieved
- [x] **`WavePass-Android`**: Zero-failure REST setup, thermal receipt QR codes, A4 voucher cutout card grids, rate-limited user profiles, auto-cleanup scheduler, and sales analytics breakdown sheet.
- [x] **`WavePass-Backend`**: Low-RAM cleanup scheduler, standard plan user profiles with speed clamps, comprehensive walled garden domains, and clean unit test suite (11/11 passing).
- [x] **`WavePass-Web`**: URL voucher auto-detection (`code` and `voucher` parameters) on captive portal, and middleware redirection (`/login?code=...` -> `/portal`) for instant 1-tap customer login upon scanning receipt QR codes.

### 13. Automated UI Verification & Layout Overflow Hardening
- [x] **Automated Sales Analytics Widget Test (`test/sales_analytics_test.dart`)**:
  - Validates dashboard earnings card presentation and `"Breakdown"` action pill trigger.
  - Verifies opening of the `_SalesBreakdownSheet` modal bottom sheet.
  - Tests timeframe tab switching (`Today`, `Last 7 Days`, `This Month`), KPI metrics display, and Plan Distribution rendering.
  - Tests modal dismissal via close button returning cleanly to dashboard.
- [x] **Layout Overflow Hardening (`home_dashboard_screen.dart`)**:
  - Wrapped AppBar title and subtitle in `Expanded` with text ellipsis to prevent horizontal overflow on narrow displays.
  - Wrapped earnings card footer text in `Flexible` with text ellipsis.
  - Wrapped Sales Analytics header column in `Expanded` with text ellipsis.
- [x] **Static Analysis & Test Verification**:
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All tests passed** (`widget_test.dart` and `sales_analytics_test.dart` passing 100%).

### 14. Dual Connection Modes (LAN & Tunnel), Default Admin Credentials, and Synchronous Router-First Voucher Provisioning (Issue #18)
- [x] **Default Admin Credentials Standardized**:
  - Removed legacy `wavepass` user probe fallback; standardized on MikroTik default `admin` user with blank password (or user-defined password).
  - Cleaned setup scripts and REST API calls across discovery service.
- [x] **Dual Connection Modes (LAN & Tunnel)**:
  - **Local Subnet Direct (LAN)**: Direct REST API communication at `http://192.168.88.1:80` with sub-millisecond latency when cashier/operator is on shop Wi-Fi.
  - **Remote Cloud / WireGuard Tunnel**: Secure remote tunnel communication (e.g. `http://10.8.0.2:80` or `https://tunnel.nexawavepass.com/...`) when operator is off-site.
  - Implemented `RouterDiscoveryService.checkDualConnection()` to concurrently probe both paths and determine optimal routing (`local` > `tunnel` > `offline`).
- [x] **Synchronous Router-First Voucher Provisioning (Mikhmon Parity)**:
  - Implemented `createHotspotUserDirectly()` and `provisionVoucherDualRoute()` in `RouterDiscoveryService`:
    - Immediately pushes generated passes to `/rest/ip/hotspot/user` via RouterOS REST API.
    - Automatic fallback from custom duration profiles (`profile_1h`, `profile_12h`, `profile_1d`) to `'default'` if custom profiles do not exist on the device.
    - Fallback from `PUT /rest/ip/hotspot/user` to `POST /rest/ip/hotspot/user/add` for maximum compatibility across RouterOS versions.
    - Cash passes are instantly live on physical router hardware at time of sale, eliminating cloud queue delay for walk-up customers.
- [x] **POS Cash Pass Terminal Integration (`sell_pass_screen.dart`)**:
  - Integrated `provisionVoucherDualRoute()` into `_handleGenerate()`.
  - Added visual hardware status badge: `"Live on Router Hardware (LAN Direct)"` / `"Live on Router Hardware (Cloud Tunnel)"` / `"Queued for Cloud Sync"`.
- [x] **High-Volume Batch Production Integration (`batch_vouchers_screen.dart`)**:
  - Automatically loops through compiled batch vouchers and provisions them directly onto physical router hardware.
  - Shows feedback on total vouchers pushed directly to hardware.
- [x] **Dual-Mode Diagnostics UI (`router_diagnostics_screen.dart`)**:
  - Added interactive **Dual-Mode Link Topology** card showing real-time ping latency, connection state, and active routing mode for both LAN Direct and Remote Tunnel.
  - Upgraded connectivity ping tests to probe both links concurrently.
- [x] **Router Setup & Configuration Script Export (`router_setup_screen.dart`)**:
  - Added optional Cloud Tunnel endpoint input field.
  - Enabled `/ip service set www disabled=no port=80` and `www-ssl port=443` in exported setup script to guarantee REST API accessibility.
- [x] **Test Verification**:
  - Added `test/router_dual_connection_test.dart` validating dual-mode status resolution, model attributes, and priority fallbacks.
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 7 tests passed**.



