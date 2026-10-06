/*
 * Outbound integrations: Firebase ID-token verification and httpSMS.
 *
 * Exported as properties of one object (not bare functions) so the test
 * suite can swap them out — e.g. integrations.verifyFirebaseToken = ... —
 * without a real Firebase project or SMS gateway.
 */

const crypto = require("node:crypto");
const jwt = require("jsonwebtoken");

// The three native apps (Customer/Partner/Admin) sign in with Firebase Auth
// directly and send their Firebase ID token as the Bearer token. It's a
// standard RS256 JWT, verified here against Google's published certs — no
// firebase-admin dependency needed.
const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "rasoi-care";
const GOOGLE_CERTS_URL =
  "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com";
const certsCache = { certs: null, fetchedAt: 0 };

async function getFirebaseCerts() {
  // Google rotates these periodically; an hour's cache keeps every request
  // from re-fetching while still picking up rotations.
  if (certsCache.certs && Date.now() - certsCache.fetchedAt < 3600 * 1000) return certsCache.certs;
  try {
    const resp = await fetch(GOOGLE_CERTS_URL, { signal: AbortSignal.timeout(10000) });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    certsCache.certs = await resp.json();
    certsCache.fetchedAt = Date.now();
    return certsCache.certs;
  } catch {
    // Network hiccup — fall back to whatever we last had (possibly null,
    // in which case verification fails closed).
    return certsCache.certs;
  }
}

/** {uid, email, email_verified, name, phone_number} for a valid Firebase
 * ID token issued to this project, else null. Every rejection is logged
 * with its real reason, so a misconfiguration doesn't look identical to
 * a stale token. */
async function verifyFirebaseToken(idToken) {
  if (!idToken) return null;
  try {
    const decoded = jwt.decode(idToken, { complete: true });
    if (!decoded) throw new Error("not a JWT");
    const kid = decoded.header.kid;
    const certs = await getFirebaseCerts();
    if (!certs) {
      console.error("verifyFirebaseToken: could not fetch Google's certs");
      return null;
    }
    if (!(kid in certs)) {
      console.error(`verifyFirebaseToken: unknown key id ${JSON.stringify(kid)}`);
      return null;
    }
    const publicKey = new crypto.X509Certificate(certs[kid]).publicKey;
    const payload = jwt.verify(idToken, publicKey, {
      algorithms: ["RS256"],
      audience: FIREBASE_PROJECT_ID,
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
      clockTolerance: 10,
    });
    const uid = payload.user_id || payload.sub;
    if (!uid) {
      console.error("verifyFirebaseToken: token has no user_id/sub claim");
      return null;
    }
    return {
      uid,
      email: payload.email ?? null,
      // Only true once Firebase has confirmed the holder controls that
      // email — required before any bootstrap may match an existing row by
      // email, so a signup using someone else's unverified email can never
      // attach itself to their account.
      email_verified: Boolean(payload.email_verified),
      name: payload.name ?? null,
      // Only set for a phone-OTP sign-in, once Firebase has verified it.
      phone_number: payload.phone_number ?? null,
    };
  } catch (e) {
    console.error(`verifyFirebaseToken: rejected — ${e.message}`);
    return null;
  }
}

// httpSMS (https://httpsms.com) turns an Android phone with a SIM into an
// HTTP-callable SMS gateway. Entirely optional: with HTTPSMS_API_KEY /
// HTTPSMS_FROM_NUMBER unset, sending is a no-op that returns false.
const HTTPSMS_SEND_URL = "https://api.httpsms.com/v1/messages/send";

/** Best-effort — never throws, never something a response depends on. */
async function sendSms(toNumber, content, { requestId = null } = {}) {
  const apiKey = process.env.HTTPSMS_API_KEY;
  const fromNumber = process.env.HTTPSMS_FROM_NUMBER;
  if (!apiKey || !fromNumber || !toNumber) return false;
  try {
    const resp = await fetch(HTTPSMS_SEND_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-Key": apiKey },
      body: JSON.stringify({
        content, from: fromNumber, to: toNumber, request_id: requestId || crypto.randomUUID(),
      }),
      signal: AbortSignal.timeout(8000),
    });
    return resp.status >= 200 && resp.status < 300;
  } catch (e) {
    console.error(`httpSMS send failed: ${e.message}`);
    return false;
  }
}

module.exports = { verifyFirebaseToken, sendSms };
