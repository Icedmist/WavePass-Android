# WavePass Mobile — Venue Wi-Fi Manager (Flutter)

Flutter **3.41** app for venue owners/operators. Sell cash passes, manage MikroTik gateways, monitor live sessions, and **cash out to your own bank** — single **Nexa Paystack** key + 15-table cloud schema.

![WavePass Logo](assets/images/logo.png)

## 🗺️ Navigation — Floating Pill Shell

`StatefulShellRoute.indexedStack` + `ScaffoldWithNav` (floating pill `margin 16 rounded 28 shadow 32/8`) — 5 tabs `Home / Devices / Sell(red pill) / Wallet / Admin` — active tab black `primary` pill with white icon, `scale 1.0 + indicator transparent`, 68dp height. `CustomTransitionPage` slide `0.08,0.02` + scale `0.98→1` 320ms expo. Entry via `Splash → context.go()` (no `MaterialPageRoute`).

| Route | Path |
|---|---|
| Splash `/` → `has_seen_onboarding` → Onboarding/Login/Dashboard |
| Onboarding `/onboarding` **7 swipeable cards** (Daily Income, Plug In, Connect, Auto-Find, Scan, Sell & Customize `tune`, Cash Out) merging HowToUse |
| Login `/login` + Signup `/signup` → onboarding → dashboard |
| Dashboard `/dashboard` |
| Devices `/active-devices`, Sell `/sell-pass`, Wallet `/wallet`, Admin `/admin`, Account `/account`, Notifications `/notifications` |

How-to-Use is also **5-card PageView** (was static list).

## 💳 Wallet — DVA + Auto-Cashout

`lib/screens/wallet_screen.dart` — `FittedBox` `accountNumber` + `Wrap` `Add Bank/Cash Out` (no overflow), `AlwaysScrollable` + bottom 80 padding, `late final` → `double get` fix. Flow: `GET /virtual-accounts/venue/:id → ensure`, `GET /cashouts/balance`, `POST /cashouts/bank-accounts`, **amount+owner password** → `POST /cashouts{venueId, amountMinor, password}` auto-transfer. Cashouts list handles both `List` and `{data:[…]}`.

## 👤 Account Center — `lib/screens/account_center_screen.dart` `/account`

Profile pill (logo + email + ONLINE), Venue (Wallet/Notifications/HowToUse), Legal (Terms/Privacy, Supabase refs scrubbed), Session (Sign Out → `supabase.signOut → go(login)`).

## 🎟️ Sell — Custom Voucher Usage

`lib/screens/sell_pass_screen.dart` shows `duration / data / speed / devices` chips (`_miniChip`). `lib/core/widgets/plan_configurator.dart` bottom sheet: **Days + Hours text fields synced to 0.5-72h slider, Gigs text (empty=Unlimited) synced to 0-50GB slider, Price/Day, Speed, Devices 1-5** — creates or **edits existing** (`existing? update eq id : insert`) via Supabase `Plan` (`venueId, priceMinor, durationSeconds, dataLimitBytes, rateLimit, simultaneousDevices`).

## 🔔 Notifications — `lib/screens/notifications_screen.dart` `/notifications`

Bell in `Home` `AppBar` (`notifications_none_rounded` + red dot) → `context.push('/notifications')` full page (also sheet). `AppNotifier` variant toasts `success/error/warning/info` with icon+color, feed `ValueNotifier` + `markAllRead/clear`.

## 📡 Captive Portal

Any `http://` from unpaid MAC → MikroTik → `GET /api/v1/portal/captive?mac=&ip=&link-orig=` → 302 to web `.../portal?mac=` (walled garden open for `*.vercel.app, paystack, supabase`). Paid → `302 .../success?paid=1` with `remainingMs/dataUsed/dataLimit/IP`. `GET /portal/landing?mac=&ip=` returns JSON for landing.

## 🗃️ Supabase — All App Data

`lib/core/services/supabase_service.dart` (URL `vvoenmdzavyzlisykhks`) is the auth + data layer for `Venue`, `Plan`, `Session`, plus wallet tables. Backend's `prisma/supabase-schema.sql` is pushed to the same Supabase Postgres — mobile, web, and backend share one schema (15 tables). Offline fallback returns 3 demo plans.

## 🎨 Branding

New mark `assets/images/logo.png` (black squircle, white ribbon-W + Wi-Fi arcs, 1254×1254) replaces the old `〰` text glyph on Splash, Login, Onboarding, Dashboard. Launcher icons resized to `mipmap-mdpi…xxxhdpi/ic_launcher.png` (48–192 px). Source: `wavepass-design/logo/logo.png` → `wavepass-web/public/logo.png`.

## 🛠️ Run

```bash
flutter pub get
flutter analyze
flutter run -d android   # or -d linux / -d chrome
flutter build apk --release
```

Set `ApiConstants.cloudBaseUrl` to your backend (`wavepass-web.vercel.app` or `localhost:3000`), and `supabaseUrl/anonKey` in `lib/core/constants/api_constants.dart`. Env passwords: `OWNER_CASHOUT_PASSWORD` / `ADMIN_PASSWORD` (sha256 hashes) on backend.
