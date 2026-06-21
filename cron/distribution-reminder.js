/**
 * BrgySync — Distribution Reminder Cron Script
 *
 * Flags upcoming distributions (senior citizen & PWD birthday programs)
 * that are scheduled within the next 7 days.
 *
 * Sets `reminderFlag: true` and `reminderNote` on matching distribution records.
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

async function main() {
  console.log(`[${new Date().toISOString()}] Distribution Reminder started`);

  const now = new Date();
  const sevenDaysFromNow = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

  // Query distributions in the next 7 days that haven't been released yet
  const snapshot = await db
    .collection('distributions')
    .where('status', 'in', ['pending', 'confirmed'])
    .where('scheduledDate', '>=', admin.firestore.Timestamp.fromDate(now))
    .where('scheduledDate', '<=', admin.firestore.Timestamp.fromDate(sevenDaysFromNow))
    .get();

  if (snapshot.empty) {
    console.log('No upcoming distributions in the next 7 days. Exiting.');
    process.exit(0);
  }

  console.log(`Found ${snapshot.size} upcoming distribution(s) within 7 days...`);
  let flagged = 0;
  const batch = db.batch();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!data.reminderFlag) {
      const scheduled = data.scheduledDate?.toDate
        ? data.scheduledDate.toDate()
        : null;
      const daysUntil = scheduled
        ? Math.round((scheduled - now) / (1000 * 60 * 60 * 24))
        : '?';

      batch.update(doc.ref, {
        reminderFlag: true,
        reminderNote: `Upcoming: ${daysUntil} day(s) until scheduled release (${data.programType || 'program'})`,
        lastReminderSent: admin.firestore.FieldValue.serverTimestamp(),
      });
      flagged++;
      console.log(`  Flagged: ${data.beneficiaryName} (${data.programType}) — ${daysUntil} days`);
    }
  }

  if (flagged > 0) {
    await batch.commit();
    console.log(`Flagged ${flagged} distribution record(s).`);
  } else {
    console.log('All upcoming distributions already flagged.');
  }

  console.log(`[${new Date().toISOString()}] Distribution Reminder finished.`);
}

main().catch(err => {
  console.error('Distribution Reminder failed:', err);
  process.exit(1);
});
