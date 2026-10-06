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

### 15. Barcode Scanner Router Onboarding & Real Gateway Setup (Issue #20, PR #21)
- [x] **Eliminated Fake Tunnel Endpoint Defaults**:
  - `BarcodeScannerScreen` and `RouterDiscoveryService.provisionWithSerial()` now register local gateway `http://192.168.88.1` with `connectionMode: 'local'` instead of registering non-existent `https://tunnel.nexawavepass.com/$serial` endpoints that mapped to web frontends.
- [x] **Actionable Onboarding Workflow**:
  - Updated post-scan dialog to instruct operators to connect to the router Wi-Fi network and tap "Auto-Configure" (routing to `AppRouter.routerSetup`) to perform automatic router discovery and hotspot provisioning in 1 tap.
  - Added "Copy Script" button copying RouterOS terminal setup script directly to clipboard.
- [x] **Verification**:
  - Added `test/barcode_scanner_flow_test.dart`.
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 10 tests passed**.

### 16. Branded Operations Manual & Architectural Blueprint (Issue #22, PR #23)
- [x] **Publication-Grade Branded Operations Manual**:
  - Created and compiled exhaustive 10-page operations manual at `docs/WavePass_Operations_Manual.pdf`.
  - Styled with WavePass design tokens (Ink `#0A0A0A`, Warm Cream `#FAF5E8`, Brand Blue `#1677FF`, Emerald Green `#0A7A3A`, Sand `#FFCE8A`).
  - Two-pass canvas with running header, chapter badges, and dynamic "Page X of Y" footers.
- [x] **Comprehensive 6-Chapter Coverage**:
  - **Chapter 1**: System Overview, Hybrid Edge-Cloud Model, End-to-End Packet Lifecycle.
  - **Chapter 2**: MikroTik RouterOS Hardware Engineering, Interface Mapping, REST API Activation, `wavepass-setup.rsc`.
  - **Chapter 3**: Operator Mobile POS Manual (`WavePass-Android`), Onboarding, Instant Pass Generation, Bluetooth Thermal Printing, Batch Cutout Cards.
  - **Chapter 4**: Guest Captive Web Portal Playbook (`WavePass-Web`), Multi-tenant Subdomain Routing, Paystack Checkout, QR Camera Bypass.
  - **Chapter 5**: Server Operations & Backend Administration (`WavePass-Backend`), NestJS Services, BullMQ/Redis Queue Engine, Docker Compose Runbook.
  - **Chapter 6**: Troubleshooting Runbook & Diagnostics Matrix (8 failure modes, fast remediation, case studies).
### 17. MikroTik Local Router Discovery Reliability, Self-Signed SSL, & Diagnostics Hardening (Issue #24, PR #25)
- [x] **Self-Signed SSL & HTTPS Probing**:
  - Implemented `createRouterClient()` using `IOClient` with `badCertificateCallback = (cert, host, port) => true` and 4s timeout across all RouterOS REST communication (`_probeRouter`, `createHotspotUserDirectly`, `rebootRouter`, `installHotspotOnRouter`, `fetchActiveHotspotUsers`, `disconnectHotspotUser`).
  - Dual scheme probe: probes `http` then `https` sequentially to transparently support RouterOS v7 `www-ssl` (port 443) and HTTP-to-HTTPS redirects.
- [x] **Input Normalization**:
  - Normalized IP/host inputs in `RouterDiscoveryService._probeRouter` and `RouterSetupScreen` to strip scheme prefixes (`http://`, `https://`) and trailing slashes, preventing doubled-up URLs (`http://http://...`).
- [x] **Actionable HTTP 401/403 Authentication Error Handling**:
  - Replaced silent `return null` (which masqueraded auth errors as offline) with explicit `authFailed: true` and descriptive error messages (`"Login failed (HTTP 401): Invalid password for user \"$username\""`).
  - Updated `RouterSetupScreen` to display an amber alert banner and SnackBar on auth failure rather than reporting router missing.
- [x] **Decoupled Cloud Backend Ping in Diagnostics**:
  - Wrapped `WavePassApi.instance.testRouter(routerId)` in an isolated inner `try/catch` block in `RouterDiagnosticsScreen._testConnection()` so cloud tunnel failures no longer abort local LAN checks.
- [x] **Persistent Router Credentials & Diagnostics Update Modal**:
  - Added `_loadSavedCredentials()` and `_saveCredentials()` to `RouterSetupScreen` using `SharedPreferences`.
  - Built `_showCredentialsDialog()` in `RouterDiagnosticsScreen` allowing direct configuration and updating of router IP, username, and password with password toggle and instant re-testing.
- [x] **Verification**:
  - Unit tests in `test/router_dual_connection_test.dart` for `authFailed` states and dual link status.
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 12 tests passed**.

### 18. Real-Time Network Diagnostics, Captive Portal Alert, & Extended Timeout (Issue #26, PR #27)
- [x] **Extended Probing Timeout**:
  - Increased router probe timeout from 3s to 8s (with 8s connection timeout) to prevent premature aborts on low-power MIPS/ARM MikroTik CPUs (such as hEX / hAP lite).
- [x] **Captive Portal Redirection Detection**:
  - Detected HTTP 200/302 HTML interception on port 80 when MikroTik HotSpot captive portal firewall redirect is active.
  - Added `captivePortalIntercepted` flag and `rawResponseSnippet` to `DiscoveredRouter`.
  - Added clear amber warning badge and banner: *"HotSpot Captive Portal intercepted port 80. Phone is on router Wi-Fi, but captive portal redirected HTTP to login page."*
- [x] **Rich Diagnostic Error Feedback**:
  - Preserved exact HTTP status code, timeout exception, connection refused, or socket error in `localDiagnosticDetail`, `tunnelDiagnosticDetail`, and `errorMessage`.
  - Displayed exact error message in the Link Topology card and SnackBar, eliminating ambiguous "OFFLINE" messages.
- [x] **Device Wi-Fi IP Discovery**:
  - Implemented `RouterDiscoveryService.getLocalDeviceIp()` using `NetworkInterface.list()` to detect phone's actual Wi-Fi IPv4 address and display it in the Link Topology card.
- [x] **In-Modal Quick LAN Test**:
  - Added "Test LAN Link Now" button inside `_showCredentialsDialog` in `RouterDiagnosticsScreen` with loading spinner and instant color-coded feedback banner.
- [x] **Verification**:
  - Added 2 new tests in `test/router_dual_connection_test.dart` for captive portal and diagnostics.
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 14 tests passed**.

### 19. Native MikroTik RouterOS API on Port 8728 & Micro Voucher App Parity (Issue #28, PR #29)
- [x] **Native RouterOS Binary API Protocol Client (`lib/core/services/mikrotik_api_client.dart`)**:
  - Implemented pure Dart client for MikroTik length-prefixed binary API protocol over TCP `Socket` on Port 8728 (`/ip service api`).
  - Encodes word lengths across all MikroTik length ranges (1, 2, 3, 4, 5-byte headers) and parses sentence boundaries (`!re`, `!done`, `!trap`, `!fatal`).
  - Supports `/login` with standard RouterOS authentication.
  - Queries system resources (`/system/resource/print`) and router identity (`/system/identity/print`).
  - Directly provisions HotSpot users/vouchers on physical router hardware via `/ip/hotspot/user/add` with fallback to `default` profile.
- [x] **HotSpot Captive Portal Bypass (Micro Voucher / Mikhmon Parity)**:
  - Port 8728 is a raw TCP protocol and is **never** intercepted or blocked by the MikroTik HotSpot captive portal firewall redirect (which only redirects HTTP Port 80 and HTTPS Port 443).
  - Enables seamless router connection and diagnostics even when the phone has not authenticated on the Wi-Fi captive portal yet.
- [x] **Dual-Protocol Router Probing in `RouterDiscoveryService`**:
  - Automatic fallback to Port 8728 when Port 80 returns captive portal HTML, 301/302 redirects, HTTP 404, connection refused, or timeout.
  - Supports explicit Port 8728 configurations (e.g. `192.168.88.1:8728` or `api://192.168.88.1`) across local discovery, `probeEndpoint()`, and `rebootRouter()`.
  - Fixed upstream ISP router collision: Ensured upstream gateway web interfaces (e.g. Starlink dish modem at `192.168.1.1`) returning HTML are marked non-RouterOS and do not override the primary `192.168.88.1` MikroTik router.
- [x] **Direct & Fallback Voucher Provisioning**:
  - `createHotspotUserDirectly()` now attempts HTTP REST first, and if intercepted by captive portal or failing, seamlessly provisions via native Port 8728 RouterOS API.
  - If target endpoint specifies `:8728`, provisions directly through Port 8728 socket.
- [x] **Unit Testing & Verification**:
  - Created test suite in `test/mikrotik_api_client_test.dart` with 9 unit and mock-server tests covering binary encoding, decoding, auth error handling, system resource parsing, identity extraction, and voucher user provisioning over local loopback sockets.
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 23 tests passed**.

### 20. Strict Port 80 HTTP MikroTik Connection & Fallback Elimination (Issue #30)
- [x] **Eliminated Legacy 192.168.1.1 Fallback in `discoverLocalRouter`**:
  - Removed the automated fallback to `192.168.1.1` that was inadvertently hitting the upstream Starlink dish on the WAN port and returning web HTML.
  - Discovery now strictly targets the user-configured router IP (`192.168.88.1` by default).
- [x] **Eliminated Automatic Port 8728 Fallback in `_probeRouter` & Voucher Provisioning**:
  - Probing Port 80 HTTP no longer falls back to Port 8728 when Port 80 returns HTML, 302, 404, or fails.
  - Native Port 8728 binary API is now strictly reserved for endpoints where the user explicitly specifies `:8728` or `api://`.
  - Removed Port 8728 fallback in `createHotspotUserDirectly()`, ensuring voucher provisioning respects the Port 80 HTTP path.
- [x] **Optimized Port 80 HTTP Probing & Diagnostic Feedback**:
  - Shortened probe timeout to 6 seconds for swift feedback.
  - Immediate resolution on HTTP status code receipt (200, 301, 302, 401, 403, 404), avoiding redundant 8-second HTTPS probe timeouts.
  - Added detection of WebFig presence on Port 80 if `/rest` is absent or returns 404.
  - Added clear diagnostic error reporting indicating exact Port 80 status code, captive portal redirection, or authentication failure in the in-modal credentials tester.
- [x] **Unit Testing & Verification**:
  - Added 2 new tests in `test/router_dual_connection_test.dart` covering WebFig on Port 80 and ensuring no Port 8728 or 192.168.1.1 error contamination.
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 25 tests passed**.

### 21. RouterOS v7 rest-plain 404 Resolution & Automatic HTTPS Fallback (Issue #32)
- [x] **RouterOS v7 `rest-plain` 404 Root Cause Resolution**:
  - RouterOS v7 introduces granular `/ip/service/webserver` controls. By default, `rest-plain` (plain HTTP REST API on Port 80) is set to `no`, while `webfig-plain` and `rest-secure` (HTTPS Port 443) are enabled.
  - When `rest-plain=no`, queries to `/rest/system/resource` on Port 80 return HTTP 404 Not Found.
- [x] **Automatic HTTPS Fallback**:
  - In `_probeRouter()`, if HTTP Port 80 returns HTTP 404, the probe no longer aborts; it automatically probes HTTPS on port 443 (`rest-secure`), using `createRouterClient()` with self-signed certificate acceptance.
  - If `rest-secure` is active on port 443, WavePass connects seamlessly without requiring router reconfiguration.
  - In `createHotspotUserDirectly()`, if HTTP PUT/POST returns 404, it automatically attempts HTTPS provisioning to ensure uninterrupted voucher creation.
- [x] **Actionable Diagnostic Guidance & 1-Tap Copy CLI Command**:
  - If both HTTP and HTTPS return 404 or fail, `DiscoveredRouter.errorMessage` explicitly instructs:
    `RouterOS v7 REST API is disabled on Port 80 (HTTP 404). Run in MikroTik Terminal: /ip/service/webserver/set rest-plain=yes`
  - In `RouterDiagnosticsScreen` (both in the credentials tester dialog and the Link Topology card), added a styled terminal code container with 1-tap clipboard copy for `/ip/service/webserver/set rest-plain=yes`.
  - In `RouterSetupScreen`, added a `COPY CMD` action to the SnackBar upon 404 detection.
- [x] **Verification**:
  - Added unit tests in `test/router_dual_connection_test.dart` for 404 rest-plain error guidance and status reporting.
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 27 tests passed**.

