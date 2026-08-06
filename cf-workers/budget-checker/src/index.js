/**
 * BrgySync — Budget Health Checker (Cloudflare Worker)
 * Cron: daily at 0:00 UTC (8AM PHT)
 * Secret: FIREBASE_SERVICE_ACCOUNT
 */

function computeBudgetStatus(program) {
  const allocated = Number(program.allocated?.doubleValue ?? program.allocated?.integerValue ?? 0);
  const utilized = Number(program.utilized?.doubleValue ?? program.utilized?.integerValue ?? 0);
  const remaining = Number(program.remaining?.doubleValue ?? program.remaining?.integerValue ?? (allocated - utilized));
  const thresholdPercent = Number(program.thresholdPercent?.doubleValue ?? program.thresholdPercent?.integerValue ?? 10);
  const thresholdAmount = allocated * (thresholdPercent / 100);
  const criticalAmount = allocated * 0.10;

  if (remaining <= criticalAmount) return 'critical';
  if (remaining <= thresholdAmount) return 'low';
  return 'healthy';
}

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

async function listFirestoreDocs(token, projectId, collection) {
  const documents = [];
  let pageToken = '';
  do {
    const params = new URLSearchParams({ pageSize: '300' });
    if (pageToken) params.set('pageToken', pageToken);
    const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}?${params}`;
    const res = await fetch(url, {
      headers: { 'Authorization': `Bearer ${token}` },
    });
    if (!res.ok) throw new Error(`Could not list ${collection}: ${res.status} ${await res.text()}`);
    const data = await res.json();
    documents.push(...(data.documents || []));
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return documents;
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

async function createFirestoreDoc(token, projectId, collection, docId, fields) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}?documentId=${encodeURIComponent(docId)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (res.status === 200) return true;
  if (res.status === 409) return false;
  throw new Error(`Could not create ${collection}/${docId}: ${res.status} ${await res.text()}`);
}

const str = value => ({ stringValue: String(value ?? '') });
const array = values => ({ arrayValue: { values: values.map(str) } });

export default {
  async scheduled(controller, env, ctx) {
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const projectId = sa.project_id;
    const token = await getAccessToken(sa);

    const docs = await listFirestoreDocs(token, projectId, 'budgetPrograms');
    let updated = 0;
    let notifications = 0;
    const now = new Date();
    const manilaParts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(now).filter(part => part.type !== 'literal').map(part => [part.type, part.value]));
    const manilaDate = `${manilaParts.year}${manilaParts.month}${manilaParts.day}`;
    const currentFiscalYear = Number(manilaParts.year);
    const currentQuarter = Math.floor((Number(manilaParts.month) - 1) / 3) + 1;

    for (const doc of docs) {
      const f = doc.fields;
      const newStatus = computeBudgetStatus(f);
      const currentStatus = f.status?.stringValue;
      const allocated = Number(f.allocated?.doubleValue ?? f.allocated?.integerValue ?? 0);
      const utilized = Number(f.utilized?.doubleValue ?? f.utilized?.integerValue ?? 0);
      const reserved = Number(f.reserved?.doubleValue ?? f.reserved?.integerValue ?? 0);
      const remaining = Number(f.remaining?.doubleValue ?? f.remaining?.integerValue ?? (allocated - utilized - reserved));
      const imbalance = Math.abs(allocated - utilized - reserved - remaining);
      const docId = doc.name.split('/').pop();
      const fiscalYear = Number(f.fiscalYear?.integerValue ?? f.fiscalYear?.doubleValue ?? 0);
      const quarter = Number(f.quarter?.integerValue ?? f.quarter?.doubleValue ?? 0);
      const isCurrentQuarter = fiscalYear === currentFiscalYear && quarter === currentQuarter;

      if (currentStatus !== newStatus) {
        await patchFirestoreDoc(token, projectId, `budgetPrograms/${docId}`, {
          status: { stringValue: newStatus },
          lastUpdated: { timestampValue: new Date().toISOString() },
        });
        updated++;
        console.log(`  ${f.name?.stringValue || docId}: ${currentStatus || '(none)'} → ${newStatus}`);
      }

      if (isCurrentQuarter && (newStatus === 'low' || newStatus === 'critical' || imbalance > 0.01)) {
        const programName = f.name?.stringValue || docId;
        const reasons = [];
        if (newStatus === 'critical') reasons.push('budget is critical');
        else if (newStatus === 'low') reasons.push('budget is low');
        if (imbalance > 0.01) reasons.push(`records are out of balance by ₱${imbalance.toFixed(2)}`);
        if (await createFirestoreDoc(
          token, projectId, 'staffNotifications', `budget_${docId}_${manilaDate}`, {
            caseId: str(''),
            referenceNumber: str(''),
            type: str('budget_alert'),
            title: str(imbalance > 0.01 ? 'Budget reconciliation required' : 'Budget health alert'),
            message: str(`${programName}: ${reasons.join(' and ')}. Available balance: ₱${remaining.toFixed(2)}.`),
            recipientId: str(''),
            targetRoles: array(['captain']),
            priority: str(newStatus === 'critical' || imbalance > 0.01 ? 'urgent' : 'high'),
            readBy: array([]),
            createdAt: { timestampValue: now.toISOString() },
          },
        )) notifications++;
      }
    }

    console.log(`Budget Checker: ${docs.length} programs checked, ${updated} updated, ${notifications} captain alerts created`);
  },

  async fetch(request, env) {
    return new Response('Budget Checker Worker — triggered by cron schedule');
  }
};
