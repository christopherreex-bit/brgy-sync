/**
 * BrgySync — Monthly Compliance Snapshot (Cloudflare Worker)
 * Cron: monthly on 1st at 0:00 UTC
 * Secret: FIREBASE_SERVICE_ACCOUNT
 */

const CATEGORIES = ['bass', 'documents', 'community', 'beneficiary', 'vaw', 'education', 'adhoc'];
const CATEGORY_LABELS = {
  bass: 'BASS Assistance', documents: 'Barangay Documents', community: 'Community Services',
  beneficiary: 'Beneficiary Registration', vaw: 'VAW / BCPC', education: 'Education Incentive',
  adhoc: 'Ad Hoc / Special Program',
};

function b64url(buf) {
  return btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function getAccessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claim = b64url(new TextEncoder().encode(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  })));
  const input = `${header}.${claim}`;
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\n/g, '');
  const keyBuf = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', keyBuf,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = b64url(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(input)));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${input}.${sig}`,
  });
  const data = await res.json();
  return data.access_token;
}

async function queryFirestore(token, projectId, collection, fieldFilters) {
  const filters = fieldFilters.map(f => ({
    fieldFilter: { field: { fieldPath: f.field }, op: f.op || 'EQUAL', value: f.value }
  }));
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: collection }],
          where: filters.length > 0 ? { compositeFilter: { op: 'AND', filters } } : undefined,
        },
      }),
    }
  );
  return res.json();
}

async function addFirestoreDoc(token, projectId, collection, fields) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}`,
    {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields }),
    }
  );
  return res.status === 200;
}

function tsToDate(ts) {
  if (!ts) return new Date();
  if (ts.timestampValue) return new Date(ts.timestampValue);
  return new Date();
}

export default {
  async scheduled(controller, env, ctx) {
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const projectId = sa.project_id;
    const token = await getAccessToken(sa);

    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    const period = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

    // Check if snapshot already exists
    const existing = await queryFirestore(token, projectId, 'complianceSnapshots', [
      { field: 'period', value: { stringValue: period } },
    ]);
    if (existing.length > 0 && existing[0].document) {
      console.log(`Compliance snapshot for ${period} already exists. Skipping.`);
      return;
    }

    // Fetch all cases this month
    const result = await queryFirestore(token, projectId, 'cases', [
      { field: 'submissionTimestamp', op: 'GREATER_THAN_OR_EQUAL', value: { timestampValue: startOfMonth.toISOString() } },
      { field: 'submissionTimestamp', op: 'LESS_THAN', value: { timestampValue: endOfMonth.toISOString() } },
    ]);

    const stats = {};
    for (const cat of CATEGORIES) {
      stats[cat] = { totalReceived: 0, completedOnTime: 0, overdueCount: 0, totalProcessingMs: 0, resolvedCount: 0 };
    }

    for (const entry of result) {
      if (!entry.document) continue;
      const f = entry.document.fields;
      const cat = f.serviceCategory?.stringValue || 'documents';
      if (!stats[cat]) continue;

      stats[cat].totalReceived++;
      const isResolved = ['released', 'rejected'].includes(f.status?.stringValue);

      if (isResolved && f.submissionTimestamp && f.lastUpdated) {
        const submitted = tsToDate(f.submissionTimestamp);
        const resolved = tsToDate(f.lastUpdated);
        stats[cat].totalProcessingMs += (resolved - submitted);
        stats[cat].resolvedCount++;
      }
      if (f.slaStatus?.stringValue === 'on_time' && isResolved) stats[cat].completedOnTime++;
      if (f.slaStatus?.stringValue === 'overdue') stats[cat].overdueCount++;
    }

    const byCategory = CATEGORIES.map(cat => {
      const s = stats[cat];
      const avgHours = s.resolvedCount > 0 ? Math.round(s.totalProcessingMs / s.resolvedCount / 3600000) : 0;
      const complianceRate = s.totalReceived > 0 ? Math.round((s.completedOnTime / s.totalReceived) * 100) : 0;
      return {
        category: { stringValue: CATEGORY_LABELS[cat] },
        totalReceived: { integerValue: s.totalReceived },
        completedOnTime: { integerValue: s.completedOnTime },
        overdueCount: { integerValue: s.overdueCount },
        avgProcessingTime: { integerValue: avgHours },
        complianceRate: { integerValue: complianceRate },
      };
    });

    await addFirestoreDoc(token, projectId, 'complianceSnapshots', {
      period: { stringValue: period },
      generatedAt: { timestampValue: now.toISOString() },
      byCategory: { arrayValue: { values: byCategory.map(c => ({ mapValue: { fields: c } })) } },
    });

    console.log(`Compliance Snapshot for ${period} written. ${result.length || 0} cases processed.`);
  },

  async fetch(request, env) {
    return new Response('Compliance Snapshot Worker — triggered by cron schedule');
  }
};
