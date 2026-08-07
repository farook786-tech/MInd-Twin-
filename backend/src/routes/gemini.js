const express = require('express');
const axios = require('axios');
const { authMiddleware } = require('../middleware/auth');
const router = express.Router();

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
const GEMINI_ENDPOINT =
  process.env.GEMINI_ENDPOINT ||
  'https://generativelanguage.googleapis.com/v1beta/models';

const FALLBACK_TEXT =
  'I am right here with you. Take one slow breath, ground yourself in this moment, and take one step at a time.';

/**
 * Maps chat history entries (e.g. "user: hello", "assistant: hi")
 * into Gemini content turns, merging consecutive same-role turns
 * because the Gemini API requires alternating roles.
 */
function mapHistory(history = []) {
  const contents = [];
  for (const entry of history) {
    if (typeof entry !== 'string') continue;
    const idx = entry.indexOf(': ');
    if (idx === -1) continue;
    const role = entry.slice(0, idx).trim();
    const text = entry.slice(idx + 2).trim();
    if (!text) continue;

    const geminiRole = role === 'user' ? 'user' : 'model';
    const last = contents[contents.length - 1];
    if (last && last.role === geminiRole) {
      last.parts[0].text += '\n' + text;
    } else {
      contents.push({ role: geminiRole, parts: [{ text }] });
    }
  }
  return contents;
}

/**
 * POST /api/gemini/chat
 * Proxies a chat request to the Gemini API. Keeps the API key
 * server-side instead of in the Flutter client.
 * Body: { prompt: string, systemPrompt?: string, history?: string[] }
 * Response: { success: true, response: string }
 */
router.post('/chat', authMiddleware, async (req, res) => {
  try {
    const { prompt, systemPrompt, history } = req.body;

    if (!prompt || typeof prompt !== 'string') {
      return res.status(400).json({ success: false, error: 'prompt is required' });
    }

    if (!GEMINI_API_KEY) {
      console.warn('[Gemini] GEMINI_API_KEY not set; returning fallback.');
      return res.json({ success: true, response: FALLBACK_TEXT, offline: true });
    }

    const contents = [
      ...mapHistory(history || []),
      { role: 'user', parts: [{ text: prompt }] },
    ];

    const body = {
      contents,
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 400,
      },
    };

    if (systemPrompt && typeof systemPrompt === 'string' && systemPrompt.trim()) {
      body.systemInstruction = { parts: [{ text: systemPrompt }] };
    }

    const response = await axios.post(
      `${GEMINI_ENDPOINT}/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
      body,
      { timeout: 20000 }
    );

    const text =
      response.data?.candidates?.[0]?.content?.parts
        ?.map((p) => p.text)
        .join('')
        .trim() || '';

    res.json({ success: true, response: text || FALLBACK_TEXT });
  } catch (error) {
    console.error('[Gemini] Error:', error.message);
    res.json({ success: true, response: FALLBACK_TEXT });
  }
});

module.exports = router;
