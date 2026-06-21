/**
 * BrgySync — Budget Health Checker Cron Script
 *
 * Queries all budget programs and updates their health status:
 *   - Healthy  : remaining > threshold
 *   - Low      : remaining ≤ threshold but > 10% of allocated
 *   - Critical : remaining ≤ 10% of allocated
 *
 * Default threshold: 10% of allocated amount
 *
 * Run frequency: daily via Cron-job.org
 *
 * Required env var:
 *   FIREBASE_SERVICE_ACCOUNT — stringified Firebase Admin service account JSON
 */

const admin = require('firebase-admin');

const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function computeBudgetStatus(program) {
  const allocated = Number(program.allocated) || 0;
  const remaining = Number(program.remaining) ?? (allocated - Number(program.utilized || 0));
  const thresholdPercent = Number(program.thresholdPercent) || 10;
  const thresholdAmount = allocated * (thresholdPercent / 100);
  const criticalAmount = allocated * 0.10; // 10% of allocated

  if (remaining <= criticalAmount) return 'critical';
  if (remaining <= thresholdAmount) return 'low';
  return 'healthy';
}

async function main() {
  console.log(`[${new Date().toISOString()}] Budget Checker started`);

  const snapshot = await db.collection('budgetPrograms').get();

  if (snapshot.empty) {
    console.log('No budget programs found. Exiting.');
    process.exit(0);
  }

  console.log(`Checking ${snapshot.size} budget program(s)...`);
  let updated = 0;
  const batch = db.batch();

  for (const doc of snapshot.docs) {
    const program = doc.data();
    const newStatus = computeBudgetStatus(program);

    if (program.status !== newStatus) {
      batch.update(doc.ref, {
        status: newStatus,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
      updated++;
      console.log(`  ${program.name}: ${program.status || '(none)'} → ${newStatus}`);
    }
  }

  if (updated > 0) {
    await batch.commit();
    console.log(`Updated ${updated} budget program(s).`);
  } else {
    console.log('All budget programs already up to date.');
  }

  console.log(`[${new Date().toISOString()}] Budget Checker finished.`);
}

main().catch(err => {
  console.error('Budget Checker failed:', err);
  process.exit(1);
});
