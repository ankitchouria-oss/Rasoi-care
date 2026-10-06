/*
 * In-memory rate limiting and short-lived OTP state.
 *
 * Three tiers (thresholds configurable by env var, all with defaults):
 *   AUTH          — login/signup. Per-account AND per-IP exponential
 *                   backoff: a few free attempts, then each wrong one
 *                   doubles the wait. A correct attempt resets it.
 *   PUBLIC        — unauthenticated read-only routes; moderate per-IP cap.
 *   AUTHENTICATED — every route behind a require*Auth middleware; looser,
 *                   keyed per account rather than per IP.
 * Plus a coarse per-IP backstop across all of /api/.
 *
 * In-memory is enough for a single Node process (Hostinger runs one per
 * app). It resets on restart and wouldn't be shared across instances.
 */

const crypto = require("node:crypto");

function envInt(name, fallback) {
  const v = Number.parseInt(process.env[name], 10);
  return Number.isNaN(v) ? fallback : v;
}

function envFloat(name, fallback) {
  const v = Number.parseFloat(process.env[name]);
  return Number.isNaN(v) ? fallback : v;
}

/** Map that evicts its least-recently-touched key past maxSize — every
 * store here is keyed by attacker-controlled values (IPs, emails, phone
 * numbers), so without a bound a script cycling identities could grow it
 * forever. Worst case from early eviction is a limit resetting slightly
 * sooner, never a memory leak. getOrCreate() auto-vivifies like a
 * defaultdict; set() is for state that's always written explicitly. */
class BoundedMap {
  constructor(defaultFactory = null, maxSize = 20000) {
    this.defaultFactory = defaultFactory;
    this.maxSize = maxSize;
    this.map = new Map();
  }

  touch(key, value) {
    this.map.delete(key);
    this.map.set(key, value);
  }

  getOrCreate(key) {
    if (this.map.has(key)) {
      const value = this.map.get(key);
      this.touch(key, value);
      return value;
    }
    if (this.map.size >= this.maxSize) this.map.delete(this.map.keys().next().value);
    const value = this.defaultFactory();
    this.map.set(key, value);
    return value;
  }

  get(key) {
    if (!this.map.has(key)) return undefined;
    const value = this.map.get(key);
    this.touch(key, value);
    return value;
  }

  set(key, value) {
    this.touch(key, value);
    while (this.map.size > this.maxSize) this.map.delete(this.map.keys().next().value);
  }

  pop(key) {
    const value = this.map.get(key);
    this.map.delete(key);
    return value;
  }

  has(key) {
    return this.map.has(key);
  }

  keys() {
    return [...this.map.keys()];
  }
}

const LIMITS = {
  globalMax: envInt("RATE_LIMIT_GLOBAL_MAX_CALLS", 180),
  globalWindow: envInt("RATE_LIMIT_GLOBAL_WINDOW_SECONDS", 60),
  publicMax: envInt("RATE_LIMIT_PUBLIC_MAX_CALLS", 60),
  publicWindow: envInt("RATE_LIMIT_PUBLIC_WINDOW_SECONDS", 60),
  authedMax: envInt("RATE_LIMIT_AUTHENTICATED_MAX_CALLS", 120),
  authedWindow: envInt("RATE_LIMIT_AUTHENTICATED_WINDOW_SECONDS", 60),
  acctFree: envInt("RATE_LIMIT_AUTH_ACCOUNT_FREE_ATTEMPTS", 5),
  acctBase: envInt("RATE_LIMIT_AUTH_ACCOUNT_BACKOFF_BASE_SECONDS", 2),
  acctMax: envInt("RATE_LIMIT_AUTH_ACCOUNT_BACKOFF_MAX_SECONDS", 900),
  ipFree: envInt("RATE_LIMIT_AUTH_IP_FREE_ATTEMPTS", 15),
  ipBase: envInt("RATE_LIMIT_AUTH_IP_BACKOFF_BASE_SECONDS", 2),
  ipMax: envInt("RATE_LIMIT_AUTH_IP_BACKOFF_MAX_SECONDS", 900),
};

const monotonic = () => performance.now() / 1000;
const wallClock = () => Date.now() / 1000;

const rateBuckets = new BoundedMap(() => []);

/** Sliding-window call counter. True if this call should be rejected. */
function rateLimited(key, maxCalls, windowSeconds) {
  const t = monotonic();
  const bucket = rateBuckets.getOrCreate(key);
  while (bucket.length && t - bucket[0] > windowSeconds) bucket.shift();
  if (bucket.length >= maxCalls) return true;
  bucket.push(t);
  return false;
}

const backoffState = new BoundedMap(() => ({ failures: 0, blockedUntil: 0 }));

function backoffCheck(key) {
  const remaining = backoffState.getOrCreate(key).blockedUntil - monotonic();
  return remaining > 0 ? remaining : null;
}

