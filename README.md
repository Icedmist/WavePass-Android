# WavePass Mobile — Venue Wi-Fi Manager (Flutter)

Flutter **3.41** app for venue owners/operators. Sell cash passes, manage MikroTik gateways, monitor live sessions, and **cash out to your own bank** — all backed by **Supabase** + a single **Nexa Paystack** key.

![WavePass Logo](assets/images/logo.png)

## 🗺️ Navigation

Central **GoRouter** (`lib/core/router/app_router.dart`, 15 named routes):

| Route | Path | Screen |
|---|---|---|
| Splash | `/` | `SplashScreen` — animated logo → Supabase auth gate |
| Onboarding | `/onboarding` | 3-slide carousel |
| Login | `/login` | Supabase email/password |
| Dashboard | `/dashboard` | Revenue, online count, quick actions |
| Set Up Router | `/setup-router` | Wi-Fi auto-find + barcode scan |
| Sell Pass | `/sell-pass` | Plans → voucher code → Bluetooth print |
| Active Devices | `/active-devices` | Live sessions, disconnect |
| Router Health | `/router-health` | CPU/mem, restart |
| Printer | `/printer-settings` | Bluetooth POS pairing |
| Admin | `/admin` | Plans, reconcile/cleanup triggers |
| Wallet | `/wallet` | **DVA, balance, auto-cashout** |
| How-To / Terms / Privacy | … | Static guides |

Use `context.goNamedRoute(AppRouter.wallet)` — no ad-hoc `MaterialPageRoute` sprawl.

## 💳 Wallet — DVA + Auto-Cashout (Owner Password)

Single Nexa Paystack DVA per venue (platform settlement). Flow:

1. **DVA** — `WalletScreen` auto-calls `GET /virtual-accounts/venue/:venueId` → `ensure` if missing; shows `accountNumber`/`accountName` (`WavePassApi`).
2. **Balance** — `GET /cashouts/balance/:venueId` → `availableNGN`.
3. **Bank** — Register payout NUBAN: `POST /cashouts/bank-accounts` (Paystack `transferrecipient`).
4. **Auto-cashout** — Dialog asks **amount + owner password** → `POST /cashouts {venueId, amountMinor, password}`; server checks `availableMinor`, executes Paystack `transfer` instantly — no admin approval queue. Legacy pending items still confirmable via `POST /cashouts/confirm`.

Default venue resolved via `GET /venues/default` when `venueId == 'default'`.

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
