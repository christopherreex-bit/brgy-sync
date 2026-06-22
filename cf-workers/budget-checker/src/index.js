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
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}`;
  const res = await fetch(url, {
    headers: { 'Authorization': `Bearer ${token}` },
  });
  const data = await res.json();
  return data.documents || [];
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

export default {
  async scheduled(controller, env, ctx) {
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const projectId = sa.project_id;
    const token = await getAccessToken(sa);

    const docs = await listFirestoreDocs(token, projectId, 'budgetPrograms');
    let updated = 0;

    for (const doc of docs) {
      const f = doc.fields;
      const newStatus = computeBudgetStatus(f);
      const currentStatus = f.status?.stringValue;

      if (currentStatus !== newStatus) {
        const docId = doc.name.split('/').pop();
        await patchFirestoreDoc(token, projectId, `budgetPrograms/${docId}`, {
          status: { stringValue: newStatus },
          lastUpdated: { timestampValue: new Date().toISOString() },
        });
        updated++;
        console.log(`  ${f.name?.stringValue || docId}: ${currentStatus || '(none)'} → ${newStatus}`);
      }
    }

    console.log(`Budget Checker: ${docs.length} programs checked, ${updated} updated`);
  },

  async fetch(request, env) {
    return new Response('Budget Checker Worker — triggered by cron schedule');
  }
};