function backoffRecordFailure(key, free, base, max) {
  const state = backoffState.getOrCreate(key);
  state.failures += 1;
  const over = state.failures - free;
  if (over > 0) state.blockedUntil = monotonic() + Math.min(base * 2 ** (over - 1), max);
}

function backoffRecordSuccess(key) {
  backoffState.pop(key);
}

function clientIp(req) {
  const forwarded = req.get("X-Forwarded-For") || "";
  if (forwarded) return forwarded.split(",")[0].trim();
  return req.socket.remoteAddress || "unknown";
}

/** Call before checking credentials on an AUTH-tier route. Sends a 429 and
 * returns true if this account or IP is currently backed off. */
function authGate(req, res, accountKey) {
  const remaining = backoffCheck(`authacct:${accountKey}`) ?? backoffCheck(`authip:${clientIp(req)}`);
  if (remaining !== null) {
    res.status(429).json({
      error: "Too many attempts",
      message: "Try again shortly",
      retry_after: Math.round(remaining * 10) / 10,
    });
    return true;
  }
  return false;
}

/** Call once whether an AUTH-tier attempt succeeded is known. */
function authGateRecord(req, accountKey, success) {
  const ipKey = `authip:${clientIp(req)}`;
  const acctKey = `authacct:${accountKey}`;
  if (success) {
    backoffRecordSuccess(acctKey);
    backoffRecordSuccess(ipKey);
  } else {
    backoffRecordFailure(acctKey, LIMITS.acctFree, LIMITS.acctBase, LIMITS.acctMax);
    backoffRecordFailure(ipKey, LIMITS.ipFree, LIMITS.ipBase, LIMITS.ipMax);
  }
}

const TOO_MANY = { error: "Too Many Requests", message: "Slow down and try again shortly" };

/** PUBLIC tier middleware. */
function rateLimitPublic(req, res, next) {
  if (rateLimited(`public:${clientIp(req)}`, LIMITS.publicMax, LIMITS.publicWindow)) {
    return res.status(429).json(TOO_MANY);
  }
  return next();
}

/** AUTHENTICATED tier — called from inside the auth middlewares once the
 * caller's identity is known. */
function rateLimitAuthenticated(identityKey) {
  return rateLimited(`authed:${identityKey}`, LIMITS.authedMax, LIMITS.authedWindow);
}

/** Global per-IP backstop across /api/ — express-rate-limit, keyed the same
 * way as every other tier here. */
const globalRateLimit = require("express-rate-limit").rateLimit({
  windowMs: LIMITS.globalWindow * 1000,
  limit: LIMITS.globalMax,
  keyGenerator: (req) => `ip:${clientIp(req)}`,
  skip: (req) => !req.path.startsWith("/api/"),
  standardHeaders: false,
  legacyHeaders: false,
  validate: false,
  handler: (req, res) => res.status(429).json(TOO_MANY),
});

// ---------------------------------------------------------------- OTPs
function fourDigitCode() {
  return String(crypto.randomInt(10000)).padStart(4, "0");
}

/** A short-lived, attempt-limited, one-time code store keyed by `key`. */
class OtpStore {
  constructor(ttlSeconds, maxAttempts) {
    this.ttl = ttlSeconds;
    this.maxAttempts = maxAttempts;
    this.state = new BoundedMap();
  }

  request(key) {
    const code = fourDigitCode();
    this.state.set(key, { code, expiresAt: wallClock() + this.ttl, attempts: 0 });
    return code;
  }

  /** Null on a correct, still-valid code (and clears it), else an error
   * message. `missingMessage` is what to say when no code was requested. */
  verify(key, submitted, missingMessage) {
    const entry = this.state.get(key);
    if (!entry) return missingMessage;
    if (wallClock() > entry.expiresAt) {
      this.state.pop(key);
      return "That code expired — request a new one.";
    }
    if (entry.attempts >= this.maxAttempts) {
      this.state.pop(key);
      return "Too many incorrect attempts — request a new code.";
    }
    if (submitted !== entry.code) {
      entry.attempts += 1;
      return "Incorrect code.";
    }
    this.state.pop(key);
    return null;
  }
}

/** Phones that just passed OTP verification and may finish signing up
 * once, within the TTL. */
class VerifiedFlags {
  constructor(ttlSeconds) {
    this.ttl = ttlSeconds;
    this.state = new BoundedMap();
  }

  mark(key) {
    this.state.set(key, wallClock() + this.ttl);
  }

  take(key) {
    const expiresAt = this.state.pop(key);
    return expiresAt !== undefined && wallClock() <= expiresAt;
  }
}

module.exports = {
  envInt,
  envFloat,
  BoundedMap,
  clientIp,
  authGate,
  authGateRecord,
  rateLimitPublic,
  rateLimitAuthenticated,
  globalRateLimit,
  fourDigitCode,
  OtpStore,
  VerifiedFlags,
};
