/**
 * Token Bucket Rate Limiter Middleware
 * Prevents abuse and ensures fair token usage across users.
 *
 * Keys on the authenticated user id (set by authMiddleware from the JWT)
 * when available, otherwise falls back to the client IP so the limiter is
 * not spoofable via req.body/req.params fields.
 *
 * Factory: TokenBucketMiddleware({ capacity, windowMs })
 *   - capacity: tokens granted per window (default 10)
 *   - windowMs: refill window length in ms (default 1 hour)
 */
const buckets = new Map();
const IDLE_BUCKET_TTL_MS = 24 * 60 * 60 * 1000; // drop buckets idle for 24h
let lastPrune = 0;

// Bound memory usage by dropping buckets that have not refilled for a day.
function pruneBuckets() {
  const now = Date.now();
  if (now - lastPrune < IDLE_BUCKET_TTL_MS) return;
  lastPrune = now;
  for (const [key, bucket] of buckets) {
    if (now - bucket.lastRefill >= IDLE_BUCKET_TTL_MS) {
      buckets.delete(key);
    }
  }
}

const TokenBucketMiddleware = (options = {}) => {
  const capacity = options.capacity ?? 10;
  const windowMs = options.windowMs ?? 60 * 60 * 1000;

  return (req, res, next) => {
    pruneBuckets();

    const key = req.userId || req.ip || 'unknown';
    const now = Date.now();

    let bucket = buckets.get(key);
    if (!bucket) {
      bucket = { tokens: capacity, lastRefill: now };
      buckets.set(key, bucket);
    }

    // Refill tokens proportional to the time elapsed in the current window.
    const refillTokens = Math.floor(((now - bucket.lastRefill) / windowMs) * capacity);
    if (refillTokens > 0) {
      bucket.tokens = Math.min(capacity, bucket.tokens + refillTokens);
      bucket.lastRefill = now;
    }

    if (bucket.tokens <= 0) {
      return res.status(429).json({
        success: false,
        error: 'Rate limit exceeded. Please try again later.',
        refillSeconds: Math.max(1, Math.ceil((windowMs - (now - bucket.lastRefill)) / 1000)),
      });
    }

    // Consume token
    bucket.tokens--;

    // Add remaining tokens to response headers
    res.set('X-RateLimit-Remaining', bucket.tokens);
    res.set('X-RateLimit-Reset', new Date(bucket.lastRefill + windowMs).toISOString());

    next();
  };
};

module.exports = TokenBucketMiddleware;
