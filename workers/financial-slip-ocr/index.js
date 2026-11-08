const MODEL = '@cf/meta/llama-3.2-11b-vision-instruct';
const MAX_BASE64_LENGTH = 3_000_000;

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return cors(new Response(null));
    if (request.method !== 'POST' || new URL(request.url).pathname !== '/extract') {
      return json({ error: 'Not found.' }, 404);
    }
    if (!env.AI) return json({ error: 'OCR service is not configured.' }, 503);
    if (!env.FIREBASE_WEB_API_KEY) {
      return json({ error: 'OCR authentication is not configured.' }, 503);
    }

    try {
      const user = await verifyFirebaseUser(request, env.FIREBASE_WEB_API_KEY);
      if (!user) return json({ error: 'Sign in before scanning a slip.' }, 401);
      const body = await request.json();
      const image = typeof body.image === 'string' ? body.image : '';
      const contentType = body.contentType;
      if (!['image/jpeg', 'image/png'].includes(contentType)) {
        return json({ error: 'Only JPG and PNG slips can be scanned.' }, 400);
      }
      if (!image || image.length > MAX_BASE64_LENGTH) {
        return json({ error: 'The slip image is missing or too large.' }, 400);
      }

      const prompt = `Read this Philippine bank deposit or withdrawal slip.
Return ONLY valid JSON with this exact shape:
{"amount":number|null,"transactionNumber":"","transactionDate":"YYYY-MM-DD or original printed date","financialInstitution":"","confidence":0.0,"rawText":""}
Rules:
- Never invent a value. Use null or an empty string when unclear.
- amount is the final transaction amount in Philippine pesos, without commas or currency symbols.
- transactionNumber is the transaction, reference, trace, deposit-slip, or withdrawal-slip number.
- Carefully inspect text immediately beside or below labels such as Transaction Reference, Reference No.,
  Transaction No., Trace No., or Slip No. Preserve every letter, digit, and hyphen exactly.
- financialInstitution is the printed bank, remittance provider, or government institution.
- confidence is from 0 to 1 for the structured fields overall.
- rawText is a short transcription of the relevant printed fields only.`;

      const output = await env.AI.run(MODEL, {
        prompt,
        image: `data:${contentType};base64,${image}`,
        max_tokens: 500,
        temperature: 0,
      });
      const text = output?.response || output?.result || '';
      const parsed = parseModelJson(text);
      const result = sanitize(parsed);

      if (!result.transactionNumber) {
        const referenceFromText = extractReference(result.rawText);
        if (referenceFromText) {
          result.transactionNumber = referenceFromText;
        } else {
          try {
            const referenceOutput = await env.AI.run(MODEL, {
              prompt: `Inspect only the transaction-reference area of this financial slip.
Find the value beside or immediately below Transaction Reference, Reference No., Transaction No.,
Trace No., or Slip No. Preserve all letters, digits, and hyphens exactly.
Return ONLY JSON: {"transactionNumber":""}. Use an empty string only if no such value is visible.`,
              image: `data:${contentType};base64,${image}`,
              max_tokens: 100,
              temperature: 0,
            });
            const referenceText = referenceOutput?.response || referenceOutput?.result || '';
            const referenceParsed = parseModelJson(referenceText);
            result.transactionNumber = clean(referenceParsed?.transactionNumber, 120);
          } catch (_) {
            // Keep the field blank so the reviewer can enter it manually.
          }
        }
      }

      return json({ result });
    } catch (error) {
      return json({ error: error?.message || 'Slip extraction failed.' }, 500);
    }
  },
};

async function verifyFirebaseUser(request, apiKey) {
  const authorization = request.headers.get('Authorization') || '';
  if (!authorization.startsWith('Bearer ')) return null;
  const idToken = authorization.slice(7).trim();
  if (!idToken) return null;
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken }),
    },
  );
  if (!response.ok) return null;
  const data = await response.json();
  return data.users?.[0] || null;
}

function parseModelJson(value) {
  const text = String(value || '').trim();
  try { return JSON.parse(text); } catch (_) {}
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error('The OCR response could not be understood. Enter the details manually.');
  return JSON.parse(match[0]);
}

function sanitize(value) {
  const amount = Number(value?.amount);
  const confidence = Number(value?.confidence);
  return {
    amount: Number.isFinite(amount) && amount > 0 ? amount : null,
    transactionNumber: clean(value?.transactionNumber, 120),
    transactionDate: clean(value?.transactionDate, 60),
    financialInstitution: clean(value?.financialInstitution, 120),
    confidence: Number.isFinite(confidence) ? Math.max(0, Math.min(1, confidence)) : 0,
    rawText: clean(value?.rawText, 1000),
  };
}

function clean(value, max) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

function extractReference(rawText) {
  const text = clean(rawText, 1000);
  if (!text) return '';
  const match = text.match(
    /(?:transaction\s*(?:reference|no\.?|number)|reference\s*(?:no\.?|number)?|trace\s*(?:no\.?|number)|slip\s*(?:no\.?|number))\s*[:#-]?\s*([A-Z0-9][A-Z0-9-]{3,})/i,
  );
  return match ? clean(match[1], 120) : '';
}

function json(body, status = 200) {
  return cors(new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  }));
}

function cors(response) {
  const headers = new Headers(response.headers);
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  return new Response(response.body, { status: response.status, headers });
}
