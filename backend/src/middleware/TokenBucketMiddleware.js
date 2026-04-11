/**
 * Token Bucket Rate Limiter Middleware
 * Prevents abuse and ensures fair token usage across users
 */
const requestBuckets = {}; // Store { userId: { tokens, lastRefill } }

const TokenBucketMiddleware = (req, res, next) => {
  const userId = req.body.userId || req.params.userId;

  if (!userId) {
    return res.status(400).json({
      success: false,
      error: 'User ID required for rate limiting'
    });
  }

  // Initialize bucket for new user
  if (!requestBuckets[userId]) {
    requestBuckets[userId] = {
      tokens: 10, // 10 requests per hour per user
      lastRefill: Date.now()
    };
  }

  const bucket = requestBuckets[userId];
  const now = Date.now();
  const hourInMs = 3600000;

  // Refill tokens every hour
  if (now - bucket.lastRefill >= hourInMs) {
    bucket.tokens = 10;
    bucket.lastRefill = now;
  }

  // Check if user has tokens
  if (bucket.tokens <= 0) {
    return res.status(429).json({
      success: false,
      error: 'Rate limit exceeded. Max 10 requests per hour.',
      refillTime: Math.ceil((hourInMs - (now - bucket.lastRefill)) / 1000) + ' seconds'
    });
  }

  // Consume token
  bucket.tokens--;

  // Add remaining tokens to response headers
  res.set('X-RateLimit-Remaining', bucket.tokens);
  res.set('X-RateLimit-Reset', new Date(bucket.lastRefill + hourInMs).toISOString());

  next();
};

module.exports = TokenBucketMiddleware;