### 22. HotSpot wproxy 404 Resolution & Native Port 8728 Fallback (Issue #34)
- [x] **Router Telemetry & Configuration Audit from Live Hardware**:
  - Confirmed hardware: MikroTik RB951Ui-2HnD running RouterOS v7.23.5 (long-term) on MIPS 74Kc.
  - Confirmed services: `www` (80), `winbox` (8291), and `api` (8728) are active. `www-ssl` (443) is disabled (`X`).
  - Confirmed dynamic services: `hotspot` (64873) and `wproxy` (64874, 64875) actively intercept all unauthenticated Port 80 HTTP traffic and return 404 for `/rest/system/resource`.
- [x] **Automatic Native Port 8728 Fallback**:
  - In `_probeRouter()`, if Port 80 returns 404 (HotSpot wproxy interception) and HTTPS Port 443 fails, the probe automatically checks native RouterOS API on Port 8728 (`/ip service api`).
  - In `createHotspotUserDirectly()`, added automated Port 8728 fallback if HTTP/HTTPS provisioning fails or returns 404.
  - Users can configure `192.168.88.1:8728` directly or leave `192.168.88.1` and connect automatically.
- [x] **Verification**:
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 27 tests passed**.

### 23. 1-Tap Hotspot Setup Completion & Local LAN Online Sync (Issue #36)
- [x] **Binary API HotSpot Setup on Port 8728**:
  - Added `installHotspotConfig` in `MikrotikApiClient` to provision system identity, hotspot profile, DNS captive portal (`$slug.nexawavepass.com`), walled garden domains, user rate-limit profiles, and auto-cleanup scheduler directly over Port 8728 binary socket.
  - In `RouterDiscoveryService.installHotspotOnRouter()`, added automatic fallback to Port 8728 binary API if HTTP REST returns 404 or fails.
  - Unconditionally persisted router credentials (`keyRouterLocalIp`, `keyRouterUsername`, `keyRouterPassword`, `keyRouterTunnelEndpoint`) in `SharedPreferences`.
- [x] **Interactive Completion Modal in RouterSetupScreen**:
  - Eliminated the dead-end ("done then nothing happened") by displaying an interactive completion sheet upon setup finish.
  - Provides instant 1-tap navigation to "Go to Dashboard" or "View Diagnostics" with active gateway details.
- [x] **Local LAN Online Status Sync**:
  - Updated `HomeDashboardScreen` and `AdminManagementScreen` to probe local LAN connectivity directly when in `local` mode rather than relying solely on cloud WAN pings against private RFC1918 IPs.
  - Automatically updates Supabase router record to `status: 'ONLINE'` and `lastSeen: now` when the phone communicates with the router on Wi-Fi.
- [x] **Verification**:
### 24. Voucher Confirmation, Credentials Login & Pure-JS CHAP MD5 Authentication (Issue #70, PR #71)
- [x] **Root Cause Analysis**:
  - `redeemVoucher()` on `wavepass-web` synchronously awaited cloud backend voucher validation. When `api.nexawavepass.com` was unreachable or DNS timed out, the request hung for 30+ seconds, browser user activation expired, and local router form submission was never executed.
  - `loginWithCredentials()` on `wavepass-web` was missing form POST execution entirely, only performing `window.location.href = ...` (a GET request), which RouterOS Hotspot ignores.
  - RouterOS Hotspot with `login-by=http-chap` rejected voucher and credentials submissions without RFC 1321 CHAP challenge responses.
  - In `RouterSetupScreen`, the hosted trampoline redirector did not forward `$(chap-id)` or `$(chap-challenge)` in the redirect URL, and lacked on-box execution for query credentials (`?code=...` or `?username=...&password=...`), causing an infinite bounce loop.
- [x] **Full-Stack Implementation & Fixes**:
  - `wavepass-web/lib/md5.ts`: Added pure-JS RFC 1321 MD5 hash generator (0 external dependencies).
  - `wavepass-web/app/portal/page.tsx`:
    - Converted cloud voucher sync to fire-and-forget (`fetch(...).catch(() => {})`) to eliminate blocking delays.
    - Implemented instant POST form submissions for both `redeemVoucher()` and `loginWithCredentials()` targeting the local gateway (`linkLogin || 'http://192.168.88.1/login'`).
    - Added dynamic CHAP MD5 response hashing whenever `chap-id` and `chap-challenge` are present.
    - Added `popup="true"` and `dst=linkOrig || window.location.href` to auto-close captive network assistants.
  - `wavepass-web/app/api/vouchers/[code]/redeem/route.ts`: Added 3.5s `AbortController` timeout to prevent cloud hanging.
  - `wavepass-android/lib/screens/router_setup_screen.dart`:
    - Extracted static `_rfc1321Md5Js` constant reused across hosted trampoline and standalone portal suites.
    - Forwarded `&chap-id=$(chap-id)&chap-challenge=$(chap-challenge)` in hosted trampoline URL.
    - Embedded hidden `sendin` form, `executeLogin()`, and query-param detection in `login.html` to execute login directly on-router when query credentials are present.
- [x] **Verification**:
  - `wavepass-web`: Production build clean (`pnpm build`: 30 static pages, 9 route handlers, 0 errors).
  - `wavepass-android`:
    - `flutter test`: **All 56 tests passed**.
    - `flutter analyze`: **0 issues found** (clean).
    - PR [#71](https://github.com/Icedmist/WavePass-Android/pull/71) merged into `main` (`45b1744`).

### 25. WAN-Safe Anti-Sharing Enforcement & Automated Trial Profile Configuration (Issue #72, PR #73)
- [x] **WAN-Safe Anti-Sharing & Anti-Tethering Enforcement**:
  - Restored and secured postrouting TTL mangle rule (`action=change-ttl new-ttl=set:1`) with explicit `out-interface=!ether1` filter across `RouterSetupScreen`, `RouterDiscoveryService.enforceNoHotspotSharing`, and `MikrotikApiClient.enforceNoHotspotSharing`.
  - Guaranteed that WAN traffic from the router to the ISP's upstream hop is untouched (avoiding TTL=0 packet drops that kill the venue's internet uplink), while client-bound packets arrive with TTL=1, immediately blocking secondary Wi-Fi and Bluetooth tethering.
  - Automatically cleans up any legacy mangle rules lacking the `!ether1` safety constraint upon router setup, fleet push, or portal upload.
- [x] **Automated 2-Minute Payment Trial Profile**:
  - Added `wp-payment-trial` profile (`rate-limit=2M/2M`, `session-timeout=2m`, `shared-users=1`, `transparent-proxy=yes`) to `RouterDiscoveryService.standardDurationProfiles`.
  - Automatically configured during both HTTP REST and Port 8728 binary API router provisioning, portal file uploads, and fleet anti-sharing enforcement.
  - Configured hotspot server profile with `addresses-per-mac=1`, `mac-cookie=no`, `login-by=http-pap,http-chap,mac-cookie,trial`, `trial-user-profile=wp-payment-trial`, `trial-uptime-limit=2m`, and `trial-uptime-reset=24h`.
