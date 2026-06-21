/**
 * BrgySync — Seed Admin (Captain) Account Script
 *
 * Creates the initial Barangay Captain account in Firebase Auth + Firestore.
 * Run once after setting up environment variables.
 *
 * Usage:
 *   node scripts/seed-admin.js
 *
 * Required env vars:
 *   FIREBASE_SERVICE_ACCOUNT  — stringified Firebase Admin service account JSON
 *   ADMIN_EMAIL               — captain's email address
 *   ADMIN_PASSWORD            — captain's password
 *   ADMIN_NAME                — captain's full name (default: "Barangay Captain")
 *   ADMIN_MOBILE              — captain's mobile (default: "09170000000")
 */

const admin = require('firebase-admin');

const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const auth = admin.auth();
const db = admin.firestore();

const EMAIL = process.env.ADMIN_EMAIL;
const PASSWORD = process.env.ADMIN_PASSWORD;
const NAME = process.env.ADMIN_NAME || 'Barangay Captain';
const MOBILE = process.env.ADMIN_MOBILE || '09170000000';

if (!EMAIL || !PASSWORD) {
  console.error('ERROR: ADMIN_EMAIL and ADMIN_PASSWORD env vars are required.');
  console.error('Usage: ADMIN_EMAIL=captain@brgy.gov.ph ADMIN_PASSWORD=SecurePass123! FIREBASE_SERVICE_ACCOUNT={...} node scripts/seed-admin.js');
  process.exit(1);
}

async function main() {
  console.log('Creating Barangay Captain account...');

  // Check if user already exists
  try {
    const existing = await auth.getUserByEmail(EMAIL);
    console.log(`User already exists (uid: ${existing.uid}). Updating role to captain...`);
    await db.collection('users').doc(existing.uid).set({
      name: NAME,
      mobile: MOBILE,
      email: EMAIL,
      role: 'captain',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log('✓ Captain account updated.');
    process.exit(0);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }

  // Create new auth user
  const user = await auth.createUser({
    email: EMAIL,
    password: PASSWORD,
    displayName: NAME,
  });

  console.log(`✓ Auth user created (uid: ${user.uid})`);

  // Create Firestore user document
  await db.collection('users').doc(user.uid).set({
    name: NAME,
    mobile: MOBILE,
    email: EMAIL,
    role: 'captain',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log('✓ Firestore user document created.');
  console.log(`\nBarangay Captain account created successfully.`);
  console.log(`  Email:    ${EMAIL}`);
  console.log(`  Password: ${PASSWORD}`);
  console.log(`  Role:     captain`);
  console.log('\nYou can now log in with this account.');
}

main().catch(err => {
  console.error('Seed admin failed:', err);
  process.exit(1);
});
