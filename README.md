# BrgySync

AI-powered automated workflow and case monitoring system for Barangay Calzada-Tipas, Taguig City. A Flutter **Web** app (deployed to Cloudflare Pages) backed by **Firebase Auth + Cloud Firestore**. Residents submit requests; staff and the barangay captain process them.

This guide covers two ways to run BrgySync:

- **Localhost** — run the app on your own machine for development/testing.
- **Hosted** — deploy the production app to Cloudflare Pages (this is already wired up via GitHub Actions).

---

## 1. Prerequisites

| Tool | Version | Used for |
|------|---------|----------|
| Flutter SDK | 3.44.2 (stable) | Building/running the app. **Not** on your PATH by default — use the full path or add it. |
| Dart | 3.x (ships with Flutter) | — |
| Node.js + npm | 18+ | Wrangler (hosted deploy) and seed scripts |
| Google Chrome | latest | Running the web app locally |
| Git | any | Cloning + deploys |
| Firebase project | — | Auth + Firestore backend (see §2) |
| Cloudflare account | — | Hosted deploy only (see §4) |

> **Flutter SDK path:** the project expects Flutter at `C:\flutter-sdk\bin\flutter` on Windows. Wherever you see `flutter` below, use the full path (or add Flutter to your `PATH`):
> ```bash
> # Windows
> C:\flutter-sdk\bin\flutter --version
> # macOS / Linux
> flutter --version
> ```

Confirm the toolchain is ready:

```bash
flutter doctor
```

---

## 2. Firebase backend setup

BrgySync needs a Firebase project with **Authentication** and **Cloud Firestore** enabled.

1. Create a Firebase project (or reuse an existing one).
2. **Authentication** → **Sign-in method** → enable **Email/Password**.
3. **Firestore Database** → create a database (start in production or test mode).
4. Deploy the security rules and indexes bundled with this repo:
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```
   (This uses the `firebase.json`, `firestore.rules`, and `firestore.indexes.json` in the repo root.)

### Pointing the app at your Firebase project

The web app's Firebase configuration is **baked into the build** in `lib/firebase_options.dart` (this is standard Flutter web behavior — there is no runtime env var for it).

- If you created a **new** Firebase project, replace the values in `lib/firebase_options.dart` with your project's web app config (Firebase Console → Project Settings → Your apps → Web app).
- The repo's committed values already point at the `brg-sync` project, so you can skip this if you're working against that project.

> **Note:** SMS provider keys (MySMSGate / Twilio) are the *only* values injected at build time (see §3.3 and §4.2). Everything else (Auth, Firestore) comes from `firebase_options.dart`.

---

## 3. Local development (localhost)

### 3.1 Install dependencies

```bash
flutter pub get
```

### 3.2 Run the app in Chrome

```bash
flutter run -d chrome
```

The app opens at `http://localhost:xxxx` (Flutter picks a free port). Use the test accounts below to sign in.

### 3.3 Optional: SMS provider keys for local runs

SMS sending is optional for local dev. The app reads these build-time variables via `--dart-define`; if omitted, SMS simply won't have credentials. To enable SMS locally, pass them on the run/build command:

```bash
flutter run -d chrome \
  --dart-define=MYSMSGATE_API_KEY=your_key \
  --dart-define=EASYSENDSMS_API_KEY=your_key \
  --dart-define=TWILIO_ACCOUNT_SID=ACxxxx \
  --dart-define=TWILIO_AUTH_TOKEN=your_token \
  --dart-define=TWILIO_FROM=+1XXXXXXXXX
```

(See `.env.example` for where to get each value.)

### 3.4 Seed demo data (optional)

To populate Firestore with realistic demo data and test accounts, you need a service-account key and Node.js:

```bash
# 1. Create the test users in Firebase Auth first (see scripts/README.md)
# 2. Then seed Firestore data:
FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}' node scripts/seed-data.js
```

