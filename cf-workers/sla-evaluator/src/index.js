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

async function createFirestoreDoc(token, projectId, collection, docId, fields) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}?documentId=${encodeURIComponent(docId)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  // A deterministic ID makes every reminder idempotent. HTTP 409 means the
  // reminder was already created by an earlier cron run.
  if (res.status === 200) return true;
  if (res.status === 409) return false;
  throw new Error(`Could not create ${collection}/${docId}: ${res.status} ${await res.text()}`);
}

const str = value => ({ stringValue: String(value ?? '') });
const bool = value => ({ booleanValue: Boolean(value) });
const array = values => ({ arrayValue: { values: values.map(str) } });

function fieldString(fields, name) {
  return fields[name]?.stringValue || '';
}

function fieldBool(fields, name) {
  return fields[name]?.booleanValue === true;
}

async function createResidentNotification(token, projectId, id, caseId, fields, title, message, type) {
  const residentId = fieldString(fields, 'residentId');
  if (!residentId) return false;
  return createFirestoreDoc(token, projectId, 'notifications', id, {
    residentId: str(residentId),
    caseId: str(caseId),
    referenceNumber: str(fieldString(fields, 'referenceNumber')),
    type: str(type),
    title: str(title),
    message: str(message),
    isRead: bool(false),
    createdAt: dateToTs(new Date()),
  });
}

