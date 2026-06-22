/**
 * BrgySync — SLA Evaluator (Cloudflare Worker)
 * Cron: every 15 minutes
 * Secret: FIREBASE_SERVICE_ACCOUNT
 *
 * Uses Firestore REST API (no firebase-admin dependency).
 */

const ACTIVE_STATUSES = ['pending_review', 'processing', 'awaiting_docs', 'approved'];

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
  const diff = deadline.getTime() - Date.now();
  if (diff < 0) return 'overdue';
  if (diff < 86400000) return 'near_deadline';
  return 'on_time';
}

// ─── JWT Auth ──────────────────────────────────────────────────────
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

// ─── Firestore REST helpers ────────────────────────────────────────
async function queryFirestore(token, projectId, collection, fieldFilters) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;
  const filters = fieldFilters.map(f => ({
    fieldFilter: { field: { fieldPath: f.field }, op: f.op || 'EQUAL', value: f.value }
  }));
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: collection }],
        where: filters.length > 0 ? { compositeFilter: { op: 'AND', filters } } : undefined,
      },
    }),
  });
  return res.json();
}

async function patchFirestoreDoc(token, projectId, docPath, fields) {
  const mask = Object.keys(fields).join('&updateMask.fieldPaths=');
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}?updateMask.fieldPaths=${mask}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  return res.status === 200;
}

function tsToDate(ts) {
  if (!ts) return new Date();
  if (ts.timestampValue) return new Date(ts.timestampValue);
  if (ts.stringValue) return new Date(ts.stringValue);
  return new Date();
}

function dateToTs(d) {
  return { timestampValue: d.toISOString() };
}

// ─── Main ──────────────────────────────────────────────────────────
export default {
  async scheduled(controller, env, ctx) {
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const projectId = sa.project_id;
    const token = await getAccessToken(sa);

    // Query active cases with IN filter
    const result = await queryFirestore(token, projectId, 'cases', [{
      field: 'status',
      op: 'IN',
      value: { arrayValue: { values: ACTIVE_STATUSES.map(s => ({ stringValue: s })) } },
    }]);

    let updated = 0;

    for (const entry of result) {
      if (!entry.document) continue;
      const doc = entry.document;
      const f = doc.fields;
      const submitted = tsToDate(f.submissionTimestamp).getTime();
      const category = f.serviceCategory?.stringValue || 'documents';
      const subType = f.serviceSubType?.stringValue || '';
      const deadline = computeDeadline(submitted, category, subType);
      const slaStatus = computeSLAStatus(deadline);
      const currentStatus = f.slaStatus?.stringValue;

      if (currentStatus !== slaStatus || !f.slaDeadline) {
        const docId = doc.name.split('/').pop();
        await patchFirestoreDoc(token, projectId, `cases/${docId}`, {
          slaStatus: { stringValue: slaStatus },
          slaDeadline: dateToTs(deadline),
        });
        updated++;
      }
    }

    console.log(`SLA Evaluator: ${result.length || 0} cases checked, ${updated} updated`);
  },

  async fetch(request, env) {
    return new Response('SLA Evaluator Worker — triggered by cron schedule');
  }
};
