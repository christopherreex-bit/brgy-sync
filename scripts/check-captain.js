/**
 * Check and fix the captain user document in Firestore.
 * Ensures the document ID matches the Auth UID and role is 'captain'.
 * Usage: node scripts/check-captain.js
 */

const admin = require('firebase-admin');

const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const auth = admin.auth();
const db = admin.firestore();

const EMAIL = process.env.ADMIN_EMAIL || 'captain@barangay.test';
const PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';
const NAME = process.env.ADMIN_NAME || 'Barangay Captain';
const MOBILE = process.env.ADMIN_MOBILE || '09170000000';

async function main() {
  // Step 1: Get the Auth user
  let authUser;
  try {
    authUser = await auth.getUserByEmail(EMAIL);
    console.log(`✓ Auth user found: ${EMAIL} (uid: ${authUser.uid})`);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      console.log('Auth user not found. Creating...');
      authUser = await auth.createUser({ email: EMAIL, password: PASSWORD, displayName: NAME });
      console.log(`✓ Auth user created (uid: ${authUser.uid})`);
    } else {
      throw e;
    }
  }

  // Step 2: Check Firestore user document
  const userDoc = await db.collection('users').doc(authUser.uid).get();
  if (userDoc.exists) {
    const data = userDoc.data();
    console.log(`✓ Firestore document exists at /users/${authUser.uid}`);
    console.log(`  Current role: ${data.role}`);
    if (data.role !== 'captain') {
      console.log('  ⚠ Role is NOT "captain" — updating...');
      await db.collection('users').doc(authUser.uid).update({ role: 'captain' });
      console.log('  ✓ Role updated to "captain"');
    } else {
      console.log('  ✓ Role is already "captain"');
    }
  } else {
    console.log(`  ⚠ No Firestore document at /users/${authUser.uid} — creating...`);
    await db.collection('users').doc(authUser.uid).set({
      name: NAME,
      mobile: MOBILE,
      email: EMAIL,
      role: 'captain',
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('  ✓ Firestore document created with role: captain');
  }

  // Step 3: Check for duplicate/misnamed documents
  const allUsers = await db.collection('users').get();
  const misplaced = [];
  allUsers.forEach(doc => {
    if (doc.id !== authUser.uid && doc.data().email === EMAIL) {
      misplaced.push(doc.id);
    }
  });
  if (misplaced.length > 0) {
    console.log(`\n⚠ Found duplicate documents with same email at: ${misplaced.join(', ')}`);
    for (const docId of misplaced) {
      console.log(`  Deleting duplicate /users/${docId}...`);
      await db.collection('users').doc(docId).delete();
      console.log(`  ✓ Deleted /users/${docId}`);
    }
  }

  console.log('\n✅ Captain account is ready.');
  console.log(`  Email: ${EMAIL}`);
  console.log(`  UID:   ${authUser.uid}`);
  console.log(`  Role:  captain`);
}

main().catch(err => {
  console.error('❌ Error:', err);
  process.exit(1);
});