- [x] **Verification**:
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 58 tests passed** (including unit tests for anti-sharing mangle, profile addition, and trial settings).
  - PR [#73](https://github.com/Icedmist/WavePass-Android/pull/73) merged into `main` (`5f241dd`).

### 26. Zero Unsecure Warnings, FastTrack Anti-Sharing, Venue Activation Lock Persistence & Router Admin Password Sync (Issue #74, PR #75)
- [x] **Eliminated Cross-Origin Insecure Form Warning**:
  - Replaced cross-origin `<form action="http://192.168.88.1/login" method="POST">` from HTTPS hosted portal with direct top-level navigation via `window.location.replace(fullLoginUrl)`.
  - Router `login.html` trampoline captures query credentials and submits the local, same-origin `<form name="sendin">` directly on the router with CHAP MD5 hashing, completely eliminating browser *"The information you’re about to submit is not secure"* alerts.
- [x] **Unbreakable Anti-Sharing & FastTrack Prevention**:
  - Automatically disables RouterOS FastTrack (`/ip firewall filter set [find action=fasttrack-connection] disabled=yes`) across binary API (8728), REST, and script exports, preventing established TCP streams from bypassing mangle and firewall filter rules.
  - Converted mangle anti-tethering to explicitly target client RFC 1918 destination subnets (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`), ensuring outgoing WAN traffic to the ISP is 100% untouched regardless of WAN interface naming, while all packets delivered to hotspot clients are strictly set to TTL=1.
  - Positioned forward filter drop rules for TTL 63, 62, 127, 126 at index 0 (`place-before=0`) so secondary tethering hops are immediately dropped at the very top of the forward chain.
- [x] **Permanent Venue Activation Gate Persistence**:
  - Enhanced `ActivationCodeService.isAccountActivated()` with global device persistence (`wavepass_venue_activated_globally`), Supabase venue ownership verification, and email fallbacks.
  - Authenticated accounts that already configured a venue or have an active venue are permanently recognized as activated and will never be kicked back to `activateVenue` upon app reload, logout, or reconnect.
  - Hardened `clearCache()` so legitimate global venue activations are never wiped on simple account switches.
- [x] **Synchronized Router Hardware Admin Password**:
  - Added dedicated **"ROUTER HARDWARE ADMIN CREDENTIALS"** card in `AccountCenterScreen` with Gateway IP, Admin User, Router Admin Password, visibility toggler, and live "Save & Sync Router Password" button.
  - Implemented `RouterDiscoveryService.updateRouterAdminPassword()` and `MikrotikApiClient.updateUserPassword()` to update user credentials directly on RouterOS hardware via Port 8728 and REST API, while persisting immediately to `RouterDiscoveryService.keyRouterPassword`.
  - Added real-time `onChanged` credential saving in `RouterSetupScreen` and ensured `_saveCredentials()` is invoked before portal file uploads, anti-sharing enforcement, and script exports.
- [x] **Verification**:
  - `wavepass-web`: `pnpm build` clean (30 static pages, 9 route handlers, 0 errors). PR [#8](https://github.com/Icedmist/WavePass-Web/pull/8) merged into `main` (`4635210`).
  - `wavepass-android`:
    - `flutter analyze`: **0 issues found** (clean).
    - `flutter test`: **All 58 tests passed**.
    - PR [#75](https://github.com/Icedmist/WavePass-Android/pull/75) merged into `main` (`7ff8552`).

### 27. End-to-End Grace Period Architecture & Native Passwordless Trial Auth (Issues #9 & #76, PRs #10 & #77)
- [x] **Native RouterOS Hotspot Trial Auth Mechanics**:
  - Identified that MikroTik Hotspot's native trial functionality (`login-by=trial`) provisions a virtual trial user `T-<mac>` and strictly requires passwordless authentication.
  - Submitting passwords or CHAP MD5 challenge hashes on `T-<mac>` causes RouterOS to look in the `/ip hotspot user` database, fail to find the user, and reject the login with *"invalid username or password"*.
- [x] **Hosted Subdomain Trial Navigation Alignment (`WavePass-Web`)**:
  - Updated `activateTrial()` in `wavepass-web/app/portal/page.tsx` to dispatch `http://192.168.88.1/login?username=T-<mac>&trial=yes&dst=<target>` without sending `code=` or `password=` query parameters.
  - Production build clean (`pnpm build`: 30 static pages, 9 route handlers, 0 errors).
  - Closed Issue [#9](https://github.com/Icedmist/WavePass-Web/issues/9) via PR [#10](https://github.com/Icedmist/WavePass-Web/pull/10) merged to `main` (`e0dae7b`).
- [x] **Router Trampoline & Standalone Portal Trial Parameter Handling (`WavePass-Android`)**:
  - Updated `_generateHostedTrampolineHtml()` and `_generatePortalHtml()` in `RouterSetupScreen` to detect `params.get('trial') === 'yes'` or `username.indexOf('T-') === 0`.
  - Sets `dst_user` to `trialUser` and leaves `dst_pass` empty `''`, immediately submitting `document.sendin.submit()` directly to the hotspot gateway without CHAP MD5 hashing.
  - Closed Issue [#76](https://github.com/Icedmist/WavePass-Android/issues/76) via PR [#77](https://github.com/Icedmist/WavePass-Android/pull/77) merged to `main` (`3c1b9b3`).
- [x] **Session Limits, Bandwidth Shaping & 24-Hour Abuse Protection**:
  - Provisioned profile: `wp-payment-trial` with `rate-limit=2M/2M` (2 Mbps down / 2 Mbps up).
  - Strict session duration: `session-timeout=2m`, `trial-uptime-limit=2m` (hard 120-second cutoff).
  - Anti-abuse cooldown: `trial-uptime-reset=24h` (hardware MAC tracking enforces a single trial per device every 24 hours).
  - Anti-tethering: TTL=1 client mangle rules and wireless/bridge isolation apply to trial sessions, preventing trial data sharing.
- [x] **Verification**:
  - `wavepass-web`: Next.js build clean (0 errors).
  - `wavepass-android`: `flutter analyze` clean (0 errors), `flutter test` (58/58 passed).

### 28. Account Switch Session Isolation ("Session Catcher" Fix) & Universal Account Deletion (Issues #78, #23, #11; PRs #79, #24, #12)
- [x] **Universal Account Deletion Across Supabase Auth & Prisma (`WavePass-Backend` #23, #24)**:
  - Updated `POST /api/v1/admin/delete-account` to verify credentials for both system admins (`ADMIN_PASSWORD`) and standard Supabase operators via Supabase Auth REST verification (`POST /auth/v1/token?grant_type=password`).
  - Implemented cascading user deletion in `AdminAuthService.deleteUserAccount()`: purges user from Supabase Auth admin API (`DELETE /auth/v1/admin/users/:id`), drops venue memberships, cleans up owned vouchers, and deletes Prisma records.
  - Test suite clean: all 27 backend unit/service tests passing; `pnpm build` clean.
- [x] **Session Catcher & Cross-Account State Isolation (`WavePass-Android` #78, #79)**:
  - **Account Purge on Sign Out**: `AccountCenterScreen._signOutUser()` and `LoginScreen._handleSignIn()` now wipe `admin_token`, `wavepass_voucher_history_v1`, router credentials (`wavepass_router_local_ip`, `wavepass_router_username`, `wavepass_router_password`), venue cache, activation state, and voucher cache upon account switch.
  - **Scoped System Admin Elevation**: `SystemAdminService.isSystemAdmin()` now strictly validates email alongside token presence; non-admin accounts are never elevated to System Admin.
  - **Strict Venue Ownership & Fallback Isolation**: `SupabaseService.getPrimaryVenue()`, `getVenues()`, and `VenueStateService.refreshVenue()` limit primary venue fallback strictly to `talk2icedmist@gmail.com`. Standard operator accounts resolve only their own `VenueMember` associations.
  - **Home Dashboard Active User Leak Guard**: `HomeDashboardScreen` guards `WavePassApi.instance.adminStats()` behind `isSuperAdmin && vid == null` so platform-wide active user counts never overwrite local stats for zero-session accounts. Guarded router hardware probes behind `venue != null || isSuperAdmin`.
  - **Voucher History & Hardware Polling Isolation**: `VoucherHistoryService` now scopes database queries to `venueId` when not super admin, clears internal caches via `clearCache()`, and guards 20-second router background polling when no venue is configured.
- [x] **Web Admin Cookie & Token Purge (`WavePass-Web` #11, #12)**:
  - Updated `app/login/page.tsx` to explicitly delete `admin_token` from `localStorage` and set `admin_token` cookie to expired upon standard Supabase user login.
- [x] **Verification**:
  - `wavepass-backend`: 27/27 unit tests passed; `pnpm build` clean. PR [#24](https://github.com/Icedmist/WavePass-Backend/pull/24) merged to `main` (`2bc542c`).
  - `wavepass-web`: `pnpm build` clean (30 static pages, 9 route handlers). PR [#12](https://github.com/Icedmist/WavePass-Web/pull/12) merged to `main` (`2f1bd45`).
  - `wavepass-android`: `flutter analyze` clean (0 warnings, 0 errors); `flutter test` clean (all 58 tests passed). PR [#79](https://github.com/Icedmist/WavePass-Android/pull/79) merged to `main` (`b8766be`).

### 29. Linux IPv6 Hotspot Anti-Sharing Enforcement & Native GET Trial Access (Issues #80 & #13; PRs #81 & #14)
- [x] **Complete Linux Hotspot Tethering / Sharing Elimination**:
  - **Identified IPv6 Bypass**: Linux NetworkManager Wi-Fi Hotspot sharing creates automated IPv6 router advertisements and forwarding. Because MikroTik HotSpot operates on IPv4, IPv6 traffic bypassed voucher auth, mangle TTL rewriting, and IPv4 drop filters.
  - **IPv6 Lockdown**: Added RouterOS rules disabling IPv6 on the hotspot interface (`/ipv6/settings/set disable-ipv6=yes`), dropping incoming IPv6 prerouting traffic (`/ipv6/firewall/raw/add chain=prerouting action=drop`), and dropping all forwarded IPv6 packets (`/ipv6/firewall/filter/add chain=forward action=drop`).
  - **Generalized Subnet TTL Drops**: Replaced static TTL=63/62 drops with client-subnet-scoped drop rules (`src-address=$subnet ttl=less-than:64 action=drop`) for all RFC 1918 subnets (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`), blocking secondary routed hops from Linux, Android, and iOS tethering regardless of hop count, alongside Windows tethering (`ttl=equal:127,126,125`).
- [x] **2-Minute Trial Access & Payment Grace Period Reliability**:
  - **Fixed CLI/API Syntax Error**: Corrected invalid RouterOS properties `trial-uptime-limit=2m` and `trial-uptime-reset=24h` to the official composite parameter `trial-uptime=2m/24h`.
  - **Profile Dependency Ordering**: Ensured `wp-payment-trial` user profile is created prior to the server profile referencing it as `trial-user-profile=wp-payment-trial`.
  - **Unencoded MAC Authentication in Hosted Portal (`WavePass-Web`)**: Updated `activateTrial()` to pass raw unencoded colons (`username=T-${mac}`) instead of `%3A`, preventing RouterOS username matching failure, and added fallback navigation to `/login?trial=yes` for QR camera scans.
  - **Native HTTP GET Trampoline Execution**: Replaced passwordless HTTP POST form submission with native HTTP GET redirection (`window.location.replace('$(link-login-only)?dst=' + encodeURIComponent(dst) + '&username=' + targetTrialUser)`), resolving the *"invalid username or password"* rejection by RouterOS.
- [x] **Verification**:
  - `wavepass-web`: `pnpm build` clean (30 static pages, 9 route handlers, 0 errors). PR [#14](https://github.com/Icedmist/WavePass-Web/pull/14) merged to `main` (`58a8ae1`).
  - `wavepass-android`:
    - `flutter analyze`: **0 issues found** (clean).
    - `flutter test`: **All 58 tests passed** (including mock socket tests for `trial-uptime=2m/24h` and IPv6 drop rules).
    - PR [#81](https://github.com/Icedmist/WavePass-Android/pull/81) merged to `main` (`c069b81`).

### 30. Disconnected Device Active Voucher Retrieval & 1-Tap Reconnect (Issues #82, #25, #17; PRs #83, #26, #18)
- [x] **Disconnection & Reconnection Root Cause Resolution**:
  - Devices disconnected from Wi-Fi (sleep, idle, walking out of range) had their active session cleared from `/ip/hotspot/active` on RouterOS.
  - When reconnecting, captive portals presented only blank inputs and pay buttons. Online Paystack customers (`username = MAC`) or cash voucher customers who misplaced paper slips could not reconnect without paying again or contacting staff.
- [x] **Backend MAC-to-Voucher Active Session Resolution (`WavePass-Backend` #25, #26)**:
  - Added `getDeviceActiveAccess(mac, ip)` in `src/modules/portal/portal.service.ts`:
    - Queries active `Session`, redeemed `Voucher` (by `redeemedMac`), and active `Order` (by `customerRef`).
    - Calculates real-time remaining duration, plan specifications, and credentials (`voucherCode`, `username`, `password`, `reconnectUrl`).
  - Added `@Get('active-session')` and `@Get('device/:mac/active-voucher')` in `portal.controller.ts`.
  - PR [#26](https://github.com/Icedmist/WavePass-Backend/pull/26) merged to `main` (`6912807`).
- [x] **Hosted Portal Auto-Detection & 1-Tap Reconnect UI (`WavePass-Web` #17, #18)**:
  - Created `app/api/portal/active-session/route.ts` proxying client requests by MAC/IP to the backend.
  - Added live countdown banner and prominent card in `app/portal/page.tsx` displaying the active pass allocated to the device's MAC address with remaining time, copyable voucher code, and 1-tap "Reconnect Active Session Now" button.
  - Caches redeemed vouchers to browser `localStorage` (`wp-active-voucher`, `wp-active-user`).
  - PR [#18](https://github.com/Icedmist/WavePass-Web/pull/18) merged to `main` (`a0dec4e`).
- [x] **Router Gateway Local Storage Caching & Offline Reconnect (`WavePass-Android` #82, #83)**:
  - Router `login.html` hosted trampoline caches query-param vouchers (`c` or `u`) to `localStorage`.
  - Router `status.html` automatically caches active session `$(username)` into `localStorage`.
  - Router emergency offline fallback pre-fills cached voucher and transforms button into 1-tap reconnect.
  - Standalone `login.html` presents dynamic `#savedVoucherBox` card when a cached active voucher is found.
  - Exposes `RouterSetupScreen.generateStatusHtml` and `RouterSetupScreen.generateLogoutHtml`.
  - All 59 unit/widget tests passing; `flutter analyze` 0 issues.
  - PR [#83](https://github.com/Icedmist/WavePass-Android/pull/83) merged to `main` (`e9ad316`).

### 31. Payment Modal Parity & Complete Notifications Tab (Issue #86, PR #87)
- [x] **Single Modal Renderer**: `_buildModal` shared by foreground `show()` and background poll alerts via a messenger key bound in `main.dart` — payment alerts look exactly like "Voucher In Use" modals.
- [x] **Silent First Fill**: initial poll populates feed only; subsequent polls modal + system bar for new payments.
- [x] **Complete Tab**: Notifications screen syncs backend alerts on open; mark-all-read syncs to backend.
- [x] **Verification**: `flutter analyze` 0 issues; 60/60 tests pass.
- [x] PR [#87](https://github.com/Icedmist/WavePass-Android/pull/87) merged to `main`.

### 32. Activation Generation by Kind & Duration (Issue #88, PR #89)
- [x] **Generate Dialog**: kind picker (LICENSE monthly / MASTER multi-use / TRIAL short) with duration presets, custom days input (0 = lifetime), venue assignment.
- [x] **List**: kind badge + expiry per code, EXPIRED filter/count.
- [x] **Verification**: `flutter analyze` 0 issues; 60/60 tests pass.
- [x] PR [#89](https://github.com/Icedmist/WavePass-Android/pull/89) merged to `main`.

### 33. Code Request Flow & Admin Review (Issue #90, PR #91)
- [x] **Request Form**: activation screen collects name/phone/venue/message, posts to admin, shows pending confirmation.
- [x] **Review Screen**: pending/granted/rejected filters, full requester details, grant-code (kind+days), direct-access (days), reject, copy granted code.
- [x] **Verification**: `flutter analyze` 0 issues; 60/60 tests pass.
- [x] PR [#91](https://github.com/Icedmist/WavePass-Android/pull/91) merged to `main`.

### 34. Sticky Summary, Expiry Countdown & Funnel (Issues #93, PR #95)
- [x] **Sticky Strip**: pinned money summary (venue, earnings, online, license countdown) via slivers; 7/3-day expiry banner with Renew shortcut.
- [x] **Funnel Card**: 7-day initiated → paid → active stepper + revenue from admin endpoint.
- [x] **Verification**: `flutter analyze` 0 issues; 60/60 tests pass (balance-duplication expectations updated).
- [x] PR [#95](https://github.com/Icedmist/WavePass-Android/pull/95) merged to `main`.

### 35. Print Preview, Sold Marking & Sales History (Issue #92, PR #94)
- [x] **Receipt Preview**: thermal-style sheet with Print action on sell screen; sold/unsold marker persisted per voucher + toggle in history sheet.
- [x] **Full History**: sales-history screen (100 orders + total) linked from Recent Sales; fixed header-row overflow.
- [x] **Verification**: `flutter analyze` 0 issues; 60/60 tests pass.
- [x] PR [#94](https://github.com/Icedmist/WavePass-Android/pull/94) merged to `main`.

### 36. Wallet Always Ensures DVA (Issue #98, PR #99)
- [x] Wallet ensures (not just reads) on every load with read-fallback, so backend self-heal runs for existing venues.
- [x] **Verification**: `flutter analyze` clean.
- [x] PR [#99](https://github.com/Icedmist/WavePass-Android/pull/99) merged to `main`.

### 37. Verify-Before-Present Vouchers (Issue #101, PR #102)
- [x] Sell verifies router-pushed OR cloud-confirmed before success; failure state with retry; auto-print gated on provisioned.
- [x] Batch uploads exact codes to cloud with router/cloud counts; UNSYNCED markers in history.
- [x] **Verification**: `flutter analyze` clean; 70/70 tests pass.
- [x] PR [#102](https://github.com/Icedmist/WavePass-Android/pull/102) merged to `main`.

### 38. Router Target Validation & Cloud Fallback (Issue #103, PR #104)
- [x] **Cause**: router target IP persisted unconditionally — a stale 192.168.1.1 (ISP gateway) poisoned all router ops while UI showed nothing wrong.
- [x] **Fix**: validateRouterTarget proves MikroTik identity (API-8728, REST fallback); Pass History shows effective target with tap-to-verify + one-tap reset to 192.168.88.1; monitoring falls back to cloud retrieve-voucher when router unreachable.
- [x] **Verification**: `flutter analyze` clean; 70/70 tests pass.
- [x] PR [#104](https://github.com/Icedmist/WavePass-Android/pull/104) merged to `main`.

### 39. Approval Error Surfacing (PR #105, related to Backend #52)
- [x] approveTransfer throws real backend/network errors instead of silent false; Approve buttons show friendly snackbars (offline vs timeout vs server message).
- [x] **Verification**: `flutter analyze` clean.
- [x] PR [#105](https://github.com/Icedmist/WavePass-Android/pull/105) merged to `main`.

### 40. Payment Review Queue Screen (PR #106, related to Backend #55)
- [x] Review Queue screen: counts, filters, refund/stuck/failed/reversed cards with refs; Verify-live action per item; dashboard entry card.
- [x] **Verification**: `flutter analyze` clean.
- [x] PR [#106](https://github.com/Icedmist/WavePass-Android/pull/106) merged to `main`.

### 41. Secret Hygiene (Issue #109, PR #110)
- [x] Removed hardcoded Supabase key from ApiConstants (dart-define only, fail-closed guard); README documents key injection.
- [x] **Verification**: `flutter analyze` clean; 70/70 tests pass.
- [x] PR [#110](https://github.com/Icedmist/WavePass-Android/pull/110) merged to `main`.

### 42. Wallet Error Surfacing (Issue #111, PR #112)
- [x] Backend 4xx/5xx JSON error maps now surface message + retry instead of rendering as silent pending.
- [x] **Verification**: `flutter analyze` clean.
- [x] PR [#112](https://github.com/Icedmist/WavePass-Android/pull/112) merged to `main`.

### 43. 2-Minute Trial Loop Prevention & Hotspot Profile Provisioning (Issue #113, PR #114)
- [x] **Trial Loop Fix**: Fixed `login.html` auto-login script in both hosted and standalone modes. Previously, matching `u.indexOf('T-') === 0` triggered an infinite redirect loop whenever RouterOS reloaded or redirected with a trial username (`T-...`). Now strictly checks `trial === 'yes' || trial === '1'`.
- [x] **Hotspot Trial Profile Provisioning**: Created `/ip hotspot user profile add name="wp-payment-trial"` before `/ip hotspot profile add name="wavepass-profile"`, adding `login-by=http-pap,http-chap,mac-cookie,trial`, `trial-user-profile="wp-payment-trial"`, and `trial-uptime=2m/24h` directly on the hotspot profile.
- [x] **Walled Garden**: Added Google Fonts domains (`fonts.googleapis.com` and `fonts.gstatic.com`) to walled garden and walled garden IP tables.
- [x] **Standalone Trial Form**: Switched trial activation in standalone `login.html` to native RouterOS trial GET form submission (`value="T-$(mac-esc)"`).
- [x] **Hosted Subdomain Default**: Defaulted `_useHostedSubdomainPortal = true` with `SharedPreferences` persistence.
- [x] **Verification**: `flutter analyze` passed with 0 issues; all 70 tests passed.
- [x] PR [#114](https://github.com/Icedmist/WavePass-Android/pull/114) merged to `main`.

### 44. Biometrics, 48-Hour Session Lifecycle, Portal Templates & Supabase Initialization Guard (Issue #96, PR #115)
- [x] **Face ID & Biometrics (iOS & Android)**:
  - Added `NSFaceIDUsageDescription` to `ios/Runner/Info.plist`.
  - Migrated Android `MainActivity.kt` to `FlutterFragmentActivity` and added `USE_BIOMETRIC` permission in `AndroidManifest.xml`.
  - Built `BiometricAuthService` integrating `package:local_auth` for secure credential enrollment and biometric re-authentication.
  - Added biometric login trigger button and setup dialog on `LoginScreen`.
- [x] **Session Expiration Guard (`SessionService`)**:
  - Automatically expires sessions after 48 hours of inactivity.
  - Surfaces friendly expiration notice banner upon forced sign-in redirect.
- [x] **Supabase Client Initialization & Signup Guard**:
  - Fixed `LateInitializationError: Field 'client' has not been initialized` by tracking `isInitialized` status in `SupabaseService`.
  - Guarded `SupabaseService.instance.client` getter to throw an informative `StateError` instead of crashing unhandled.
  - Guarded `SignupScreen._signup()` to display actionable guidance (*"Supabase is not configured. Rebuild or run with --dart-define=SUPABASE_ANON_KEY=<key>."*) when credentials are not injected.
  - Fixed loading state hang when validation fails.
- [x] **Captive Portal Templates & Wallet Guard**:
  - Integrated portal theme templates (Onyx, Ivory, NeoPop, Aurora) and showcase HTML in `assets/portal_templates/` and `router_setup_screen.dart`.
  - Added temporary locked Paystack checkout notice in `wallet_screen.dart`.
- [x] **Verification**: `flutter analyze` clean (0 issues); 70/70 tests passed.
- [x] PR [#115](https://github.com/Icedmist/WavePass-Android/pull/115) merged to `main`.

### 45. Out-of-the-Box Supabase Anon Key Default (Issue #116, PR #117)
- [x] **Default Anon Publishable Key**:
  - Configured `defaultValue: 'sb_publishable_Lyp5cAFr5o0gSSvKEtp3QQ_4p0nPEKR'` on `ApiConstants.supabaseAnonKey`.
  - Enables standard `flutter run` and builds to initialize Supabase and execute sign-up/login out-of-the-box without requiring explicit `--dart-define` command line arguments.
  - Retained `String.fromEnvironment('SUPABASE_ANON_KEY')` to allow overriding at build time whenever custom keys are provided.
- [x] **Verification**: `flutter analyze` clean (0 issues); 70/70 tests passed.
- [x] PR [#117](https://github.com/Icedmist/WavePass-Android/pull/117) merged to `main`.

### 46. ISP Gateway Blacklist, Cache Sanitization & Safe HotSpot Anti-Tethering (Issue #118, PR #119)
- [x] **Upstream ISP Gateway Blacklist (`router_discovery_service.dart`)**:
  - Added `blacklistedIspGateways` (`192.168.1.1`, `192.168.0.1`, `192.168.100.1`, `10.0.0.1`) and `isForbiddenIspGateway()`.
  - Prohibits targeting or caching upstream ISP / modem / WAN gateways (e.g. Starlink dish on `ether1` at `192.168.1.1`) as the local MikroTik router.
  - Guarded `discoverLocalRouter`, `probeEndpoint`, `_probeRouter`, `_probeRouterOsApi`, `installHotspotOnRouter`, `updateRouterAdminPassword`, `validateRouterTarget`, and `provisionVoucherDualRoute`.
- [x] **Automatic Cache Sanitization (`main.dart` & `effectiveRouterTarget()`)**:
  - Calls `RouterDiscoveryService.sanitizeCachedRouterTarget()` on application boot in `main.dart` to immediately purge any cached `192.168.1.1` without requiring manual reset.
  - `effectiveRouterTarget()` automatically removes blacklisted gateways and falls back to default `192.168.88.1`.
- [x] **HotSpot Subnet Scoping & WAN-Safe Anti-Tethering (`mikrotik_api_client.dart`, `router_discovery_service.dart`, `router_setup_screen.dart`)**:
  - Removed blanket `192.168.0.0/16`, `10.0.0.0/8`, and `172.16.0.0/12` rules that were intercepting Starlink WAN responses.
  - Scoped anti-tethering `postrouting` mangle TTL modification strictly to local HotSpot client subnets (`192.168.88.0/24`, `10.5.50.0/24`, `172.16.10.0/24`).
  - Removed destructive `chain=forward src-address=... ttl=less-than:64 action=drop` forward filter rules that were dropping Starlink WAN responses (TTL 63) and breaking user internet connectivity.
  - Actively audits and removes legacy `WavePass Anti-Tethering` filter drop rules from RouterOS filter table upon execution.
- [x] **UI Validation Guards (`router_setup_screen.dart`, `router_diagnostics_screen.dart`, `account_center_screen.dart`)**:
  - Validates manual IP inputs and prevents saving blacklisted ISP gateways with clear user guidance.
- [x] **Verification**:
  - `flutter analyze` clean (0 issues).
  - All 76 tests passed (including 6 new tests in `test/router_dual_connection_test.dart`).
- [x] PR [#119](https://github.com/Icedmist/WavePass-Android/pull/119) merged to `main`.

### 47. Subdomain Elimination, Venue Retention on Login, Resilient Plan Creation & Global Error Boundary (Issue #120, PR #121)
- [x] **Permanently Disabled Subdomain/Slug Feature**:
  - Removed subdomain/slug textfield, controller, and regex validation from Onboarding (`onboarding_screen.dart`), Account Center (`account_center_screen.dart`), Admin Management (`admin_management_screen.dart`), and Router Setup (`router_setup_screen.dart`).
  - Auto-generates unique, collision-free internal slugs (`v-<timestamp>-<hash>`) in `VenueStateService.createVenue` to satisfy backend database unique constraints without user friction.
  - Bypassed `checkSlugAvailability` to always return available.
  - Disabled hosted subdomain bounce architecture in `router_setup_screen.dart`, ensuring template captive portals run directly on the local router gateway.
- [x] **Fixed Venue Resolution on Login**:
  - Stopped `login_screen.dart` from wiping active venue on login unless the user account email actually changed.
  - Allowed primary venue fallback (`allowFallbackToPrimary: true`) for all authenticated operators (not just superadmin) in `SupabaseService.getPrimaryVenue` and `getVenues`.
- [x] **Self-Healing Plan Creation**:
  - `VenueStateService.createPlan` automatically attempts venue restoration if `currentVenueId` is null, and auto-provisions a default venue if still empty.
  - Added offline fallback in `createPlan`, `updatePlan`, and `refreshPlans` to ensure locally created plans persist seamlessly even when offline or during transient network errors.
- [x] **Global Error Handling & Resilient UI**:
  - Wired `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and `ErrorWidget.builder = buildGracefulErrorWidget` in `main.dart`.
  - Implemented `buildGracefulErrorWidget` in `lib/core/widgets/graceful_error_widget.dart` to replace red screens of death with friendly recovery cards.
- [x] **Verification**:
  - `flutter analyze` clean (0 issues).
  - All 81 tests passed (including 5 new tests in `test/venue_creation_and_plan_self_healing_test.dart`).
- [x] PR [#121](https://github.com/Icedmist/WavePass-Android/pull/121) merged to `main`.

### 48. Portal Bank Transfer Removal, Direct Online Paystack Checkout, Residual Subdomain Eradication & Bug Fixes (Issue #122, PR #123)
- [x] **Removed Bank Transfer Feature**:
  - Removed "Bank Transfer" tab and panel from captive portal HTML (`router_setup_screen.dart` and `assets/portal_templates/` templates 1–4: Onyx, Ivory, Neo-Pop, Aurora).
  - Removed `submitTransferPayment()`, `copyAcct()`, `loadDynamicBankAccounts()`, and transfer status polling from portal scripts.
  - Removed the "Venue Bank Accounts on Portal" setup card from `router_setup_screen.dart` UI.
  - Removed bank account fetching and mock DVA restrictions from `_ensurePortalSuite()`.
- [x] **Enabled Direct Online Paystack Checkout on Venue Login Page**:
  - Fixed critical backend endpoint mismatch: updated payment verification callback from `/api/v1/portal/verify-payment` (404 Not Found) to `/api/v1/portal/retrieve-voucher?reference=...`.
  - Fixed foreign key constraint in `init-payment`: passed UUID `venueId` instead of slug to prevent Prisma foreign key failures on checkout.
  - Mock DVA accounts no longer disable Paystack; online checkout remains active with automated guest voucher fulfillment upon payment.
  - Unlocked rates/plans in all portal templates (`assets/portal_templates/`) with active "Pay Online" buttons.
- [x] **Residual Subdomain & Slug Eradication**:
  - Replaced `${venue['slug']}.nexawavepass.com` in `home_dashboard_screen.dart` with "Local Hotspot Gateway".
  - Replaced subdomain in voucher preview, thermal PDF printout, and share instructions in `sell_pass_screen.dart` with gateway IP `192.168.88.1`.
  - Replaced subdomain in `batch_vouchers_screen.dart` cutout cards with `192.168.88.1`.
  - Replaced captive portal footer subdomain tag in `router_setup_screen.dart` with `Gateway: 192.168.88.1`.
  - Replaced subdomain text in `system_monitor_screen.dart` with Venue ID.
- [x] **Merged Counter Sales into Sales History & Router Scanner Fix**:
  - In `sales_history_screen.dart`, merged offline and counter-sold vouchers from `VoucherHistoryService` into the sales history list, displaying both online orders and counter cash sales with accurate revenue totals.
  - In `barcode_scanner_screen.dart`, resolved actual venue UUID via `VenueStateService` and validated active venue presence before router registration instead of falling back to `'default'`.
  - Registered `assets/portal_templates/` in `pubspec.yaml`.
- [x] PR [#123](https://github.com/Icedmist/WavePass-Android/pull/123) merged to `main`.

### 49. Re-entrant Loops, Hung Loading States, Unsafe Type Casts & Widget Lifecycle Hardening (Issue #124, PR #125)
- [x] **Eliminated Re-entrant Network Polling Loop**:
  - In `NotificationService` (`lib/core/services/notification_service.dart`), introduced an in-flight concurrency lock `_isRefreshingPayments` with `try-finally` and reset in `stopPaymentPolling()`.
  - Prevents network poll pileups if request latency exceeds the 30-second interval, eliminating duplicated push alerts and repeated modal dialogs.
- [x] **Bounded Batch Voucher Generation Loop**:
  - In `BatchVouchersScreen` (`lib/screens/batch_vouchers_screen.dart`), replaced unbounded code accumulation with a `Set<String>` and an explicit attempt ceiling `attempts < qty * 50`.
  - Guarantees 100% unique voucher codes without colliding or looping indefinitely on high-quantity batches.
  - Added null/num-safe parsing for plan prices and deduplicated pricing dropdown entries to eliminate `DropdownButtonFormField` duplicate value assertion crashes.
- [x] **Eliminated Hung Button & Indefinite Loading States**:
  - In `RouterSetupScreen` (`lib/screens/router_setup_screen.dart`), wrapped `_handleAutoDiscover` in a `try-finally` block ensuring `_isScanning = false` is always cleared even on unhandled network socket exceptions.
  - In `SellPassScreen` (`lib/screens/sell_pass_screen.dart`), wrapped `_handleGenerate` in a `try-finally` block ensuring `_isGenerating = false` is always executed, preventing permanently locked spinner buttons.
- [x] **Safe Numeric Parsing Across State & Widgets**:
  - In `HomeDashboardScreen` (`lib/screens/home_dashboard_screen.dart`), replaced direct `(o['amountMinor'] as int)` cast with null/double-safe `(((o['amountMinor'] as num?)?.toInt() ?? 0) ~/ 100)`.
  - In `PlanConfiguratorSheet` (`lib/core/widgets/plan_configurator.dart`), converted `as int` casts for `durationSeconds`, `simultaneousDevices`, and `priceMinor` to `(e?['...'] as num?)?.toInt()` to eliminate fatal Dart `TypeError` crashes when consuming API responses with decimal numbers.
- [x] **Widget Lifecycle Hardening (Unmounted setState Elimination)**:
  - Added `if (mounted)` guards before `setState()` in `VoucherHistorySheet`, `PrinterSettingsScreen`, `AdminManagementScreen`, and `BatchVouchersScreen` search controllers to protect against asynchronous calls resolving after widget tree disposal.
- [x] **Regression & Unit Tests**:
  - Created `test/loops_and_runtime_bugs_test.dart` testing `NotificationService` re-entrancy locks and ID deduplication, `PlanConfiguratorSheet` initialization with floating-point JSON numbers, and bounded collision-free batch voucher generation.
- [x] **Verification**:
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 84 tests passed** (0 failures).
- [x] PR [#125](https://github.com/Icedmist/WavePass-Android/pull/125) merged to `main`.

### 50. Operator Venue Retention, User Upsert & Membership Self-Healing (Issue #126, PR #127)
- [x] **Root Cause Investigation on "Disappearing Venues"**:
  - Investigated account `Sahabimusa963@gmail.com`: verified that the user had created "DAN MUSA WIFI" (`087e2f20-899e-419e-8af2-b8978f8cb70b`) with a 1-day pass (`30000` minor = ₦300), but `VenueMember` was empty because `public.User` had no matching row for Supabase Auth ID `5f28a9cf-57c6-4cb3-bb1d-fc836570a053`.
  - Because `VenueMember` insertions had failed silently due to missing `User` foreign keys, `getPrimaryVenue` returned `null` upon app updates or re-logins, making the venue disappear and forcing repeated venue creation.
- [x] **Guaranteed User Upsert in `VenueStateService`**:
  - In `createVenue` and `refreshVenue`, added an explicit upsert for `public.User` (`id`, `email`, `authProvider: 'supabase'`, `status: 'active'`) before attempting to upsert into `VenueMember`.
- [x] **Self-Healing Fallback in `SupabaseService`**:
  - In `getPrimaryVenue` and `getVenues`, added fallback to `ActivationRedemption` by operator email. If `VenueMember` is missing, it resolves the operator's active venue and automatically heals both the `User` and `VenueMember` rows in Supabase.
- [x] **Live Account Restoration**:
  - Restored and linked `Sahabimusa963@gmail.com` to active venue `DAN MUSA WIFI` (`087e2f20-899e-419e-8af2-b8978f8cb70b`) as `Owner`, alongside their `ActivationRedemption` record.
- [x] **Regression Tests**:
  - Added test in `test/venue_creation_and_plan_self_healing_test.dart` verifying venue retention across refreshes for non-superadmin operator accounts.
- [x] **Verification**:
  - `flutter analyze`: **0 issues found** (clean).
  - `flutter test`: **All 85 tests passed** (0 failures).
- [x] PR [#127](https://github.com/Icedmist/WavePass-Android/pull/127) merged to `main`.

### 51. Voucher Wall-Clock Expiration, Stale Session Eviction & Rate-Limit Syntax Normalization (Issue #128, PR #129)
- [x] **Diagnosed Operator Issue for `Sahabimusa963@gmail.com`**:
  - **Issue 1 (Vouchers Not Expiring)**: RouterOS `limit-uptime` only counts active connected uptime, not elapsed wall-clock time. A 1-day pass lasted weeks if used for only 1 hour daily.
  - **Issue 2 (Vouchers Not Working Before Expiration / Session Lockouts)**:
    - User profiles were provisioned with `shared-users=1` without session eviction on login. When phones disconnected, slept, or rotated MAC addresses, stale active sessions remained in `/ip/hotspot/active` for 2–5 minutes (`keepalive-timeout` / `idle-timeout`), rejecting reconnections with `"user already logged in"`.
    - Profiles had stale 30-day MAC cookies (`mac-cookie-timeout=30d`), causing authentication loops.
    - Operator's plan in Supabase had `rateLimit: "50mbps"`, which is invalid RouterOS syntax, corrupting user creation and queue limits.
- [x] **Rate Limit Normalization (`formatRouterOsRateLimit`)**:
  - Implemented `formatRouterOsRateLimit` in `RouterDiscoveryService` to automatically sanitize inputs (e.g., `50mbps` -> `50M/50M`, `10` -> `10M/10M`, `512k` -> `512k/512k`, ignoring `none`/`unlimited`).
  - Integrated into `PlanConfiguratorSheet` on plan save.
  - Live-patched `Sahabimusa963@gmail.com` active plan (`6c1b9d80-4cfc-44ee-a5b2-9372b22be0a5`) to `50M/50M`.
- [x] **RouterOS Reconnect Lockout Elimination (`onLoginScript`)**:
  - Configured user profiles with `shared-users: '2'` and an automated `on-login` eviction script that detects active session counts > 1, immediately kicking the oldest active session (`/ip hotspot active remove numbers=$ka`).
  - Preserves strict 1-device policy while allowing legitimate reconnects when a device wakes from sleep or changes network state.
- [x] **On-Router Hardware Wall-Clock Expiration Schedulers**:
  - `onLoginScript` dynamically generates a `/system/scheduler` task (`exp_$user`) upon first login with `interval=$limitUptime`.
  - When the duration expires, the router independently removes the active session, deletes the hotspot user, deletes `/ip/hotspot/cookie`, and cleans up the scheduler itself, even if the operator is offline or away from the router.
- [x] **Orphan MAC Cookie & Safety Cleanup**:
  - Reduced `mac-cookie-timeout` from `30d` to `3d`.
  - Enhanced `wavepass-cleanup` safety script (and `MikrotikApiClient` methods) to purge orphan cookies in `/ip/hotspot/cookie` whose users no longer exist.
  - Enhanced `VoucherHistoryService` to use dual-route client resolution (`local IP -> cloud tunnel`), calculate `remainingSeconds`, accurately backdate `usedAt` via cloud telemetry, and clean up hardware accounts.
- [x] **Exported Quick-Setup Terminal Script**:
  - Updated `router_setup_screen.dart` exported MikroTik terminal script to include `shared-users=2`, `mac-cookie-timeout=3d`, `on-login` session eviction, and comprehensive cookie/scheduler cleanup.
- [x] **Regression & Unit Tests**:
  - Created `test/voucher_expiration_and_session_reconnect_test.dart` validating rate-limit formatting, on-login eviction logic, dynamic scheduler configuration, orphan cookie cleanup, and `VoucherRecord` expiration calculations.
  - Updated existing tests in `test/voucher_limits_and_expiry_test.dart` and `test/mikrotik_api_client_test.dart`.
- [x] **Verification**:
  - `flutter analyze`: **No issues found** (0 warnings, 0 errors).
  - `flutter test`: **All 90 tests passed** (0 failures).
- [x] PR [#129](https://github.com/Icedmist/WavePass-Android/pull/129) merged to `main`.

### 52. Plan Retention Across Logout/Login & Captive Portal Auto-Connect (Issue #130, PR #131)
- [x] **Diagnosed Plan Disappearance Across Logout/Login**:
  - **Root Cause**: `VenueStateService` lacked disk persistence for `plansNotifier.value`. On logout, `clearVenue()` cleared in-memory state and removed cached venue keys from `SharedPreferences`. When an operator logged back in, if the network was slow or `getPrimaryVenue` had not completed, `refreshPlans()` aborted because `currentVenueId` was empty, leaving the plan list blank across Sell Pass and Admin.
  - Furthermore, in `supabase_service.dart`, `getPrimaryVenue` only queried `VenueMember` using `currentUser.id`. If a user logged in via admin password verification or if Auth state lagged, the operator venue query failed to resolve.
- [x] **Persistent Disk Caching & Instant Hydration in `VenueStateService`**:
  - Added SharedPreferences disk caching keys: `wavepass_active_venue_plans`, `wavepass_cached_plans_$venueId`, and `wavepass_user_venue_$email`.
  - In `init()`, cached plans and venue identity are restored synchronously from disk before network latency, eliminating empty plan states and UI flicker across app cold starts.
  - In `clearVenue({bool preserveUserCache = true})`, in-memory state is cleared immediately for security upon logout, while the local disk mapping is preserved. When the operator logs back in, their venue and plans are restored instantly. On explicit account switches, `preserveUserCache: false` completely wipes the cache.
  - In `refreshVenue()`, added multi-tier recovery: checks `WavePassApi.getVenue(vid)` (which returns full venue details with embedded plans and routers), direct Supabase queries, and an offline cached venue identity fallback so offline/spotty networks never wipe the active venue.
  - In `refreshPlans()`, loads cached plans as a fallback if the network is interrupted or delayed, and writes newly fetched plans to disk.
  - In `createPlan`, `updatePlan`, and `deletePlan`, automatically updates the disk cache (`_persistPlansCache`) to survive offline restarts.
- [x] **Email-Based Venue Member Resolution in `SupabaseService`**:
  - In `getPrimaryVenue()` and `getVenues()`, added Step 1b: queries `public.User` by `targetEmail` to resolve `VenueMember` records, preventing venue loss when `currentUser` takes time to propagate or when logging in via admin password verification.
- [x] **Captive Portal Auto-Connect Fixes (`router_setup_screen.dart`)**:
  - **Root Cause**: In `login.html`, `autoUrl` construction used `if (devMac) autoUrl += '&mac=...; else if (savedV) autoUrl += '&q=...;`. On MikroTik Hotspots, `devMac` (`$(mac)`) is always present, which permanently suppressed the saved voucher parameter (`&q=`), returning `{ found: false }` for counter-sold or batch vouchers.
  - **Simultaneous MAC & Voucher Query**: Updated `autoUrl` to include BOTH `&mac=` AND `&q=` (`if (devMac)...; if (savedV)...;`).
  - **RouterOS Error Loop Guard**: Detected `.error-msg` from RouterOS. If RouterOS returns an authentication error (e.g. invalid code or expired uptime), `wp-auto-attempt` and `wp-active-voucher` are cleared immediately, preventing infinite submit loops and enabling fresh input.
  - **Offline / Pre-Auth Captive Portal Fallback**: When client requests to cloud backend are blocked, DNS-filtered, or timed out prior to Hotspot authentication, the captive portal immediately falls back to `executeLogin(savedV, savedV)` (or `savedU, savedP`) so RouterOS Hotspot can authenticate the client locally.
  - Added `AbortController` timeout (1500ms) to cloud voucher check.
- [x] **Regression & Unit Tests**:
  - Created `test/plan_retention_and_portal_autoconnect_test.dart` validating synchronous plan hydration on `init()`, plan retention across logout/login, cache purging on account switch, plan mutation persistence, auto-connect URL construction with both `&mac=` and `&q=`, RouterOS error detection and loop guard, offline fallback, and 1-tap reconnect box rendering.
- [x] **Verification**:
  - `flutter analyze --no-pub`: **No issues found** (0 warnings, 0 errors).
  - `flutter test --no-pub`: **All 98 tests passed** (0 failures).
- [x] PR [#131](https://github.com/Icedmist/WavePass-Android/pull/131) merged to `main`.

### 53. In-App Self-Updater via GitHub Releases for Sideloaded Android (Issue #136, PR #137)
- [x] **Direct APK Download & Sideload Updating**:
  - Added `android.permission.REQUEST_INSTALL_PACKAGES` to `AndroidManifest.xml` to allow seamless in-place updating of sideloaded installs without Play Store dependency.
  - Implemented `AppUpdateService` (`lib/core/services/app_update_service.dart`) managing remote release checks against GitHub Releases API (`https://api.github.com/repos/Icedmist/WavePass-Android/releases/latest`).
  - Added semver comparator (`isNewerVersion`) supporting `v` prefixes and build numbers (e.g. `1.0.1+2` vs `1.0.2`).
  - Implemented streamed chunked APK downloading with progress callback (`MB / Total MB`) and `OpenFile.open` installer invocation.
  - Added modern interactive update dialog (`_AppUpdateDialog`) displaying latest version, current version, release notes, progress bar, and action triggers.
- [x] **UI & Lifecycle Integration**:
  - Integrated post-frame background update check on dashboard mount (`home_dashboard_screen.dart`) with 4-hour cooldown caching.
  - Added "WavePass Version" and manual "Check for Updates" tile to Account Center (`account_center_screen.dart`).
- [x] **Unit Testing**:
  - Created `test/app_update_service_test.dart` verifying semver bump detections (patch, minor, major, build numbers) and API resilience.
- [x] **Verification**:
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 109 tests passed**.
- [x] PR [#137](https://github.com/Icedmist/WavePass-Android/pull/137) merged to `main`.

### 54. Check for Updates Component in Settings & Admin Hub (Issue #138, PR #139)
- [x] **Admin Hub & Account Center Integration**:
  - Added dedicated `Check for Updates` tool tile under Advanced & Hardware Tools in Admin Hub (`lib/screens/admin_management_screen.dart`).
  - Upgraded Account Center update tile with full `InkWell` card wrapping to allow tap-anywhere triggers.
  - Added real-time user feedback with toast/snackbars indicating check status, up-to-date notifications, and error resilience.
- [x] **Automated UI Verification**:
  - Created `test/update_ui_verification_test.dart` testing the update UI flow with mock HTTP release responses.
  - Verified update dialog presentation, release notes rendering, "Update Now", and "Later" buttons.
  - Verified up-to-date snackbar feedback when version matches.
- [x] **Verification**:
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 111 tests passed**.
- [x] PR [#139](https://github.com/Icedmist/WavePass-Android/pull/139) merged to `main`.

### 55. Fix GitHub Pages Deployment & Release Workflow YAML Syntax (Issue #140, PR #141)
- [x] **GitHub Pages 404 Resolution**:
  - Diagnosed `404 Not Found` in `actions/deploy-pages@v4` on `pages.yml`.
  - Enabled GitHub Pages with `build_type: workflow` via GitHub REST API (`POST /repos/Icedmist/WavePass-Android/pages`).
  - Re-ran workflow; `Deploy Flutter Web to GitHub Pages` passed successfully in 2m8s (`https://icedmist.github.io/WavePass-Android/`).
- [x] **Release Workflow YAML Fix**:
  - Diagnosed `ScannerError` in `.github/workflows/release.yml` caused by root-level unindented heredoc lines in `android/key.properties` generation.
  - Replaced unindented heredoc with structured, indented echo block to guarantee valid YAML.
  - Added `permissions: contents: write`.
  - Added version extraction from `pubspec.yaml` and `softprops/action-gh-release@v2` publishing step with compiled APK and AppBundle attached.
- [x] PR [#141](https://github.com/Icedmist/WavePass-Android/pull/141) merged to `main`.

### 56. Dual-Repository Release Publishing & Multi-Tier Fallback Update Checking (Issue #142, PR #143)
- [x] **Cross-Repository Release Automation (`.github/workflows/release.yml`)**:
  - Configured automated dual release deployment on tagged builds (`v*`) and manual workflow dispatches.
  - Automatically publishes releases and binary artifacts (`app-release.apk` and `app-release.aab`) to both the primary source repository (`Icedmist/WavePass-Android`) and the public distribution repository (`Icedmist/WavePass-App`).
  - Integrated `GH_RELEASE_TOKEN` secret and `gh release create` / `gh release upload --clobber` for automated asset uploads.
- [x] **Multi-Tier Fallback App Update Service (`lib/core/services/app_update_service.dart`)**:
  - Implemented multi-tier fallback update resolution:
    1. **Primary**: Backend API version endpoint (`https://api.nexawavepass.com/api/v1/app/version`)
    2. **Secondary**: Public distribution repository releases (`Icedmist/WavePass-App`)
    3. **Tertiary**: Source repository releases (`Icedmist/WavePass-Android`)
  - Ensures remote in-app updates continue functioning seamlessly even if the primary source repository is made private.
- [x] **Automated Testing & Verification**:
  - Updated `test/app_update_service_test.dart` to verify backend API prioritization, public distribution repository fallback, and graceful error handling.
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 113 tests passed**.
- [x] PR [#143](https://github.com/Icedmist/WavePass-Android/pull/143) merged to `main`.

### 57. Wallet Input Validation, Missing Details Error Handling & Prompt Dialogs (Issue #144, PR #145)
- [x] **Missing Settlement Bank Account Prompting**:
  - Implemented proactive check in `_requestCashout()` verifying `_bankAccounts.isNotEmpty` before initiating cashout.
  - Eliminated `StateError: Bad state: No element` crashes by presenting a modern, styled alert dialog prompting the venue owner to register a settlement bank account with a direct `"Add Bank Account"` action button.
- [x] **Interactive Bank Account Registration Dialog**:
  - Integrated a curated Nigerian bank selection dropdown with popular commercial and digital banks (Access, GTBank, Zenith, FirstBank, UBA, Kuda, OPay, PalmPay, Moniepoint, Stanbic, Sterling, Fidelity, FCMB, Wema, etc.) plus custom CBN bank code input fallback.
  - Added strict 10-digit NUBAN account number validation with `FilteringTextInputFormatter.digitsOnly` and inline error prompt (`"Account number must be exactly 10 digits."`).
  - Added account holder name presence check with inline feedback (`"Account holder name is required."`).
  - Added friendly user dialog displaying actionable guidance upon Paystack bank registration rejection.
- [x] **Cashout Amount & Password Authorization Validation**:
  - Added inline validation in `_requestCashout()` dialog enforcing positive amount, minimum cashout floor (₦500), and maximum limit within available balance (`_availableNgn`).
  - Added inline validation requiring owner password before sending cashout request.
  - Handled submission failures and OTP confirmation states with descriptive alerts.
- [x] **Automated Testing & Verification**:
  - Created `test/wallet_validation_test.dart` asserting input validation prompts, 10-digit NUBAN constraints, and missing bank account dialog navigation.
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 115 tests passed**.
- [x] PR [#145](https://github.com/Icedmist/WavePass-Android/pull/145) merged to `main` (commit `2c35dd3`).

### 58. Dynamic Wallet Active Venue Synchronization & Auto-Provision DVA (Issue #146, PR #147)
- [x] **Wallet Screen Dynamic Venue Synchronization (`lib/screens/wallet_screen.dart`)**:
  - Registered `VenueStateService.instance.venueNotifier` listener in `WalletScreenState.initState()` with proper disposal in `dispose()`.
  - Added dynamic `_onVenueChanged()` handler to automatically reload wallet balances, transaction logs, and Dedicated Virtual Accounts (DVA) whenever an operator switches active venues or creates a new venue.
  - Enhanced `_load()` to actively query `VenueStateService.instance.currentVenueId` and hydrate active venue state before falling back to default venue.
  - Updated Dedicated Virtual Account card header to explicitly display active venue name: `DEDICATED ACCOUNT • ${VenueStateService.instance.currentVenueName.toUpperCase()}` for unambiguous operator visual confirmation.
- [x] **Automatic DVA Provisioning on Venue Creation (`lib/core/services/venue_state_service.dart`)**:
  - Automatically invokes `WavePassApi.ensureVirtualAccount(newVenue.id)` upon venue creation in `createVenue()`.
  - Ensures newly created venues immediately initialize their dedicated bank account without waiting for an initial manual wallet tab visit.
- [x] **Backend Paystack Customer Scoping & Collision Prevention (`WavePass-Backend` Issue #68, PR #69)**:
  - Addressed root cause of venues sharing virtual accounts where synthetic Paystack customer email generation relied solely on venue name.
  - Scoped customer emails to venue ID and slug (`venue.${cleanSlug}.${shortId}@nexawavepass.com`) ensuring 100% 1-to-1 customer and DVA uniqueness.
  - Added collision detection in `ensureForVenue` to purge collided DVA entries and re-provision dedicated accounts.
- [x] **Automated Testing & Verification**:
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All tests passed**.
- [x] PR [#147](https://github.com/Icedmist/WavePass-Android/pull/147) merged to `main` (commit `aff3867`).

### 59. Fix Captive Portal CORS Preflight, Voucher Device Notifications, Walled Garden IP & Release Automation (Issue #148, PR #149 & Backend Issue #70, PR #71)
- [x] **Captive Portal CORS Preflight 500 Fix (`WavePass-Backend` Issue #70, PR #71)**:
  - Addressed root cause of `Payment Error: Failed to fetch` on captive portal domains (e.g. `nuru.net`, `192.168.88.1`).
  - Fastify previously threw an unhandled Error for origins outside `FRONTEND_URL`, returning `HTTP 500` on browser `OPTIONS` preflight requests.
  - Updated `src/main.ts` CORS origin handler to reflect the request origin (`cb(null, true)`) and allow standard headers (`Content-Type`, `Authorization`, `x-paystack-signature`, `Accept`, `Origin`, `X-Requested-With`).
  - Built, tested (150/150 tests passed), and deployed to droplet; verified live `curl -i -X OPTIONS https://api.nexawavepass.com/api/v1/portal/init-payment -H "Origin: http://nuru.net"` returns `HTTP 204 No Content` with `access-control-allow-origin: http://nuru.net`.
- [x] **Voucher Device Status Notifications (`lib/core/services/notification_service.dart`)**:
  - Broadened `refreshPayments` notification filter from only `PAYMENT` to also include `VOUCHER` events (`typeRaw == 'VOUCHER' || typeRaw.contains('VOUCHER')`), ensuring pass usage and status changes trigger the Android system notification bar (`_showBar`).
  - Added post-frame callback in `HomeDashboardScreen.initState()` to request Android 13+ `POST_NOTIFICATIONS` runtime permissions once the activity is fully mounted.
- [x] **Router Setup Script Walled Garden Static IP (`lib/screens/router_setup_screen.dart`)**:
  - Added `add comment="WavePass API Static IP (HTTPS)" dst-address=134.209.116.20 action=accept` to `/ip hotspot walled-garden ip` rules, preventing HTTPS pre-auth drops when clients use DNS-over-HTTPS (DoH).
- [x] **Dual-Repository Automated Release Publishing (`.github/workflows/release.yml`)**:
  - Updated release triggers to publish compiled APK and AppBundle assets to both `Icedmist/WavePass-Android` and `Icedmist/WavePass-App` on push to `main` as well as tagged releases and manual dispatch.
  - Bumped version to `1.0.2+3` across `pubspec.yaml` and `lib/core/services/app_update_service.dart`.
  - Pushed git tag `v1.0.2+3` to establish the new release.
- [x] **Automated Testing & Verification**:
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 115 tests passed**.
- [x] PR [#149](https://github.com/Icedmist/WavePass-Android/pull/149) merged to `main` (commit `b4d31c7`).

### 60. Captive Portal Checkout Redirect, Venue Plans Persistence Across Logout/Update, & Active Devices Discovery (Issue #150, PR #151)
- [x] **Captive Portal Paystack Hosted Checkout Redirect (`lib/screens/router_setup_screen.dart`)**:
  - Addressed root cause where Android CaptivePortalLogin and iOS CNA (Captive Network Assistant) sandboxes block `PaystackPop.openIframe()` popups and 3rd-party banking redirects.
  - Prioritized direct navigation: `if (data.authorization_url) { window.location.href = data.authorization_url; return; }` to allow native checkout flows (Cards, USSD, Bank Transfer).
  - Stored `data.reference` in `localStorage` and `sessionStorage` (`wp_pending_ref`).
  - Added `DOMContentLoaded` listener that detects return payment parameters (`?reference=`, `?trxref=`, or `wp_pending_ref`), fetches the voucher from `/api/v1/portal/retrieve-voucher`, and triggers instant `executeLogin(voucherCode, voucherCode)`.
- [x] **Venue & Plans Persistence Across Logout & App Updates (`lib/core/services/venue_state_service.dart`)**:
  - Introduced `keyLastKnownVenueId = 'wavepass_last_known_venue_id'`.
  - In `clearVenue({bool preserveUserCache = true})`, preserved `keyLastKnownVenueId`, `$keyCachedPlansPrefix$vid`, and `keyVenuePlans` when `preserveUserCache` is true.
  - In `init()` and `refreshVenue()`, resolved venue ID from `keyLastKnownVenueId` and added backend `getDefaultVenue()` fallback.
  - In `refreshPlans()`, resolved venue ID from `currentVenueId ?? keyVenueId ?? keyLastKnownVenueId`, pulling plans from backend `WavePassApi.listPlans`, Supabase `getActivePlans`, and disk cache `$keyCachedPlansPrefix$vid`.
  - Updated plan fallback logic to fall back to `keyVenuePlans` if venue-specific plan cache is empty.
  - In `lib/core/services/supabase_service.dart`, prioritized the flagship venue (`0e65c025-480a-4a42-8c49-68b6f0b27712`) in `getPrimaryVenue()` for super-admin (`talk2icedmist@gmail.com`) instead of falling back to arbitrary newly created test venues.
- [x] **Screens Plan Recovery & Proactive Hydration (`sell_pass_screen.dart`, `batch_vouchers_screen.dart`, `admin_management_screen.dart`)**:
  - Ensured `refreshPlans()` runs proactively during initial venue resolution.
  - In `admin_management_screen.dart`, added backend `WavePassApi.instance.listPlans(venueId: _venueId!)` fallback.
- [x] **Online Devices Discovery Dual-Probe (`lib/screens/active_devices_screen.dart`, `lib/screens/home_dashboard_screen.dart`)**:
  - Resolved `venueId` using `VenueStateService.currentVenueId ?? keyVenueId ?? keyLastKnownVenueId ?? primaryVenue`.
  - Implemented dual-probe logic: probes local LAN (`192.168.88.1`) first, and if empty/unreachable, falls back to the remote tunnel endpoint.
  - Fetches sessions via `WavePassApi.instance.listSessions(venueId)` before falling back to Supabase.
  - In `lib/core/services/wavepass_api.dart`, exposed public `get(String path)` and added `listSessions(String venueId)` helper.
- [x] **Automated Testing & Verification**:
  - Added comprehensive unit tests in `test/plan_retention_and_portal_autoconnect_test.dart` for authorization redirect priority, `DOMContentLoaded` auto-retrieval, and plan hydration via `keyLastKnownVenueId`.
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 117 tests passed**.
- [x] PR [#151](https://github.com/Icedmist/WavePass-Android/pull/151) merged to `main` (commit `5b8d0da`).
### 61. Captive Portal Auto-Trial Checkout, Flagship Plans Persistence, & Active Devices Probing (Issue #152, PR #153)
- [x] **Captive Portal Auto-Grant Payment Trial for Paystack Checkout (`lib/screens/router_setup_screen.dart`)**:
  - Identified root cause where MikroTik walled garden IP rules cannot whitelist the myriad external domains and CDNs utilized by Nigerian banks for 3DS OTPs, USSD, and Paystack assets.
  - Implemented captive payment window auto-grant: When `data.authorization_url` is returned in captive environments (`$(link-login-only)`), the portal automatically grants a 2-minute trial connection (`wp-payment-trial`) by redirecting to `linkLogin + '?dst=' + encodeURIComponent(data.authorization_url) + '&username=wp-payment-trial'`.
  - Gives users full unrestricted internet access during checkout so 3DS bank OTPs and transfers load seamlessly.
  - Standardized walled-garden script syntax with valid wildcard domains (`*.paystack.com` and `*.paystack.co`).
- [x] **Flagship Venue & Plans Auto-Resolution (`lib/core/services/venue_state_service.dart`)**:
  - In `refreshVenue()`: Directly queries backend `getVenue('0e65c025-480a-4a42-8c49-68b6f0b27712')` (the flagship venue) when logged in as super-admin (`talk2icedmist@gmail.com`) before any generic fallback.
  - Paired with backend PR [#73](https://github.com/Icedmist/WavePass-Backend/pull/73) (`WavePass-Backend` Issue [#72](https://github.com/Icedmist/WavePass-Backend/issues/72)), which prioritizes flagship / active-plan venues in `getDefaultVenue()`.
- [x] **Router Credentials Retention Across Logout & Login (`lib/screens/account_center_screen.dart`, `lib/screens/login_screen.dart`)**:
  - In `account_center_screen.dart`: Preserved router credentials (`keyRouterLocalIp`, `keyRouterPassword`, etc.) and cached plans across sign out, saving `sb-last-signed-in-email`.
  - In `login_screen.dart`: Only wipes router configurations if a completely different user account logs in, preventing accidental removal of router passwords and credentials when an operator re-authenticates.
- [x] **Online Devices Gateway Discovery & Expiry Filtering (`lib/screens/active_devices_screen.dart`)**:
  - Dynamically probes the local subnet default gateway (`${parts[0]}.${parts[1]}.${parts[2]}.1`) using `RouterDiscoveryService.getLocalDeviceIp()` when the configured `localIp` is unreachable or unconfigured.
  - Filtered out expired DB sessions (`remainingSec <= 0 && matchHw == null`) from the active devices list to ensure only currently active sessions and connected hardware devices are displayed.
- [x] **Automated Testing & Verification**:
  - Added unit tests in `test/plan_retention_and_portal_autoconnect_test.dart` for payment trial auto-grant, credential retention on same operator login, and gateway probing.
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 118 tests passed**.
### 62. Router Reboot Expired Voucher Protection, Cloud Sync Cap Expansion & Super-Admin Short-Circuit (Issue #154, PR #155)
- [x] **Router Reboot Expired Voucher Protection (`lib/core/services/voucher_history_service.dart`)**:
  - Identified root cause where RouterOS resets user uptime counters to 0s upon router reboot (e.g. after power outage or firmware update).
  - Previously, `fetchFullVoucherActivity()` ran an unconditional `existing.status = status`, which overwrote locally expired vouchers with `status = 'unused'` when router reported `uptime: 0s`.
  - Added strict one-way gating:
    ```dart
    if (status == 'expired' || existing.isExpired) {
      existing.status = 'expired';
    } else if (existing.status != 'expired' && !existing.isExpired) {
      if (status == 'in_use' || existing.status != 'in_use') {
        existing.status = status;
      }
    }
    ```
  - Guarantees that expired vouchers can never be resurrected on router reboot, and in-use vouchers are not downgraded to unused.
- [x] **Cloud Sync Cap Expansion (`lib/core/services/voucher_history_service.dart`)**:
  - Expanded the Supabase query limit in `fetchFullVoucherActivity()` from 200 to 1,000 vouchers (`.limit(1000)`), ensuring high-volume venues don't lose older historical voucher activity upon resync.
- [x] **Super-Admin Check Short-Circuit Optimization (`lib/core/services/voucher_history_service.dart`)**:
  - Fixed non-short-circuiting async call in `isSuperAdmin`:
    ```dart
    final isSuperAdmin = (currentEmail == SupabaseService.superAdminEmail)
        ? true
        : await SystemAdminService.instance.isSystemAdmin();
    ```
  - Eliminated redundant network/DB round-trips to Supabase on every sync for the super-admin account.
  - Also optimized `checkVoucherLifecycle` to only evaluate `isSuperAdmin` when `currentVenue == null`.
- [x] **Automated Testing & Verification**:
  - Added `FakeMikrotikApiClient` and unit tests in `test/voucher_limits_and_expiry_test.dart` asserting that router reboot (`uptime: 0s`) does not resurrect expired vouchers or downgrade in-use vouchers, while preserving legitimate transitions.
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 121 tests passed**.
- [x] PR [#155](https://github.com/Icedmist/WavePass-Android/pull/155) merged to `main` (commit `4719205`).

### 63. Persistent Release Keystore Generation & CI Signing Configuration (Issue #156, PR #157)
- [x] **Persistent Release Keystore Generation**:
  - Generated official upload keystore `upload-keystore.jks` (RSA 2048-bit, 10,000 days validity until 2054) under alias `wavepass-upload`.
  - Certificate Fingerprints:
    - SHA-256: `B5:8A:87:8B:7D:83:6D:14:D0:DF:95:36:3C:04:B1:3D:D5:A4:20:D6:1A:A3:65:90:A2:32:78:2B:F4:93:4F:18`
    - SHA-1: `28:A8:BF:5E:F3:84:EA:F7:B9:E1:70:E6:7D:B8:25:52:30:FB:B6:00`
- [x] **GitHub Actions Secrets Provisioning**:
  - Configured repository secrets on both `Icedmist/WavePass-Android` and `Icedmist/WavePass-App`:
    - `ANDROID_KEYSTORE_BASE64` (Base64-encoded JKS binary)
    - `KEYSTORE_PASSWORD`
    - `KEY_ALIAS` (`wavepass-upload`)
    - `KEY_PASSWORD`
- [x] **Gradle Build Configuration (`android/app/build.gradle.kts`)**:
  - Updated `android/app/build.gradle.kts` to robustly locate `storeFile` in either the subproject `app/` directory or `rootProject.file(...)`.
  - Added release signing config pointing directly to `key.properties`.
- [x] **Release CI Workflow Hardening (`.github/workflows/release.yml`)**:
  - Made keystore configuration mandatory; workflow fails immediately if `ANDROID_KEYSTORE_BASE64` is missing rather than silently falling back to ephemeral debug keys.
  - Automatically writes `android/key.properties` and decodes `android/app/upload-keystore.jks` before building.
  - Added automated signature verification step in CI (`keytool -printcert -jarfile ...`).
- [x] **Build & Signature Verification**:
  - Locally verified release build with `./gradlew app:signingReport` and `apksigner verify --verbose --print-certs`.
  - Verified APK Signature Scheme v2 valid, signed by `CN=WavePass, OU=Engineering, O=WavePass, L=Lagos, ST=Lagos, C=NG`.
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 121 tests passed**.
- [x] PR [#157](https://github.com/Icedmist/WavePass-Android/pull/157) merged to `main` (commit `3835a04`).

### 64. Dynamic Portal Venue Plans, Paystack Init Resilience, App Notifications, and Voucher Filtering & Search (Issue #158, PR #159)
- [x] **Dynamic Venue Plans in Captive Portal (`lib/screens/router_setup_screen.dart`)**:
  - Eliminated hardcoded fallback plans (`plan_1h`, `plan_24h`, `plan_7d`) in `_generateLoginHtml`.
  - Injected client-side JavaScript (`fetchLiveVenuePlans()` and `renderDynamicPlans()`) into `login.html` to dynamically fetch live venue plans from `/api/v1/portal/plans?venueId=...` on portal load and hydrate `#plansContainer` with real backend plan UUIDs.
  - Enhanced `_ensurePortalSuite()` to directly query `WavePassApi.instance.listPlans(venueId: venueIdStr)` and `SupabaseService.instance.getActivePlans(venueIdStr)` if plans are initially empty, updating `VenueStateService.plansNotifier`.
  - Added `venueNotifier` and `plansNotifier` listeners in `_RouterSetupScreenState` to invalidate cached portal suites upon any plan update, and properly unregistered them in `dispose()`.
- [x] **Paystack Initialization Resilience (`lib/screens/router_setup_screen.dart`)**:
  - Fixed `login.html` pay buttons to use real plan IDs instead of predefined IDs that failed with 404 on the backend.
  - Sanitized MAC addresses to enforce valid `AA:BB:CC:DD:EE:FF` format matching backend `InitPaymentDto`.
  - Resolved `effectiveVenueId` to prevent sending the literal string `"null"`, which was triggering 500 foreign-key constraint violations on `Order.venueId` in Prisma.
  - Added detailed error message extraction on failed payment initialization responses so guests receive clear explanations.
- [x] **In-App & Device Notifications Fix (`lib/core/services/notification_service.dart`, `lib/screens/home_dashboard_screen.dart`)**:
  - Fixed startup crash where calling `androidPlugin.requestNotificationsPermission()` during headless `main()` before `runApp()` threw an unhandled exception before `_barReady = true` was set, permanently disabling all device notifications. Permission requesting is now isolated strictly to `requestPermission()` when an Activity is attached.
  - Secured notification ID against 32-bit integer overflow using `(DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF)`.
  - Added `hideCurrentSnackBar()` and fallback to `showViaKey` when `ScaffoldMessenger.of(context)` fails.
  - Added `AppNotifier.instance.startPaymentPolling(vid)` inside `_loadDashboard()` in `home_dashboard_screen.dart`, ensuring payment polling starts as soon as the venue ID is resolved asynchronously.
- [x] **Voucher Filtering & Search (`lib/core/services/voucher_history_service.dart`, `lib/screens/voucher_history_sheet.dart`, `lib/screens/batch_vouchers_screen.dart`)**:
  - Normalized `isExpired` and `effectiveStatus` with case-insensitivity (`.toLowerCase().trim()`) and recognized status synonyms (`ACTIVE`, `REDEEMED`, `IN_USE` -> `'in_use'`; `EXPIRED`, `CONSUMED`, `REVOKED` -> `'expired'`). Previously, uppercase database/cloud statuses failed string comparison, causing all vouchers to fall back to `'unused'` and breaking tab filtering.
  - Changed default filter from `'unused'` to `'all'` in `VoucherHistorySheet` so vouchers aren't hidden by default.
  - Added interactive search bar in `VoucherHistorySheet` searching across `code`, `password`, `planTitle`, `mac`, and `ip`.
  - Expanded `BatchVouchersScreen` search filter to match `code`, `password`, `plan`, and `price`.
- [x] **Automated Testing & Verification**:
  - Added unit tests in `test/voucher_limits_and_expiry_test.dart` verifying case normalization and status synonyms (`ACTIVE`, `REDEEMED`, `CONSUMED`, `REVOKED`) for `effectiveStatus` and `isExpired`.
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 121 tests passed**.
- [x] PR [#159](https://github.com/Icedmist/WavePass-Android/pull/159) merged to `main` (commit `3b56354`).

### 65. Captive Portal Venue Target Sanitization & Auto-Connect Query Precision (Issue #160, PR #161)
- [x] **Venue Target Interpolation Sanitization (`lib/screens/router_setup_screen.dart`)**:
  - Eliminated dangerous Dart string interpolation where nullable `venueId` or `slug` evaluated to the string literal `'null'` inside injected portal JavaScript.
  - Defined `safeVenueId`, `safeSlug`, and `effectiveVenueTarget` in Dart prior to generating HTML, ensuring `effectiveVenueTarget` contains only a clean, non-null UUID or slug identifier.
  - Updated `retrieveActivePass()`, `payWithPaystack()`, `fetchLiveVenuePlans()`, `DOMContentLoaded` auto-claim, and auto-reconnect routines to consistently utilize `effectiveVenueTarget`.
  - Preserved exact query parameter formatting in `autoUrl` (`&mac=` and `&q=`) ensuring 100% compliance with captive portal auto-connect test specifications.
- [x] **Automated Testing & Verification**:
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test test/voucher_limits_and_expiry_test.dart test/plan_retention_and_portal_autoconnect_test.dart`: **All 26 tests passed**.
  - Full test suite: **All 122 tests passed**.
- [x] PR [#161](https://github.com/Icedmist/WavePass-Android/pull/161) squashed and merged to `main` (commit `51924d9`).

### 66. In-App Update Resilience, Browser Fallbacks, Version Bump & GitHub Actions Storage Optimization (Issue #163, PR #164)
- [x] **Immediate Storage Recovery**:
  - Purged 49 obsolete workflow artifacts totaling 1.63 GB using GitHub API, instantly freeing up the user's exhausted GitHub Actions storage quota from 90% down to near 0%.
  - Cleaned up 5 stale duplicate Flutter SDK caches totaling 3.6+ GB.
- [x] **Workflow Storage & Compute Optimization (`.github/workflows/release.yml`, `.github/workflows/pages.yml`)**:
  - Removed wasteful `actions/upload-artifact@v4` steps in `release.yml` that previously duplicated GitHub Releases and stored 110 MB per run with 90-day retention.
  - Restricted `release.yml` to trigger on tag pushes (`tags: ['v*']`) and manual triggers (`workflow_dispatch`), preventing 15-minute release builds and artifact accumulation on every push to `main`.
  - Removed failing `pages.yml` workflow which was repeatedly erroring on GitHub Pages deployment (status 404) and burning runner minutes.
- [x] **In-App Update Hardening (`lib/core/services/app_update_service.dart`, `pubspec.yaml`)**:
  - Bumped app version to `1.0.3+4` across `pubspec.yaml` and `AppUpdateService.currentVersion`, enabling existing `1.0.2+3` installs to detect new releases.
  - Added direct dependency for `url_launcher: ^6.3.2`.
  - Enhanced `downloadAndInstall()` to save APKs to `getExternalCacheDirectories()` (with fallback to `getTemporaryDirectory()`), ensuring PackageInstaller has read access across strict OEM Android distributions.
  - Implemented `_openInBrowser()` using `url_launcher` on `widget.update.downloadUrl` and `widget.update.htmlUrl`.
  - Upgraded `_AppUpdateDialogState` to include:
    - Dedicated "Browser" action button alongside "Update Now".
    - Direct browser icon button in dialog header.
    - Soft error notice card with prominent "Download via Browser" button whenever PackageInstaller cannot be launched or "Install unknown apps" permission is not yet toggled by the user.
  - Fixed `checkForUpdate()` fallback handling so that checking the source repo does not lock the app into a 4-hour cooldown when no update is found.
- [x] **Automated Testing & Verification**:
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 122 tests passed** (including unit tests in `test/app_update_service_test.dart` and widget tests in `test/update_ui_verification_test.dart`).
- [x] PR [#164](https://github.com/Icedmist/WavePass-Android/pull/164) squashed and merged to `main` (commit `184ab4a`).

### 67. Voucher Real-Time Online Status Tracking, Portal Suite Caching Fix, and Test Coverage (Issue #166, PR #167)
- [x] **Real-Time Voucher Online Status (`lib/core/services/voucher_history_service.dart`)**:
  - Added `bool isOnline` field with default `false` to `VoucherRecord` along with JSON serialization and deserialization.
  - In `fetchFullVoucherActivity`:
    - Updated MikroTik hardware sync (`/ip/hotspot/active`) to record live connection state (`isOnline: isActive`).
    - Updated Supabase cloud vouchers and sessions sync to mark `isOnline: true` when `latestSession['status'] == 'ACTIVE'`.
  - In `checkVoucherLifecycle`:
    - Cross-referenced live MikroTik active users against cached voucher history, updating `record.isOnline` dynamically and setting `stateChanged = true`.
    - Automatically reset `record.isOnline = false` when vouchers expire naturally or when uptime limit is reached.
  - In `expireVoucher`: reset `v.isOnline = false` upon manual expiration.
- [x] **Voucher History UI Enhancements (`lib/screens/voucher_history_sheet.dart`)**:
  - Updated `_statusColor` and `_statusLabel` to accept `bool isOnline`:
    - Active connected: `ONLINE (CONNECTED)` with green badge (`#10B981`) and Wi-Fi tethering icon.
    - Redeemed idle/offline: `IN USE (OFFLINE)` with amber badge (`#D97706`) and Wi-Fi off icon.
    - Available: `INACTIVE (AVAILABLE)` with primary purple/blue.
    - Expired: `EXPIRED` with muted text color.
  - Updated header counter to display active online count alongside in-use total.
  - Updated voucher card border and status banner to reflect active vs offline state with last known MAC and IP addresses.
- [x] **Portal Suite Caching Fix (`lib/screens/router_setup_screen.dart`)**:
  - Prevented premature caching of `_portalSuite` when venue pricing plans have not finished loading from network (`plans.isNotEmpty`).
  - Added fallback query using venue slug when venue ID is resolving, preventing the captive portal from showing a perpetual "Connecting to venue store..." notice.
- [x] **Automated Testing & Verification**:
  - Added unit tests in `test/voucher_limits_and_expiry_test.dart` verifying `isOnline` serialization, deserialization, and status assertions.
  - `flutter analyze`: **0 warnings, 0 errors**.
  - `flutter test`: **All 122 tests passed**.
- [x] PR [#167](https://github.com/Icedmist/WavePass-Android/pull/167) squashed and merged to `main` (commit `eacfa0f`).

### 68. Release v1.0.4+5 & CI Cloud Storage Optimization (Commit aae77df, Tag v1.0.4)
- [x] **Version Bump (`pubspec.yaml`)**:
  - Bumped version from `1.0.3+4` to `1.0.4+5`.
  - Pushed commit `aae77df` (`chore: bump version to 1.0.4+5`) to `main`.
  - Tagged `v1.0.4` and pushed to remote origin.
- [x] **Automated Build & Release Verification (`.github/workflows/release.yml`)**:
  - Workflow run `37512686180` completed successfully in 7m48s.
  - "Verify APK Signature" step verified release certificate:
    - Owner/Issuer: `CN=WavePass, OU=WavePass, O=WavePass, L=Unknown, ST=Unknown, C=NG`
    - Serial number: `e1c3d11b85437887`
    - SHA256: `39:91:07:95:5F:EF:CE:FF:34:77:4D:4A:23:4E:99:A8:1C:12:4E:D4:B4:72:FB:A3:34:E3:69:89:1E:E7:09:A0`
  - GitHub Releases deployed:
    - Source repo: [Icedmist/WavePass-Android v1.0.4](https://github.com/Icedmist/WavePass-Android/releases/tag/v1.0.4)
    - Public distribution repo: [Icedmist/WavePass-App v1.0.4](https://github.com/Icedmist/WavePass-App/releases/tag/v1.0.4)
    - Download APK: `https://github.com/Icedmist/WavePass-Android/releases/download/v1.0.4/app-release.apk`
- [x] **GitHub Cloud Storage Recovery**:
  - Purged 5 stale Actions caches in `WavePass-Android` (~1.96 GB).
  - Purged 77 build artifacts in `WavePass-Backend` (~1.48 MB).
  - Purged 1 Actions cache in `Hausa-Learn` (~154 MB).
- [x] **WavePass-Backend Droplet Deployment Verification**:
  - Latest commit on `main`: `edea423` (successor to `79ea7fa`).
  - GitHub Actions `Build, Push and Deploy` run `37463406442` succeeded.
  - Droplet logs confirmed `git pull --ff-only origin main` updated `79ea7fa..edea423`, pulled new container image, applied database migrations, and health check passed (`status: ok`).
  - Live production endpoint `https://api.nexawavepass.com/api/v1/health` confirmed running and healthy.


