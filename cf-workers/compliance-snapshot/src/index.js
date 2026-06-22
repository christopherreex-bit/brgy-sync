/**
 * BrgySync — Monthly Compliance Snapshot (Cloudflare Worker)
 * Cron: monthly on 1st at 0:00 UTC
 * Secret: FIREBASE_SERVICE_ACCOUNT
 */

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

export default {
  async scheduled(controller, env, ctx) {
    try {
      const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);

      const { initializeApp, cert } = await import('firebase-admin/app');
      const { getFirestore } = await import('firebase-admin/firestore');

      const app = initializeApp({ credential: cert(sa) }, 'cron-' + Date.now());
      const db = getFirestore(app);

      const now = new Date();
      const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
      const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
      const period = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

      // Check if snapshot already exists
      const existing = await db.collection('complianceSnapshots')
        .where('period', '==', period)
        .limit(1)
        .get();

      if (!existing.empty) {
        console.log(`Compliance snapshot for ${period} already exists. Skipping.`);
        return;
      }

      // Fetch all cases submitted this month
      const snapshot = await db.collection('cases')
        .where('submissionTimestamp', '>=', startOfMonth)
        .where('submissionTimestamp', '<', endOfMonth)
        .get();

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
          const submitted = data.submissionTimestamp.toDate?.() || new Date();
          const resolved = data.lastUpdated.toDate?.() || new Date();
          stats[cat].totalProcessingMs += (resolved - submitted);
          stats[cat].resolvedCount++;
        }

        if (data.slaStatus === 'on_time' && isResolved) stats[cat].completedOnTime++;
        if (data.slaStatus === 'overdue') stats[cat].overdueCount++;
      }

      const byCategory = CATEGORIES.map(cat => {
        const s = stats[cat];
        const avgHours = s.resolvedCount > 0 ? Math.round(s.totalProcessingMs / s.resolvedCount / 3600000) : 0;
        const complianceRate = s.totalReceived > 0 ? Math.round((s.completedOnTime / s.totalReceived) * 100) : 0;
        return {
          category: CATEGORY_LABELS[cat],
          totalReceived: s.totalReceived,
          completedOnTime: s.completedOnTime,
          overdueCount: s.overdueCount,
          avgProcessingTime: avgHours,
          complianceRate,
        };
      });

      await db.collection('complianceSnapshots').add({
        period,
        generatedAt: new Date(),
        byCategory,
      });

      console.log(`Compliance Snapshot for ${period} written. ${snapshot.size} cases processed.`);
    } catch (err) {
      console.error('Compliance Snapshot failed:', err);
    }
  },

  async fetch(request, env) {
    return new Response('Compliance Snapshot Worker — triggered by cron schedule');
  }
};
