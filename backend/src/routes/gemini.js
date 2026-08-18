const express = require('express');
const axios = require('axios');
const { authMiddleware } = require('../middleware/auth');
const TokenBucketMiddleware = require('../middleware/TokenBucketMiddleware');
const router = express.Router();

// AI endpoints proxy to paid external providers; cap usage per authenticated user.
const aiRateLimit = TokenBucketMiddleware({ capacity: 20, windowMs: 60 * 60 * 1000 });

const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL || 'openai/gpt-4o-mini';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
const GEMINI_ENDPOINT =
  process.env.GEMINI_ENDPOINT ||
  'https://generativelanguage.googleapis.com/v1beta/models';

const FALLBACK_TEXT =
  'I am right here with you. Take one slow breath, ground yourself in this moment, and take one step at a time.';

/**
 * Maps chat history entries (e.g. "user: hello", "assistant: hi")
 * into OpenAI-style {role, content} turns. Merges consecutive same-role
 * turns because some providers require alternating roles.
 */
function mapHistory(history = []) {
  const messages = [];
  for (const entry of history) {
    if (typeof entry !== 'string') continue;
    const idx = entry.indexOf(': ');
    if (idx === -1) continue;
    const role = entry.slice(0, idx).trim();
    const text = entry.slice(idx + 2).trim();
    if (!text) continue;

    const mappedRole = role === 'user' ? 'user' : 'assistant';
    const last = messages[messages.length - 1];
    if (last && last.role === mappedRole) {
      last.content += '\n' + text;
    } else {
      messages.push({ role: mappedRole, content: text });
    }
  }
  return messages;
}

/**
 * Try OpenRouter (OpenAI-compatible chat completions) first. It is the
 * primary, proven provider for MindTwin. Returns text or null.
 */
async function callOpenRouter({ systemPrompt, history, prompt }) {
  if (!OPENROUTER_API_KEY || OPENROUTER_API_KEY.includes('YOUR_')) return null;
  const messages = [];
  if (systemPrompt && systemPrompt.trim()) {
    messages.push({ role: 'system', content: systemPrompt });
  }
  messages.push(...mapHistory(history || []));
  messages.push({ role: 'user', content: prompt });

  const response = await axios.post(
    'https://openrouter.ai/api/v1/chat/completions',
    {
      model: OPENROUTER_MODEL,
      messages,
      max_tokens: 400,
      temperature: 0.7,
    },
    {
      headers: {
        Authorization: `Bearer ${OPENROUTER_API_KEY}`,
        'HTTP-Referer': 'http://localhost:5000',
      },
      timeout: 20000,
    }
  );
  return (response.data?.choices?.[0]?.message?.content || '').trim();
}

/**
 * Fall back to the Gemini API when OpenRouter is not configured.
 * Returns text or null.
 */
async function callGemini({ systemPrompt, history, prompt }) {
  if (!GEMINI_API_KEY) return null;

  const geminiContents = [
    ...mapHistory(history || []).map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    })),
    { role: 'user', parts: [{ text: prompt }] },
  ];

  const body = {
    contents: geminiContents,
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 400,
    },
  };

  if (systemPrompt && typeof systemPrompt === 'string' && systemPrompt.trim()) {
    body.systemInstruction = { parts: [{ text: systemPrompt }] };
  }

  const response = await axios.post(
    `${GEMINI_ENDPOINT}/${GEMINI_MODEL}:generateContent`,
    body,
    {
      headers: { 'x-goog-api-key': GEMINI_API_KEY },
      timeout: 20000,
    }
  );

  return (
    response.data?.candidates?.[0]?.content?.parts
      ?.map((p) => p.text)
      .join('')
      .trim() || null
  );
}

/**
 * POST /api/gemini/chat
 * Proxies a chat request to a real LLM provider, keeping API keys
 * server-side instead of in the Flutter client. Tries OpenRouter first,
 * then Gemini, then a local fallback.
 * Body: { prompt: string, systemPrompt?: string, history?: string[] }
 * Response: { success: true, response: string }
 */
router.post('/chat', authMiddleware, aiRateLimit, async (req, res) => {
  try {
    const { prompt, systemPrompt, history } = req.body;

    if (!prompt || typeof prompt !== 'string') {
      return res.status(400).json({ success: false, error: 'prompt is required' });
    }

    let text = null;

    // 1. Primary provider: OpenRouter (works for sure; validated live).
    try {
      text = await callOpenRouter({ systemPrompt, history, prompt });
    } catch (error) {
      console.warn('[Gemini] OpenRouter failed, trying Gemini:', error.message);
    }

    // 2. Fallback provider: Gemini.
    if (!text) {
      try {
        text = await callGemini({ systemPrompt, history, prompt });
      } catch (error) {
        console.error('[Gemini] Error:', error.message);
      }
    }

    if (!text) {
      console.warn('[Gemini] No provider available; returning fallback.');
      return res.json({ success: true, response: FALLBACK_TEXT, offline: true });
    }

    res.json({ success: true, response: text });
  } catch (error) {
    console.error('[Gemini] Error:', error.message);
    res.status(502).json({
      success: false,
      error: 'Upstream model request failed. Please try again.',
    });
  }
});

module.exports = router;
