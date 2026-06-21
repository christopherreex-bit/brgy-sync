/**
 * BrgySync — Monthly Compliance Snapshot Cron Script
 *
 * Aggregates resolved/released/rejected cases from the current month and
 * writes a compliance snapshot to /complianceSnapshots.
 *
 * For each service category, computes:
 *   - totalReceived, completedOnTime, overdueCount, avgProcessingTime, complianceRate
 *
 * Run frequency: monthly (1st of each month) via Cron-job.org
 *
 * Required env var:
 *   FIREBASE_SERVICE_ACCOUNT — stringified Firebase Admin service account JSON
 */

const admin = require('firebase-admin');

const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const CATEGORIES = ['bass', 'documents', 'community', 'beneficiary', 'vaw', 'education', 'adhoc'];
const CATEGORY_LABELS = {
  bass: 'BASS Assistance',
  documents: 'Barangay Documents',
  community: 'Community Services',
  beneficiary: 'Beneficiary Registration',
  vaw: 'VAW / BCPC',
  education: 'Education Incentive',
  adhoc: 'Ad Hoc / Special Program',
};

async function main() {
  console.log(`[${new Date().toISOString()}] Compliance Snapshot started`);

  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const period = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

  // Check if snapshot already exists for this period
  const existing = await db
    .collection('complianceSnapshots')
    .where('period', '==', period)
    .limit(1)
    .get();

  if (!existing.empty) {
    console.log(`Snapshot for ${period} already exists. Skipping.`);
    process.exit(0);
  }

  // Fetch all cases submitted this month
  const snapshot = await db
    .collection('cases')
    .where('submissionTimestamp', '>=', admin.firestore.Timestamp.fromDate(startOfMonth))
    .where('submissionTimestamp', '<', admin.firestore.Timestamp.fromDate(endOfMonth))
    .get();

  console.log(`Processing ${snapshot.size} cases for period ${period}...`);

  // Aggregate by category
  const stats = {};
  for (const cat of CATEGORIES) {
    stats[cat] = { totalReceived: 0, completedOnTime: 0, overdueCount: 0, totalProcessingMs: 0, resolvedCount: 0 };
  }

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const cat = data.serviceCategory || 'documents';
    if (!stats[cat]) continue;

    stats[cat].totalReceived++;

    const isResolved = ['released', 'rejected'].includes(data.status);
    if (isResolved && data.submissionTimestamp && data.lastUpdated) {
      const submitted = data.submissionTimestamp.toDate();
      const resolved = data.lastUpdated.toDate();
      const processingMs = resolved - submitted;
      stats[cat].totalProcessingMs += processingMs;
      stats[cat].resolvedCount++;
    }

    if (data.slaStatus === 'on_time' && isResolved) {
      stats[cat].completedOnTime++;
    }
    if (data.slaStatus === 'overdue') {
      stats[cat].overdueCount++;
    }
  }

  // Build byCategory array
  const byCategory = CATEGORIES.map(cat => {
    const s = stats[cat];
    const avgMs = s.resolvedCount > 0 ? s.totalProcessingMs / s.resolvedCount : 0;
    const avgHours = Math.round(avgMs / (1000 * 60 * 60));
    const complianceRate = s.totalReceived > 0
      ? Math.round((s.completedOnTime / s.totalReceived) * 100)
      : 0;

    return {
      category: CATEGORY_LABELS[cat],
      totalReceived: s.totalReceived,
      completedOnTime: s.completedOnTime,
      overdueCount: s.overdueCount,
      avgProcessingTime: avgHours,
      complianceRate,
    };
  });

  // Write snapshot
  await db.collection('complianceSnapshots').add({
    period,
    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    byCategory,
  });

  console.log(`Compliance snapshot for ${period} written successfully.`);
  byCategory.forEach(c => {
    if (c.totalReceived > 0) {
      console.log(`  ${c.category}: ${c.totalReceived} received, ${c.complianceRate}% compliance, ${c.overdueCount} overdue`);
    }
  });

  console.log(`[${new Date().toISOString()}] Compliance Snapshot finished.`);
}

main().catch(err => {
  console.error('Compliance Snapshot failed:', err);
  process.exit(1);
});
