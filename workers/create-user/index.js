const PROJECT_ID = 'brg-sync';
const FIREBASE_API_KEY = 'AIzaSyADmhc_akaeGO0ZtVcYPGJXpAT7ttPpmwU';
const FIRESTORE_BASE =
  `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}` +
  '/databases/(default)/documents';

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }
    if (!['POST', 'DELETE'].includes(request.method)) {
      return jsonResponse({ error: 'Method not allowed.' }, 405);
    }

    const authHeader = request.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Unauthorized.' }, 401);
    }

    try {
      const callerIdToken = authHeader.slice('Bearer '.length);
      const callerUid = await verifyFirebaseIdToken(callerIdToken);
      const serviceAccount = parseServiceAccount(
        env.FIREBASE_SERVICE_ACCOUNT,
      );
      const accessToken = await getGoogleAccessToken(serviceAccount);
      const callerProfile = await getFirestoreUser(callerUid, accessToken);
      const callerRole = firestoreString(callerProfile, 'role');

      const body = await request.json();
      if (request.method === 'DELETE') {
        if (callerRole !== 'captain') {
          return jsonResponse(
            { error: 'Only the Barangay Captain can manage accounts.' },
            403,
          );
        }
        return deleteAccount(body, callerUid, accessToken);
      }
      const requestedRole = body?.role;
      const mayCreateResident =
        requestedRole === 'resident' &&
        ['staff', 'officer', 'captain'].includes(callerRole);
      const mayCreateManagedAccount =
        requestedRole !== 'resident' && callerRole === 'captain';
      if (!mayCreateResident && !mayCreateManagedAccount) {
        return jsonResponse(
          { error: 'You are not allowed to create this account type.' },
          403,
        );
      }
      return createAccount(body, accessToken, {
        callerUid,
        callerRole,
        isWalkInResident: requestedRole === 'resident',
      });
    } catch (error) {
      return jsonResponse(
        { error: error?.message || 'Account service request failed.' },
        400,
      );
    }
  },
};

async function deleteAccount(body, callerUid, accessToken) {
  const uid = body?.uid;
  if (!uid || typeof uid !== 'string') {
    return jsonResponse({ error: 'A target user ID is required.' }, 400);
  }
  if (uid === callerUid) {
    return jsonResponse(
      { error: 'Use self-service User Management to delete your own account.' },
      400,
    );
  }

  const targetProfile = await getFirestoreUser(uid, accessToken);
  const targetRole = firestoreString(targetProfile, 'role');
  const targetMobile = firestoreString(targetProfile, 'mobile');
  if (!['staff', 'officer', 'captain'].includes(targetRole)) {
    return jsonResponse(
      {
        error:
          'This admin page can delete only staff, officer, or captain accounts.',
      },
      400,
    );
  }

  const authDelete = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:delete`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ localId: uid }),
    },
  );
  if (!authDelete.ok) {
    const error = await responseError(authDelete);
    if (!error.includes('USER_NOT_FOUND')) throw new Error(error);
  }

  const profileDelete = await fetch(
    `${FIRESTORE_BASE}/users/${encodeURIComponent(uid)}`,
    {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${accessToken}` },
    },
  );
  if (!profileDelete.ok && profileDelete.status !== 404) {
    throw new Error(await responseError(profileDelete));
  }
  if (targetMobile) {
    const mobileDelete = await fetch(
      `${FIRESTORE_BASE}/mobileIdentifiers/${encodeURIComponent(targetMobile)}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${accessToken}` },
      },
    );
    if (!mobileDelete.ok && mobileDelete.status !== 404) {
      throw new Error(await responseError(mobileDelete));
    }
  }
  return jsonResponse({ success: true, uid });
}

