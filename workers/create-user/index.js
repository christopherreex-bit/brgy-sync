/**
 * Cloudflare Worker — Create Staff Account
 *
 * POST /create-user
 * Body: { "email": "...", "password": "...", "name": "...", "mobile": "...", "role": "staff|officer|captain" }
 *
 * Uses Firebase Admin SDK to create the user WITHOUT affecting the client session.
 * Requires FIREBASE_SERVICE_ACCOUNT env var (same as cron scripts).
 */

import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

let app;
function getApp() {
  if (!app) {
    if (getApps().length === 0) {
      // Try to parse the service account from env
      const sa = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
      app = initializeApp({ credential: cert(sa) });
    } else {
      app = getApps()[0];
    }
  }
  return app;
}

export default {
  async fetch(request, env) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    // Verify the request comes from an authenticated captain
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    try {
      const body = await request.json();
      const { email, password, name, mobile, role } = body;

      if (!email || !password || !name || !mobile || !role) {
        return new Response(JSON.stringify({ error: 'Missing required fields' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      if (!['staff', 'officer', 'captain'].includes(role)) {
        return new Response(JSON.stringify({ error: 'Invalid role' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      getApp();
      const adminAuth = getAuth();
      const db = getFirestore();

      // Create the Auth user
      const userRecord = await adminAuth.createUser({
        email,
        password,
        displayName: name,
      });

      // Create the Firestore user document
      await db.collection('users').doc(userRecord.uid).set({
        name,
        mobile,
        email,
        role,
        isActive: true,
        isSeedData: false,
        createdAt: new Date().toISOString(),
      });

      return new Response(JSON.stringify({
        success: true,
        uid: userRecord.uid,
        email,
        role,
      }), {
        status: 201,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    } catch (err) {
      return new Response(JSON.stringify({
        error: err.message || 'Failed to create user',
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }
  },
};
