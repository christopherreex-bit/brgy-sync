/**
 * Deploy Firestore composite indexes via REST API.
 * Usage: node scripts/deploy-indexes.js
 */

const fs = require('fs');
const https = require('https');

// Load .env
const envContent = fs.readFileSync('.env', 'utf8');
envContent.split('\n').forEach(line => {
  line = line.trim();
  if (!line || line.startsWith('#')) return;
  const eqIdx = line.indexOf('=');
  if (eqIdx === -1) return;
  const key = line.substring(0, eqIdx);
  const val = line.substring(eqIdx + 1);
  process.env[key] = val;
});

const admin = require('firebase-admin');
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const projectId = serviceAccount.project_id;
const indexes = JSON.parse(fs.readFileSync('firestore.indexes.json', 'utf8'));

function getAccessToken() {
  return new Promise((resolve, reject) => {
    const cred = admin.credential.cert(serviceAccount);
    cred.getAccessToken().then(res => resolve(res.access_token)).catch(reject);
  });
}

function createIndex(token, indexData) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      queryScope: indexData.queryScope,
      fields: indexData.fields
    });
    const options = {
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${projectId}/databases/(default)/collectionGroups/${indexData.collectionGroup}/indexes`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        if (res.statusCode === 200 || res.statusCode === 201) {
          resolve({ ok: true, created: true, collection: indexData.collectionGroup });
        } else if (res.statusCode === 409) {
          resolve({ ok: true, exists: true, collection: indexData.collectionGroup });
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function main() {
  const token = await getAccessToken();
  console.log(`Deploying ${indexes.indexes.length} indexes to project: ${projectId}\n`);

  let created = 0, existed = 0, failed = 0;
  for (const idx of indexes.indexes) {
    try {
      const result = await createIndex(token, idx);
      if (result.exists) {
        existed++;
        console.log(`  ✓ Already exists: ${idx.collectionGroup}`);
      } else {
        created++;
        console.log(`  ✓ Created: ${idx.collectionGroup}`);
      }
    } catch (err) {
      failed++;
      console.error(`  ✗ FAILED: ${idx.collectionGroup} — ${err.message}`);
    }
  }
  console.log(`\nDone. Created: ${created}, Already existed: ${existed}, Failed: ${failed}`);
}

main().catch(err => { console.error(err); process.exit(1); });
