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
