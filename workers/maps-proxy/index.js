const CENTER_LAT = 14.533611;
const CENTER_LON = 121.079722;

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return cors(new Response(null));
    if (request.method !== 'GET') return json({ error: 'Method not allowed.' }, 405);
    if (!env.GEOAPIFY_API_KEY) {
      return json({ error: 'Map address service is not configured.' }, 503);
    }

    const url = new URL(request.url);
    try {
      if (url.pathname === '/autocomplete') {
        const text = (url.searchParams.get('text') || '').trim();
        if (text.length < 3) return json({ results: [] });
        const target = new URL('https://api.geoapify.com/v1/geocode/autocomplete');
        target.searchParams.set('text', text);
        target.searchParams.set('format', 'json');
        target.searchParams.set('limit', '6');
        target.searchParams.set('filter', `circle:${CENTER_LON},${CENTER_LAT},5000`);
        target.searchParams.set('bias', `proximity:${CENTER_LON},${CENTER_LAT}`);
        target.searchParams.set('lang', 'en');
        target.searchParams.set('apiKey', env.GEOAPIFY_API_KEY);
        const response = await fetch(target);
        if (!response.ok) return json({ error: 'Address search failed.' }, 502);
        const data = await response.json();
        return json({
          results: (data.results || []).map((item) => ({
            formatted: item.formatted,
            lat: item.lat,
            lon: item.lon,
            placeId: item.place_id,
            components: {
              houseNumber: item.housenumber || null,
              street: item.street || null,
              suburb: item.suburb || null,
              district: item.district || null,
              city: item.city || item.municipality || null,
              postcode: item.postcode || null,
              state: item.state || null,
              country: item.country || null,
            },
          })),
        });
      }

      if (url.pathname === '/reverse') {
        const lat = Number(url.searchParams.get('lat'));
        const lon = Number(url.searchParams.get('lon'));
        if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
          return json({ error: 'Valid coordinates are required.' }, 400);
        }
        const target = new URL('https://api.geoapify.com/v1/geocode/reverse');
        target.searchParams.set('lat', String(lat));
        target.searchParams.set('lon', String(lon));
        target.searchParams.set('format', 'json');
        target.searchParams.set('lang', 'en');
        target.searchParams.set('apiKey', env.GEOAPIFY_API_KEY);
        const response = await fetch(target);
        if (!response.ok) return json({ error: 'Reverse geocoding failed.' }, 502);
        const data = await response.json();
        const item = data.results?.[0];
        return json({
          formatted: item?.formatted || null,
          placeId: item?.place_id || null,
          components: item ? {
            houseNumber: item.housenumber || null,
            street: item.street || null,
            suburb: item.suburb || null,
            district: item.district || null,
            city: item.city || item.municipality || null,
            postcode: item.postcode || null,
            state: item.state || null,
            country: item.country || null,
          } : {},
        });
      }
      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      return json({ error: error?.message || 'Map service failed.' }, 500);
    }
  },
};

function json(body, status = 200) {
  return cors(new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  }));
}

function cors(response) {
  const headers = new Headers(response.headers);
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type');
  return new Response(response.body, { status: response.status, headers });
}