async function createAccount(body, accessToken, caller) {
  const { email, password, name, mobile, role } = body ?? {};
  if (!email || !password || !name || !mobile || !role) {
    return jsonResponse({ error: 'Missing required fields.' }, 400);
  }
  if (!['resident', 'staff', 'officer', 'captain'].includes(role)) {
    return jsonResponse({ error: 'Invalid role.' }, 400);
  }

  const normalizedMobile = mobile.trim();
  const mobileInUse = await firestoreMobileExists(
    normalizedMobile,
    accessToken,
  );
  if (mobileInUse) {
    return jsonResponse({ error: 'This mobile number is already in use.' }, 409);
  }

  const signUp = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${FIREBASE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        password,
        displayName: name,
        returnSecureToken: false,
      }),
    },
  );
  if (!signUp.ok) throw new Error(await responseError(signUp));
  const created = await signUp.json();

  const profileWrite = await fetch(
    `${FIRESTORE_BASE}/users?documentId=${encodeURIComponent(created.localId)}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        fields: {
          name: { stringValue: name },
          mobile: { stringValue: normalizedMobile },
          email: { stringValue: email },
          role: { stringValue: role },
          isActive: { booleanValue: true },
          isSeedData: { booleanValue: false },
          createdAt: { timestampValue: new Date().toISOString() },
          ...(caller.isWalkInResident
            ? {
                mustChangePassword: { booleanValue: true },
                accountOrigin: { stringValue: 'walk_in' },
                createdBy: { stringValue: caller.callerUid },
                createdByRole: { stringValue: caller.callerRole },
              }
            : {}),
        },
      }),
    },
  );
  if (!profileWrite.ok) {
    await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:delete`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ localId: created.localId }),
      },
    );
    throw new Error(await responseError(profileWrite));
  }


  const mobileWrite = await fetch(
    `${FIRESTORE_BASE}/mobileIdentifiers?documentId=${encodeURIComponent(normalizedMobile)}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        fields: {
          uid: { stringValue: created.localId },
          createdAt: { timestampValue: new Date().toISOString() },
        },
      }),
    },
  );
  if (!mobileWrite.ok) {
    await fetch(
      `${FIRESTORE_BASE}/users/${encodeURIComponent(created.localId)}`,
      { method: 'DELETE', headers: { Authorization: `Bearer ${accessToken}` } },
    );
    await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:delete`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ localId: created.localId }),
      },
    );
    if (mobileWrite.status === 409) {
      throw new Error('This mobile number is already in use.');
    }
    throw new Error(await responseError(mobileWrite));
  }
  return jsonResponse(
    { success: true, uid: created.localId, email, role },
    201,
  );
}

async function firestoreMobileExists(mobile, accessToken) {
  const identifier = await fetch(
    `${FIRESTORE_BASE}/mobileIdentifiers/${encodeURIComponent(mobile)}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (identifier.ok) return true;
  if (identifier.status !== 404) throw new Error(await responseError(identifier));

  const query = await fetch(
    `${FIRESTORE_BASE}:runQuery`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: 'users' }],
          where: {
            fieldFilter: {
              field: { fieldPath: 'mobile' },
              op: 'EQUAL',
              value: { stringValue: mobile },
            },
          },
          limit: 1,
        },
      }),
    },
  );
  if (!query.ok) throw new Error(await responseError(query));
  const results = await query.json();
  return results.some((entry) => entry.document);
}

async function verifyFirebaseIdToken(idToken) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${FIREBASE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken }),
    },
  );
  if (!response.ok) throw new Error('Your session is invalid or expired.');
  const data = await response.json();
  const uid = data.users?.[0]?.localId;
  if (!uid) throw new Error('Your session is invalid or expired.');
  return uid;
}

async function getFirestoreUser(uid, accessToken) {
  const response = await fetch(
    `${FIRESTORE_BASE}/users/${encodeURIComponent(uid)}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (response.status === 404) throw new Error('Account profile not found.');
  if (!response.ok) throw new Error(await responseError(response));
  return response.json();
}

function firestoreString(document, field) {
  return document?.fields?.[field]?.stringValue ?? '';
}

function parseServiceAccount(rawValue) {
  const raw = rawValue?.trim() ?? '';
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT does not contain a valid JSON object.',
    );
  }
  return JSON.parse(raw.slice(start, end + 1));
}

async function getGoogleAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(
    new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })),
  );
  const claims = base64Url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: serviceAccount.client_email,
        scope:
          'https://www.googleapis.com/auth/cloud-platform ' +
          'https://www.googleapis.com/auth/datastore',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const unsignedJwt = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsignedJwt),
  );
  const assertion = `${unsignedJwt}.${base64Url(new Uint8Array(signature))}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(await responseError(response));
  const data = await response.json();
  return data.access_token;
}

function pemToBytes(pem) {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

async function responseError(response) {
  const text = await response.text();
  try {
    const data = JSON.parse(text);
    return (
      data.error?.message ||
      data.error ||
      `${response.status} ${response.statusText}`
    );
  } catch (_) {
    return text || `${response.status} ${response.statusText}`;
  }
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
