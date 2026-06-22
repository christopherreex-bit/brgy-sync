/**
 * BrgySync — Budget Health Checker (Cloudflare Worker)
 * Cron: daily at 0:00 UTC (8AM PHT)
 * Secret: FIREBASE_SERVICE_ACCOUNT
 */

function computeBudgetStatus(program) {
  const allocated = Number(program.allocated) || 0;
  const remaining = Number(program.remaining) ?? (allocated - Number(program.utilized || 0));
  const thresholdPercent = Number(program.thresholdPercent) || 10;
  const thresholdAmount = allocated * (thresholdPercent / 100);
  const criticalAmount = allocated * 0.10;

  if (remaining <= criticalAmount) return 'critical';
  if (remaining <= thresholdAmount) return 'low';
  return 'healthy';
}

export default {
  async scheduled(controller, env, ctx) {
    try {
      const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);

      const { initializeApp, cert } = await import('firebase-admin/app');
      const { getFirestore } = await import('firebase-admin/firestore');

      const app = initializeApp({ credential: cert(sa) }, 'cron-' + Date.now());
      const db = getFirestore(app);

      const snapshot = await db.collection('budgetPrograms').get();
      let updated = 0;
      const batch = db.batch();

      for (const doc of snapshot.docs) {
        const program = doc.data();
        const newStatus = computeBudgetStatus(program);

        if (program.status !== newStatus) {
          batch.update(doc.ref, {
            status: newStatus,
            lastUpdated: new Date(),
          });
          updated++;
          console.log(`  ${program.name}: ${program.status || '(none)'} → ${newStatus}`);
        }
      }

      if (updated > 0) await batch.commit();
      console.log(`Budget Checker: ${snapshot.size} programs checked, ${updated} updated`);
    } catch (err) {
      console.error('Budget Checker failed:', err);
    }
  },

  async fetch(request, env) {
    return new Response('Budget Checker Worker — triggered by cron schedule');
  }
};
