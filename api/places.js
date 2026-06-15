const { kv } = require('@vercel/kv');

// Public shared fallback database URL (hosted on npoint) for zero-config out-of-the-box syncing
const FALLBACK_DB_URL = 'https://api.npoint.io/b3f62804fe66d1f0545f';

async function fetchFallbackPlaces() {
  try {
    const res = await fetch(FALLBACK_DB_URL);
    if (!res.ok) return [];
    const data = await res.json();
    return Array.isArray(data) ? data : [];
  } catch (e) {
    console.error('Fallback read error:', e);
    return [];
  }
}

async function saveFallbackPlaces(places) {
  try {
    const res = await fetch(FALLBACK_DB_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(places),
    });
    return res.ok;
  } catch (e) {
    console.error('Fallback write error:', e);
    return false;
  }
}

export default async function handler(request, response) {
  // CORS Headers
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (request.method === 'OPTIONS') {
    return response.status(200).end();
  }

  const PLACES_KEY = 'gec_compass_custom_places';

  if (request.method === 'GET') {
    try {
      // Try Vercel KV first
      if (process.env.KV_REST_API_URL && process.env.KV_REST_API_TOKEN) {
        const places = await kv.get(PLACES_KEY) || [];
        return response.status(200).json(places);
      } else {
        throw new Error('Vercel KV not configured');
      }
    } catch (error) {
      console.warn('Vercel KV not available, falling back to public DB:', error.message);
      const places = await fetchFallbackPlaces();
      return response.status(200).json(places);
    }
  }

  if (request.method === 'POST') {
    try {
      const data = request.body;
      
      // Basic validation
      if (!data || !data.id) {
        return response.status(400).json({ error: 'Invalid data' });
      }

      const isFeedback = data.type === 'feedback' || (data.tags && data.tags.feedback === true);

      if (isFeedback) {
        const FEEDBACK_KEY = 'gec_compass_feedback';
        // Try Vercel KV first
        if (process.env.KV_REST_API_URL && process.env.KV_REST_API_TOKEN) {
          const existingFeedback = await kv.get(FEEDBACK_KEY) || [];
          existingFeedback.push(data);
          await kv.set(FEEDBACK_KEY, existingFeedback);
          return response.status(200).json({ success: true, feedback: data, source: 'kv' });
        } else {
          // Fallback to npoint list
          const existingPlaces = await fetchFallbackPlaces();
          existingPlaces.push(data);
          const success = await saveFallbackPlaces(existingPlaces);
          if (success) {
            return response.status(200).json({ success: true, feedback: data, source: 'fallback' });
          } else {
            return response.status(500).json({ error: 'Failed to save feedback to fallback DB' });
          }
        }
      } else {
        // Handle normal place addition
        if (!data.name) {
          return response.status(400).json({ error: 'Invalid place data (missing name)' });
        }

        // Try Vercel KV first
        if (process.env.KV_REST_API_URL && process.env.KV_REST_API_TOKEN) {
          const existingPlaces = await kv.get(PLACES_KEY) || [];
          // Prevent duplicate IDs
          const filtered = existingPlaces.filter(p => p.id !== data.id);
          filtered.push(data);
          await kv.set(PLACES_KEY, filtered);
          return response.status(200).json({ success: true, place: data, source: 'kv' });
        } else {
          const existingPlaces = await fetchFallbackPlaces();
          // Prevent duplicate IDs
          const filtered = existingPlaces.filter(p => p.id !== data.id);
          filtered.push(data);
          const success = await saveFallbackPlaces(filtered);
          if (success) {
            return response.status(200).json({ success: true, place: data, source: 'fallback' });
          } else {
            return response.status(500).json({ error: 'Failed to save place to fallback DB' });
          }
        }
      }
    } catch (error) {
      return response.status(500).json({ error: error.message });
    }
  }

  return response.status(405).json({ error: 'Method not allowed' });
}
