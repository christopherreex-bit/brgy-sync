/**
 * SMS Proxy Worker for BrgySync
 *
 * Proxies SMS requests from the Flutter web app to MySMSGate API.
 * This avoids CORS issues since the worker is on the same Cloudflare domain.
 *
 * POST /send
 * Body: { "to": "+639397193163", "message": "..." }
 */

export default {
  async fetch(request, env) {
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
      const body = await request.json();
      const { to, message } = body;

      if (!to || !message) {
        return new Response(
          JSON.stringify({ success: false, error: 'Missing to or message' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        );
      }

      // Get devices from MySMSGate
      const devResponse = await fetch('https://mysmsgate.net/api/v1/devices', {
        headers: { 'Authorization': `Bearer ${env.MYSMSGATE_API_KEY}` },
      });
      const devData = await devResponse.json();

      let deviceId = null;
      if (devData.devices && devData.devices.length > 0) {
        const online = devData.devices.filter(d => d.status === 'online');
        deviceId = (online.length > 0 ? online[0] : devData.devices[0]).id;
      }

      // Send SMS via MySMSGate
      const sendBody = {
        to: to,
        message: message,
      };
      if (deviceId) {
        sendBody.device_id = deviceId;
      }

      const sendResponse = await fetch('https://mysmsgate.net/api/v1/send', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.MYSMSGATE_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(sendBody),
      });

      const sendData = await sendResponse.json();

      return new Response(JSON.stringify(sendData), {
        status: sendResponse.status,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    } catch (err) {
      return new Response(
        JSON.stringify({ success: false, error: err.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }
  },
};