async function createStaffNotification(token, projectId, id, caseId, fields, title, message, type, options = {}) {
  return createFirestoreDoc(token, projectId, 'staffNotifications', id, {
    caseId: str(caseId),
    referenceNumber: str(fieldString(fields, 'referenceNumber')),
    type: str(type),
    title: str(title),
    message: str(message),
    recipientId: str(options.recipientId || ''),
    targetRoles: array(options.targetRoles || []),
    priority: str(options.priority || 'normal'),
    readBy: array([]),
    createdAt: dateToTs(new Date()),
  });
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

    // One collection scan handles SLA evaluation and all reminder types. This
    // avoids multiple composite indexes and keeps reminder generation atomic
    // through deterministic notification IDs.
    const result = await queryFirestore(token, projectId, 'cases', []);

    let updated = 0;
    let notificationsCreated = 0;
    const now = new Date();
    const activeCases = [];

    for (const entry of result) {
      if (!entry.document) continue;
      const doc = entry.document;
      const f = doc.fields;
      const docId = doc.name.split('/').pop();
      const status = fieldString(f, 'status') === 'pending'
        ? 'pending_review'
        : fieldString(f, 'status');
      const submitted = tsToDate(f.submissionTimestamp).getTime();
      const category = f.serviceCategory?.stringValue || 'documents';
      const subType = f.serviceSubType?.stringValue || '';
      if (ACTIVE_STATUSES.includes(status)) {
        // Respect the deadline calculated by the Flutter app from SLA
        // Configuration. Defaults are used only for legacy cases that have no
        // stored deadline.
        const deadline = f.slaDeadline
          ? tsToDate(f.slaDeadline)
          : computeDeadline(submitted, category, subType);
        const slaStatus = computeSLAStatus(deadline);
        const currentStatus = f.slaStatus?.stringValue;
        activeCases.push({ docId, fields: f, status, deadline, slaStatus });

        if (currentStatus !== slaStatus || !f.slaDeadline) {
          await patchFirestoreDoc(token, projectId, `cases/${docId}`, {
            slaStatus: { stringValue: slaStatus },
            slaDeadline: dateToTs(deadline),
          });
          updated++;
        }

        const totalMs = Math.max(1, deadline.getTime() - submitted);
        const progress = (now.getTime() - submitted) / totalMs * 100;
        const threshold = progress >= 100 ? 'overdue'
          : progress >= 90 ? '90'
          : progress >= 75 ? '75'
          : progress >= 50 ? '50'
          : null;
        if (threshold) {
          const assignedId = fieldString(f, 'assignedStaffId');
          const label = threshold === 'overdue' ? 'overdue' : `${threshold}% of its SLA`;
          if (await createStaffNotification(
            token, projectId, `sla_${docId}_${threshold}`, docId, f,
            threshold === 'overdue' ? 'Case is overdue' : 'Case is nearing its SLA deadline',
            `${fieldString(f, 'referenceNumber')} has reached ${label}.`,
            'sla_reminder',
            assignedId
              ? { recipientId: assignedId, priority: threshold === 'overdue' ? 'urgent' : 'high' }
              : { targetRoles: ['officer', 'captain'], priority: 'high' },
          )) notificationsCreated++;
        }
      }

      // For Claiming reminders: the resident receives one reminder seven days
      // before expiry and another one day before expiry.
      if (status === 'for_claiming' && f.claimingApprovedAt) {
        const approvedAt = tsToDate(f.claimingApprovedAt);
        const claimingDeadline = new Date(approvedAt.getTime() + 30 * 86400000);
        const daysRemaining = Math.ceil((claimingDeadline.getTime() - now.getTime()) / 86400000);
        const reminderDay = daysRemaining <= 1 && daysRemaining >= 0 ? 1
          : daysRemaining <= 7 && daysRemaining > 1 ? 7
          : null;
        if (reminderDay && await createResidentNotification(
          token, projectId, `claiming_${docId}_${reminderDay}d`, docId, f,
          'Claiming deadline reminder',
          `Your assistance for ${fieldString(f, 'referenceNumber')} must be claimed within ${reminderDay} day${reminderDay === 1 ? '' : 's'}.`,
          'claiming_reminder',
        )) notificationsCreated++;
      }

      // Document correction reminders at 3, 7, and 14 days. Starting on day
      // 7, the assigned employee (or officers/captain if unassigned) is also
      // alerted so the case does not silently stall.
      if (fieldBool(f, 'residentActionRequired') && f.correctionRequestedAt) {
        const correctionAge = Math.floor((now.getTime() - tsToDate(f.correctionRequestedAt).getTime()) / 86400000);
        const reminderDay = correctionAge >= 14 ? 14 : correctionAge >= 7 ? 7 : correctionAge >= 3 ? 3 : null;
        if (reminderDay && await createResidentNotification(
          token, projectId, `correction_${docId}_${reminderDay}d`, docId, f,
          'Document replacement reminder',
          `${fieldString(f, 'referenceNumber')} is waiting for your replacement document. Open My Cases to upload it.`,
          'document_correction_reminder',
        )) notificationsCreated++;
        if (reminderDay && reminderDay >= 7) {
          const assignedId = fieldString(f, 'assignedStaffId');
          if (await createStaffNotification(
            token, projectId, `correction_staff_${docId}_${reminderDay}d`, docId, f,
            'Resident correction still pending',
            `${fieldString(f, 'referenceNumber')} has been waiting ${reminderDay} days for replacement documents.`,
            'correction_escalation',
            assignedId ? { recipientId: assignedId, priority: 'high' }
              : { targetRoles: ['officer', 'captain'], priority: 'high' },
          )) notificationsCreated++;
        }
      }
    }

    // Daily Barangay Captain digest at 8 AM Asia/Manila. A date-based ID
    // prevents duplicates if several 15-minute cron invocations overlap.
    const manilaParts = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23',
    }).formatToParts(now).reduce((map, part) => ({ ...map, [part.type]: part.value }), {});
    if (manilaParts.hour === '08') {
      const dateKey = `${manilaParts.year}${manilaParts.month}${manilaParts.day}`;
      const pendingApprovals = result.filter(e => e.document?.fields?.claimingApprovalStatus?.stringValue === 'pending').length;
      const overdue = activeCases.filter(c => c.slaStatus === 'overdue').length;
      const unassigned = activeCases.filter(c => !fieldString(c.fields, 'assignedStaffId')).length;
      const corrections = result.filter(e => e.document && fieldBool(e.document.fields, 'residentActionRequired')).length;
      if (await createStaffNotification(
        token, projectId, `captain_digest_${dateKey}`, '', {},
        'Daily operations digest',
        `${pendingApprovals} claiming approvals, ${overdue} overdue cases, ${unassigned} unassigned cases, and ${corrections} resident corrections pending.`,
        'captain_digest',
        { targetRoles: ['captain'], priority: overdue > 0 ? 'high' : 'normal' },
      )) notificationsCreated++;
    }

    console.log(`Automation worker: ${result.length || 0} cases checked, ${updated} SLA updates, ${notificationsCreated} notifications created`);
  },

  async fetch(request, env) {
    return new Response('BrgySync Automation Worker — triggered by cron schedule');
  }
};
