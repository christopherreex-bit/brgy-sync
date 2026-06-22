/**
 * BrgySync — Distribution Reminder (Cloudflare Worker)
 * Cron: daily at 0:00 UTC (8AM PHT)
 * Secret: FIREBASE_SERVICE_ACCOUNT
 */

export default {
  async scheduled(controller, env, ctx) {
    try {
      const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);

      const { initializeApp, cert } = await import('firebase-admin/app');
      const { getFirestore } = await import('firebase-admin/firestore');

      const app = initializeApp({ credential: cert(sa) }, 'cron-' + Date.now());
      const db = getFirestore(app);

      const now = new Date();
      const sevenDaysFromNow = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

      const snapshot = await db.collection('distributions')
        .where('status', 'in', ['pending', 'confirmed'])
        .where('scheduledDate', '>=', now)
        .where('scheduledDate', '<=', sevenDaysFromNow)
        .get();

      let flagged = 0;
      const batch = db.batch();

      for (const doc of snapshot.docs) {
        const data = doc.data();
        if (!data.reminderFlag) {
          const scheduled = data.scheduledDate?.toDate?.() || now;
          const daysUntil = Math.round((scheduled - now) / 86400000);

          batch.update(doc.ref, {
            reminderFlag: true,
            reminderNote: `Upcoming: ${daysUntil} day(s) until scheduled release (${data.programType || 'program'})`,
            lastReminderSent: new Date(),
          });
          flagged++;
          console.log(`  Flagged: ${data.beneficiaryName} (${data.programType}) — ${daysUntil} days`);
        }
      }

      if (flagged > 0) await batch.commit();
      console.log(`Distribution Reminder: ${snapshot.size} upcoming, ${flagged} flagged`);
    } catch (err) {
      console.error('Distribution Reminder failed:', err);
    }
  },

  async fetch(request, env) {
    return new Response('Distribution Reminder Worker — triggered by cron schedule');
  }
};
