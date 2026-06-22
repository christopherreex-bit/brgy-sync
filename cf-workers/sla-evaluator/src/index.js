/**
 * BrgySync — SLA Evaluator (Cloudflare Worker)
 * Cron: every 15 minutes
 * Secret: FIREBASE_SERVICE_ACCOUNT
 */

function getAdmin() {
  // Dynamic import to avoid issues if module isn't available
  return import('firebase-admin/app');
}

function getFirestore() {
  return import('firebase-admin/firestore');
}

const PH_HOLIDAYS_2026 = new Set([
  '2026-01-01','2026-02-25','2026-04-09','2026-04-16','2026-04-17',
  '2026-05-01','2026-06-12','2026-08-21','2026-08-31','2026-11-01',
  '2026-11-30','2026-12-08','2026-12-25','2026-12-30','2026-12-31',
]);

const SLA_DEFAULTS = {
  documents:     { value: 15, unit: 'minutes' },
  bass_standard: { value: 3,  unit: 'working_days' },
  bass_medical:  { value: 5,  unit: 'working_days' },
  vaw:           { value: 1,  unit: 'working_days' },
  community:     { value: 3,  unit: 'working_days' },
  beneficiary:   { value: 3,  unit: 'working_days' },
  education:     { value: 5,  unit: 'working_days' },
  adhoc:         { value: 5,  unit: 'working_days' },
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
  const sla = SLA_DEFAULTS[slaKeyFor(category, subType)] || SLA_DEFAULTS.documents;
  if (sla.unit === 'minutes') return new Date(submittedMs + sla.value * 60 * 1000);
  const current = new Date(submittedMs);
  let daysAdded = 0;
  while (daysAdded < sla.value) {
    current.setDate(current.getDate() + 1);
    if (current.getUTCDay() === 0 || current.getUTCDay() === 6) continue;
    if (PH_HOLIDAYS_2026.has(current.toISOString().slice(0, 10))) continue;
    daysAdded++;
  }
  return current;
}

function computeSLAStatus(deadline) {
  const diff = deadline - Date.now();
  if (diff < 0) return 'overdue';
  if (diff < 86400000) return 'near_deadline';
  return 'on_time';
}

export default {
  async scheduled(controller, env, ctx) {
    try {
      const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);

      const { initializeApp, cert } = await import('firebase-admin/app');
      const { getFirestore } = await import('firebase-admin/firestore');

      const app = initializeApp({ credential: cert(sa) }, 'cron-' + Date.now());
      const db = getFirestore(app);

      const snapshot = await db.collection('cases')
        .where('status', 'in', ['pending_review', 'processing', 'awaiting_docs', 'approved'])
        .get();

      let updated = 0;
      const batch = db.batch();

      for (const doc of snapshot.docs) {
        const data = doc.data();
        const submitted = data.submissionTimestamp?.toDate?.() || new Date();
        const deadline = computeDeadline(submitted.getTime(), data.serviceCategory || 'documents', data.serviceSubType || '');
        const slaStatus = computeSLAStatus(deadline);

        if (data.slaStatus !== slaStatus || !data.slaDeadline) {
          batch.update(doc.ref, {
            slaStatus,
            slaDeadline: deadline,
          });
          updated++;
        }
      }

      if (updated > 0) await batch.commit();

      console.log(`SLA Evaluator: ${snapshot.size} cases checked, ${updated} updated`);
    } catch (err) {
      console.error('SLA Evaluator failed:', err);
    }
  },

  async fetch(request, env) {
    return new Response('SLA Evaluator Worker — triggered by cron schedule');
  }
};
