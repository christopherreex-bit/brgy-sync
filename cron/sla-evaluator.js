/**
 * BrgySync — SLA Evaluator Cron Script
 *
 * Queries all active (non-resolved/non-rejected) cases and recomputes
 * their SLA status (on_time / near_deadline / overdue).
 *
 * Run frequency: every 15 minutes via Cron-job.org
 *
 * Required env var:
 *   FIREBASE_SERVICE_ACCOUNT — stringified Firebase Admin service account JSON
 */

const admin = require('firebase-admin');

// ─── Firebase Init ────────────────────────────────────────────────
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// ─── Philippine Holidays (2026, fixed dates) ──────────────────────
const PH_HOLIDAYS_2026 = new Set([
  '2026-01-01','2026-02-25','2026-04-09','2026-04-16','2026-04-17',
  '2026-05-01','2026-06-12','2026-08-21','2026-08-31','2026-11-01',
  '2026-11-30','2026-12-08','2026-12-25','2026-12-30','2026-12-31',
]);

// ─── SLA Defaults (mirrors kSlaDefaults from Flutter) ─────────────
const SLA_DEFAULTS = {
  documents:      { value: 15, unit: 'minutes' },
  bass_standard:  { value: 3,  unit: 'working_days' },
  bass_medical:   { value: 5,  unit: 'working_days' },
  vaw:            { value: 1,  unit: 'working_days' },
  community:      { value: 3,  unit: 'working_days' },
  beneficiary:    { value: 3,  unit: 'working_days' },
  education:      { value: 5,  unit: 'working_days' },
  adhoc:          { value: 5,  unit: 'working_days' },
};

function slaKeyFor(category, subType) {
  if (category === 'bass') {
    const medical = ['Medical – Dialysis', 'Medical – Chemotherapy', 'Medical – Major Operations'];
    return medical.includes(subType) ? 'bass_medical' : 'bass_standard';
  }
  const map = { documents: 'documents', vaw: 'vaw', community: 'community',
                beneficiary: 'beneficiary', education: 'education', adhoc: 'adhoc' };
  return map[category] || 'documents';
}

function computeDeadline(submittedMs, category, subType) {
  const slaKey = slaKeyFor(category, subType);
  const sla = SLA_DEFAULTS[slaKey] || SLA_DEFAULTS.documents;

  if (sla.unit === 'minutes') {
    return new Date(submittedMs + sla.value * 60 * 1000);
  }

  // Working days: Mon–Fri, skip PH holidays
  const current = new Date(submittedMs);
  let daysAdded = 0;
  while (daysAdded < sla.value) {
    current.setDate(current.getDate() + 1);
    const dow = current.getUTCDay();
    if (dow === 0 || dow === 6) continue; // Sat/Sun
    const key = current.toISOString().slice(0, 10);
    if (PH_HOLIDAYS_2026.has(key)) continue;
    daysAdded++;
  }
  return current;
}

function computeSLAStatus(deadline) {
  const now = new Date();
  const diffMs = deadline - now;
  if (diffMs < 0) return 'overdue';
  if (diffMs < 24 * 60 * 60 * 1000) return 'near_deadline';
  return 'on_time';
}

// ─── Main ─────────────────────────────────────────────────────────
async function main() {
  console.log(`[${new Date().toISOString()}] SLA Evaluator started`);

  // Fetch all active cases (not released, not rejected)
  const snapshot = await db
    .collection('cases')
    .where('status', 'in', ['pending_review', 'processing', 'awaiting_docs', 'approved'])
    .get();

  if (snapshot.empty) {
    console.log('No active cases found. Exiting.');
    process.exit(0);
  }

  console.log(`Processing ${snapshot.size} active cases...`);
  let updated = 0;
  const batch = db.batch();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const submitted = data.submissionTimestamp?.toDate
      ? data.submissionTimestamp.toDate().getTime()
      : Date.now();

    const deadline = computeDeadline(submitted, data.serviceCategory || 'documents', data.serviceSubType || '');
    const slaStatus = computeSLAStatus(deadline);

    // Only write back if status changed or deadline is missing
    if (data.slaStatus !== slaStatus || !data.slaDeadline) {
      batch.update(doc.ref, {
        slaStatus,
        slaDeadline: admin.firestore.Timestamp.fromDate(deadline),
      });
      updated++;
    }
  }

  if (updated > 0) {
    await batch.commit();
    console.log(`Updated ${updated} case(s) with new SLA status.`);
  } else {
    console.log('All cases already up to date.');
  }

  console.log(`[${new Date().toISOString()}] SLA Evaluator finished.`);
}

main().catch(err => {
  console.error('SLA Evaluator failed:', err);
  process.exit(1);
});
