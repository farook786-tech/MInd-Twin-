const axios = require('axios');

/**
 * Single source of truth for which LLM models the backend calls.
 *
 * Providers retire model IDs regularly (openai/gpt-4-turbo and
 * gemini-2.0-flash both disappeared), and when that happens every AI
 * request 404s and users silently get the canned offline reply. Keep the
 * defaults here current and override per-environment with env vars.
 */
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL || 'openai/gpt-4.1-mini';
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-3.8-flash';
const GEMINI_ENDPOINT =
  process.env.GEMINI_ENDPOINT ||
  'https://generativelanguage.googleapis.com/v1beta/models';

function isConfiguredKey(key) {
  return Boolean(key && key.trim() && !/your_|YOUR_/.test(key));
}

/**
 * Checks at startup that each configured provider accepts its key and that
 * the configured model still exists. Logs an error that names the env var
 * to fix rather than failing on the first user request.
 * Never throws and never logs the keys themselves.
 */
async function verifyAiProviders() {
  const results = {};

  const openRouterKey = process.env.OPENROUTER_API_KEY;
  if (!isConfiguredKey(openRouterKey)) {
    results.openrouter = 'not configured';
  } else {
    try {
      await axios.get('https://openrouter.ai/api/v1/auth/key', {
        headers: { Authorization: `Bearer ${openRouterKey}` },
        timeout: 10000,
      });
      const { data } = await axios.get('https://openrouter.ai/api/v1/models', { timeout: 10000 });
      const exists = (data?.data || []).some((m) => m.id === OPENROUTER_MODEL);
      results.openrouter = exists ? 'ok' : `model "${OPENROUTER_MODEL}" not found - set OPENROUTER_MODEL`;
    } catch (error) {
      const status = error.response?.status;
      results.openrouter = status === 401 ? 'invalid OPENROUTER_API_KEY' : `unreachable (${status || error.code})`;
    }
  }

  const geminiKey = process.env.GEMINI_API_KEY;
  if (!isConfiguredKey(geminiKey)) {
    results.gemini = 'not configured';
  } else {
    try {
      await axios.get(`${GEMINI_ENDPOINT}/${GEMINI_MODEL}`, {
        headers: { 'x-goog-api-key': geminiKey },
        timeout: 10000,
      });
      results.gemini = 'ok';
    } catch (error) {
      const status = error.response?.status;
      results.gemini =
        status === 404 ? `model "${GEMINI_MODEL}" not found - set GEMINI_MODEL`
          : status === 400 || status === 403 ? 'GEMINI_API_KEY rejected (invalid or revoked)'
            : `unreachable (${status || error.code})`;
    }
  }

  const healthy = Object.values(results).some((r) => r === 'ok');
  for (const [provider, status] of Object.entries(results)) {
    const line = `[AI] ${provider}: ${status}`;
    if (status === 'ok') console.log(`✅ ${line}`);
    else console.error(`❌ ${line}`);
  }
  if (!healthy) {
    console.error('❌ [AI] No working LLM provider - AI chat will only return the offline fallback reply.');
  }
  return results;
}

module.exports = {
  OPENROUTER_MODEL,
  GEMINI_MODEL,
  GEMINI_ENDPOINT,
  isConfiguredKey,
  verifyAiProviders,
};
