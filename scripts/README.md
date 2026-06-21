# BrgySync — Scripts

## seed-data.js

Seeds the Firestore database with realistic demo data for thesis defense.

**What it creates:**
- 4 test users (one per role)
- 4 SLA config entries
- 7 budget programs
- 25+ sample cases across all 7 categories
- Distribution records (senior citizens, PWD, education)
- 1 sample report
- 1 compliance snapshot

**Usage:**
```bash
FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}' node scripts/seed-data.js
```

**Test Accounts (after seeding):**

| Role | Email | Password |
|------|-------|----------|
| Resident | resident@brgysync.demo | Password123! |
| Staff | staff@brgysync.demo | Password123! |
| Officer | officer@brgysync.demo | Password123! |
| Captain | captain@brgysync.demo | Password123! |

> **Note:** The test users must first be created in Firebase Authentication
> (via Console or `seed-admin.js`), then run `seed-data.js` to create their
> Firestore documents and all demo data.

## seed-admin.js

Creates the initial Barangay Captain account. Run once after setting up env vars.

**Usage:**
```bash
ADMIN_EMAIL=captain@brgy.gov.ph \
ADMIN_PASSWORD=SecurePass123! \
ADMIN_NAME="Juan Dela Cruz" \
ADMIN_MOBILE=09170000000 \
FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}' \
node scripts/seed-admin.js
```
