/**
 * Deploy Firestore security rules using Firebase Admin SDK.
 * Usage: node scripts/deploy-rules.js
 * Requires: FIREBASE_SERVICE_ACCOUNT env var
 */

const admin = require('firebase-admin');
const fs = require('fs');

const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const rules = fs.readFileSync('firestore.rules', 'utf8');

admin.securityRules().releaseFirestoreRulesetFromSource(rules)
  .then(() => {
    console.log('✅ Firestore rules deployed successfully.');
    process.exit(0);
  })
  .catch(err => {
    console.error('❌ Failed to deploy rules:', err.message);
    process.exit(1);
  });