Copy `.env.example` to `.env` and fill it in for the seed scripts — details in `scripts/README.md`.

### 3.5 Test accounts

After seeding, sign in with:

| Role | Email | Password |
|------|-------|----------|
| Resident | hehe@email.com | test123 |
| Captain | captain@barangay.test | admin123 |

---

## 4. Hosted deployment (Cloudflare Pages)

The production site is **brgy-sync.pages.dev**. Deploying happens two ways:

- **Push to `master`** → GitHub Actions builds and deploys automatically (recommended).
- **Manual deploy** from your machine with Wrangler.

### 4.1 One-time: Cloudflare + repo secrets

In the Cloudflare dashboard, create an **API Token** with **Cloudflare Pages → Edit** permission, and grab your **Account ID** (Workers & Pages → Overview). Then add these as **GitHub repository secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|--------|-------|
| `CF_API_TOKEN` | Cloudflare API token (Pages:Edit) |
| `CF_ACCOUNT_ID` | Cloudflare account ID |
| `MYSMSGATE_API_KEY` | MySMSGate API key |
| `EASYSENDSMS_API_KEY` | EasySendSMS API key |
| `TWILIO_ACCOUNT_SID` | Twilio account SID |
| `TWILIO_AUTH_TOKEN` | Twilio auth token |
| `TWILIO_FROM` | Twilio sender number (e.g. `+1XXXXXXXXX`) |

Also configure these in the **Cloudflare Pages project environment variables** (so the `/sms/send` Pages Function can reach MySMSGate):

| Pages env var | Value |
|---------------|-------|
| `MYSMSGATE_API_KEY` | MySMSGate API key |

> The SMS proxy is `functions/sms/send.js` — a Cloudflare **Pages Function** that deploys automatically alongside the site. It runs on the same origin as the app, so there are no CORS issues.

### 4.2 Automatic deploy (push to master)

```bash
git push origin master
```

`.github/workflows/deploy.yml` will: install Flutter, build the web bundle with the SMS keys from secrets, and run `wrangler pages deploy` to `brgy-sync`.

### 4.3 Manual deploy (from your machine)

```bash
# 1. Install deps
flutter pub get

# 2. Build the web release with SMS keys
flutter build web --release \
  --dart-define=MYSMSGATE_API_KEY=your_key \
  --dart-define=EASYSENDSMS_API_KEY=your_key \
  --dart-define=TWILIO_ACCOUNT_SID=ACxxxx \
  --dart-define=TWILIO_AUTH_TOKEN=your_token \
  --dart-define=TWILIO_FROM=+1XXXXXXXXX

# 3. Deploy the build/ folder to Cloudflare Pages
npx wrangler pages deploy build/web --project-name=brgy-sync
```

Set `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in your environment (or log in with `npx wrangler login`) before deploying.

---

## 5. Project layout

| Path | Purpose |
|------|---------|
| `lib/` | Flutter app source (screens, services, models, utils) |
| `web/` | Flutter web `index.html` + manifest/icons |
| `functions/sms/send.js` | Cloudflare Pages Function — SMS proxy |
| `scripts/` | Node.js seed scripts (see `scripts/README.md`) |
| `firestore.rules` / `firestore.indexes.json` | Firestore security rules + indexes |
| `.github/workflows/deploy.yml` | CI/CD to Cloudflare Pages |
| `.env.example` | Template for script environment variables |

---

## 6. Useful commands

```bash
# Run unit + widget tests
flutter test testing/unit testing/widget

# Build a production web bundle
flutter build web --release

# Deploy Firestore rules/indexes
firebase deploy --only firestore:rules,firestore:indexes
```

---

## 7. Notes

- **Build & deploy details** live in `CLAUDE.md` (Flutter SDK path, test accounts, integration-test commands).
- **Seed scripts** are documented in `scripts/README.md`.
- The app is **web-only**; mobile/desktop builds are out of scope for this deployment.
