/*
 * Password/PIN hashing, byte-compatible with werkzeug.security — the
 * format the previous Python backend stored ("method$salt$hexhash"), so
 * accounts migrated from it keep working without a password reset.
 *
 * New hashes use werkzeug's own default, scrypt (n=2^15, r=8, p=1).
 */

const crypto = require("node:crypto");

const SALT_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const DEFAULT_PBKDF2_ITERATIONS = 600000;

function genSalt(length) {
  let out = "";
  for (let i = 0; i < length; i++) out += SALT_CHARS[crypto.randomInt(SALT_CHARS.length)];
  return out;
}

function hashInternal(method, salt, password) {
  const [name, ...args] = method.split(":");
  if (name === "scrypt") {
    const [n, r, p] = args.length ? args.map(Number) : [2 ** 15, 8, 1];
    const key = crypto.scryptSync(password, salt, 64, {
      N: n, r, p, maxmem: 132 * n * r * p,
    });
    return key.toString("hex");
  }
  if (name === "pbkdf2") {
    const digest = args[0] || "sha256";
    const iterations = args[1] ? Number(args[1]) : DEFAULT_PBKDF2_ITERATIONS;
    return crypto.pbkdf2Sync(password, salt, iterations, crypto.createHash(digest).digest().length, digest)
      .toString("hex");
  }
  throw new Error(`Unsupported hash method: ${method}`);
}

function generatePasswordHash(password) {
  const method = "scrypt:32768:8:1";
  const salt = genSalt(16);
  return `${method}$${salt}$${hashInternal(method, salt, password)}`;
}

function checkPasswordHash(pwhash, password) {
  if (typeof pwhash !== "string" || pwhash.split("$").length !== 3) return false;
  const [method, salt, hashval] = pwhash.split("$");
  let computed;
  try {
    computed = hashInternal(method, salt, password);
  } catch {
    return false;
  }
  const a = Buffer.from(computed);
  const b = Buffer.from(hashval);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

module.exports = { generatePasswordHash, checkPasswordHash };
