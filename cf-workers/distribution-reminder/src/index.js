/**
 * BrgySync — Distribution Reminder (Cloudflare Worker)
 * Cron: daily at 0:00 UTC (8AM PHT)
 * Secret: FIREBASE_SERVICE_ACCOUNT
 */

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
          where: { compositeFilter: { op: 'AND', filters } },
        },
      }),
    }
  );
  return res.json();
}

async function patchFirestoreDoc(token, projectId, docPath, fields) {
  const mask = Object.keys(fields).join('&updateMask.fieldPaths=');
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}?updateMask.fieldPaths=${mask}`,
    {
      method: 'PATCH',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields }),
    }
  );
  return res.status === 200;
}

export default {
  async scheduled(controller, env, ctx) {
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const projectId = sa.project_id;
    const token = await getAccessToken(sa);

    const now = new Date();
    const sevenDays = new Date(now.getTime() + 7 * 86400000);

    const result = await queryFirestore(token, projectId, 'distributions', [
      { field: 'status', op: 'IN', value: { arrayValue: { values: [
        { stringValue: 'pending' }, { stringValue: 'confirmed' }
      ]}}},
      { field: 'scheduledDate', op: 'GREATER_THAN_OR_EQUAL', value: { timestampValue: now.toISOString() } },
      { field: 'scheduledDate', op: 'LESS_THAN_OR_EQUAL', value: { timestampValue: sevenDays.toISOString() } },
    ]);

    let flagged = 0;

    for (const entry of result) {
      if (!entry.document) continue;
      const f = entry.document.fields;
      if (!f.reminderFlag?.booleanValue) {
        const scheduled = f.scheduledDate?.timestampValue ? new Date(f.scheduledDate.timestampValue) : now;
        const daysUntil = Math.round((scheduled - now) / 86400000);
        const docId = entry.document.name.split('/').pop();
        await patchFirestoreDoc(token, projectId, `distributions/${docId}`, {
          reminderFlag: { booleanValue: true },
          reminderNote: { stringValue: `Upcoming: ${daysUntil} day(s) until scheduled release (${f.programType?.stringValue || 'program'})` },
          lastReminderSent: { timestampValue: now.toISOString() },
        });
        flagged++;
        console.log(`  Flagged: ${f.beneficiaryName?.stringValue || docId} — ${daysUntil} days`);
      }
    }

    console.log(`Distribution Reminder: ${result.length || 0} upcoming, ${flagged} flagged`);
  },

  async fetch(request, env) {
    return new Response('Distribution Reminder Worker — triggered by cron schedule');
  }
};
