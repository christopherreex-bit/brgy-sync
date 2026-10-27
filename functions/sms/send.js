/**
 * Cloudflare Pages Function — SMS Proxy
 *
 * POST /sms/send
 * Body: { "to": "+639397193163", "message": "..." }
 *
 * Proxies to MySMSGate API. Same origin as the app, so no CORS issues.
 */

export async function onRequest(context) {
  const { request, env } = context;

  // Handle CORS preflight
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      },
    });
  }

  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  try {
    if (!env.MYSMSGATE_API_KEY) {
      return jsonResponse(
        { success: false, error: 'MYSMSGATE_API_KEY is not configured' },
        503,
      );
    }

    const body = await request.json();
    const { to, message } = body;

    if (!to || !message) {
      return jsonResponse({ success: false, error: 'Missing to or message' }, 400);
    }

    // Get devices from MySMSGate
    const devResponse = await fetch('https://mysmsgate.net/api/v1/devices', {
      headers: { 'Authorization': `Bearer ${env.MYSMSGATE_API_KEY}` },
    });
    const devData = await responseJson(devResponse);

    if (!devResponse.ok) {
      return jsonResponse(
        {
          success: false,
          error: 'MySMSGate device lookup failed',
          providerStatus: devResponse.status,
          providerResponse: devData,
        },
        devResponse.status,
      );
    }

    let deviceId = null;
    if (devData.devices && devData.devices.length > 0) {
      const online = devData.devices.filter(d => d.status === 'online');
      deviceId = (online.length > 0 ? online[0] : devData.devices[0]).id;
    }

    // Send SMS via MySMSGate
    const sendBody = { to, message };
    if (deviceId) sendBody.device_id = deviceId;

    const sendResponse = await fetch('https://mysmsgate.net/api/v1/send', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.MYSMSGATE_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(sendBody),
    });

    const sendData = await responseJson(sendResponse);

    return jsonResponse(sendData, sendResponse.status);
  } catch (err) {
    return jsonResponse({ success: false, error: err.message }, 500);
  }
}

async function responseJson(response) {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    return { raw: text };
  }
}

function jsonResponse(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-store',
    },
  });
}
