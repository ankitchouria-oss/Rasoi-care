/*
 * RasoiCare backend — Express REST API.
 *
 * The server all the apps (Customer, Partner, Admin — native and web —
 * plus the legacy static HTML consoles) call over HTTP. Runs on any
 * Node.js host; on Hostinger it's a Node.js web app backed by the MySQL
 * database on the same server (see db.js and README.md).
 */

const path = require("node:path");
const crypto = require("node:crypto");
const express = require("express");
const jwt = require("jsonwebtoken");

const db = require("./db");
const { getDb, initDb, nextId, now, newUuidId } = db;
const { generatePasswordHash, checkPasswordHash } = require("./passwords");
const { Field, validateJson, PATTERNS: P } = require("./validation");
const rl = require("./ratelimit");
const integrations = require("./integrations");
const legal = require("./legal");

const { envInt, envFloat, authGate, authGateRecord, rateLimitPublic, rateLimitAuthenticated } = rl;

const FRONTEND_DIR = path.join(__dirname, "..");
// The largest legitimate request body is a base64 job photo (capped at
// 12,000,000 chars by its schema) — 16MB leaves headroom for the JSON
// envelope. Anything bigger is refused before it's buffered in memory.
const MAX_CONTENT_LENGTH = 16 * 1024 * 1024;

const LIST_PAGE_DEFAULT_LIMIT = envInt("LIST_PAGE_DEFAULT_LIMIT", 500);
const LIST_PAGE_MAX_LIMIT = envInt("LIST_PAGE_MAX_LIMIT", 2000);

// Booking-cancellation OTP and the Customer web app's phone sign-in OTP —
// in memory only: short-lived by design, and losing them on a restart just
// means requesting a fresh code.
const CANCEL_OTP_TTL_SECONDS = envInt("CANCEL_OTP_TTL_SECONDS", 300);
const cancelOtps = new rl.OtpStore(CANCEL_OTP_TTL_SECONDS, envInt("CANCEL_OTP_MAX_ATTEMPTS", 5));
const WEB_PHONE_OTP_TTL_SECONDS = envInt("WEB_PHONE_OTP_TTL_SECONDS", 300);
const webPhoneOtps = new rl.OtpStore(WEB_PHONE_OTP_TTL_SECONDS, envInt("WEB_PHONE_OTP_MAX_ATTEMPTS", 5));
const webPhoneVerified = new rl.VerifiedFlags(envInt("WEB_PHONE_VERIFIED_TTL_SECONDS", 600));

// Never a fixed, publicly-known fallback: without JWT_SECRET set, a fresh
// random secret is generated per process — no forgeable tokens, at the
// cost of signing everyone out on every restart until it's configured.
let JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
  JWT_SECRET = crypto.randomBytes(32).toString("hex");
  console.error(
    "WARNING: JWT_SECRET is not set — using a random secret generated for this process only. "
      + "Every existing session (customer and staff) will be signed out on the next restart. "
      + "Set JWT_SECRET in the environment for a stable production deployment.",
  );
}
const JWT_EXPIRY = "7d";

const STATUS_ORDER = ["Requested", "Accepted", "On the way", "In Progress", "Completed"];

// ---------------------------------------------------------------- small helpers
/** Python's round(): half-to-even, so every rupee/paise figure matches what
 * the previous backend (and the apps mirroring its maths) computed. */
function pyRound(x, ndigits = 0) {
  const scale = 10 ** ndigits;
  const v = x * scale;
  const floor = Math.floor(v);
  const diff = v - floor;
  let r;
  if (Math.abs(diff - 0.5) < 1e-9) r = floor % 2 === 0 ? floor : floor + 1;
  else r = Math.round(v);
  return r / scale;
}

const trimOrNull = (v) => (typeof v === "string" && v.trim() ? v.trim() : null);
const isNum = (v) => typeof v === "number" && Number.isFinite(v);

/** ISO timestamp -> Date. A value with no offset is taken as UTC. Null if
 * unparseable. */
function parseIso(s) {
  if (!s) return null;
  const hasTz = /(Z|[+-]\d{2}:\d{2})$/.test(s);
  const d = new Date(hasTz ? s : `${s}Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function isoSeconds(d) {
  return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function paginationArgs(req) {
  let limit = Number.parseInt(req.query.limit ?? LIST_PAGE_DEFAULT_LIMIT, 10);
  if (Number.isNaN(limit)) limit = LIST_PAGE_DEFAULT_LIMIT;
  limit = Math.max(1, Math.min(limit, LIST_PAGE_MAX_LIMIT));
  let offset = Number.parseInt(req.query.offset ?? 0, 10);
  if (Number.isNaN(offset)) offset = 0;
  return [limit, Math.max(0, offset)];
}

const notFound = (res) => res.status(404).json({ error: "not found" });

// ---------------------------------------------------------------- row mappers
// Joins in the technician's firebase_uid (the Customer app keys live-location
// watching off it) and the customer's phone alongside every bookings column.
const BOOKING_SELECT =
  "SELECT bookings.*, technicians.firebase_uid AS technician_firebase_uid, "
  + "users.phone AS customer_phone "
  + "FROM bookings LEFT JOIN technicians ON technicians.id = bookings.technician_id "
  + "LEFT JOIN users ON users.id = bookings.user_id";

const SERVICE_SELECT =
  "SELECT services.*, appliances.name AS appliance_name FROM services "
  + "JOIN appliances ON appliances.id = services.appliance_id";

const HEALTH_SELECT =
  "SELECT appliance_health.*, appliances.name AS appliance_name FROM appliance_health "
  + "JOIN appliances ON appliances.id = appliance_health.appliance_id";

const get = (row, key, fallback = null) => (row[key] === undefined ? fallback : row[key]);

function partRowToDict(row) {
  return {
    id: row.id,
    name: row.name,
    sku: row.sku,
    qty: row.qty,
    pricePaise: row.price_paise,
    status: row.status,
    createdAt: row.created_at,
    decidedAt: row.decided_at,
  };
}

function serviceChangeRowToDict(row) {
  return {
    id: row.id,
    oldService: row.old_service,
    newService: row.new_service,
    oldPricePaise: row.old_price * 100,
    newPricePaise: row.new_price * 100,
    createdAt: row.created_at,
  };
}

async function fetchBookingParts(conn, bookingId) {
  const rows = await conn.all("SELECT * FROM booking_parts WHERE booking_id = ? ORDER BY created_at", [bookingId]);
  return rows.map(partRowToDict);
}

async function fetchBookingServiceChanges(conn, bookingId) {
  const rows = await conn.all(
    "SELECT * FROM booking_service_changes WHERE booking_id = ? ORDER BY created_at", [bookingId],
  );
  return rows.map(serviceChangeRowToDict);
}

/** One query for every booking in a list response, grouped by booking id —
 * avoids an N+1 per row. */
async function fetchBulk(conn, table, bookingIds, mapper) {
  const out = new Map();
  if (!bookingIds.length) return out;
  const rows = await conn.all(
    `SELECT * FROM ${table} WHERE booking_id IN (${bookingIds.map(() => "?").join(",")}) ORDER BY created_at`,
    bookingIds,
  );
  for (const r of rows) {
    if (!out.has(r.booking_id)) out.set(r.booking_id, []);
    out.get(r.booking_id).push(mapper(r));
  }
  return out;
}

function bookingRowToDict(row, {
  includeStartCode = false, parts = null, serviceChanges = null, redactCustomerContact = false,
} = {}) {
  const d = {
    id: row.id,
    category: row.category,
    service: row.service,
    price: row.price,
    technicianId: row.technician_id,
    technicianFirebaseUid: get(row, "technician_firebase_uid"),
    customerName: row.customer_name,
    status: row.status,
    bachatSlot: row.bachat_slot,
    ratings: row.service_rating !== null ? { service: row.service_rating, tech: row.tech_rating } : null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    user_id: get(row, "user_id"),
    service_id: get(row, "service_id"),
    total_amount: "total_amount" in row ? row.total_amount : row.price,
    area: get(row, "area"),
    // The real street address behind the short `area` label ("Home").
    addressLine: get(row, "address_line"),
    // Which Partner service city this booking is in — see inferCity.
    city: get(row, "city"),
    lat: get(row, "lat"),
    lng: get(row, "lng"),
    suctionBefore: get(row, "suction_before"),
    suctionAfter: get(row, "suction_after"),
    timeOnSiteMin: get(row, "time_on_site_min"),
    cancelledAt: get(row, "cancelled_at"),
    cancellationFee: get(row, "cancellation_fee"),
    directions: get(row, "directions"),
    notes: get(row, "notes"),
    // What the customer actually ticked on the Issue screen — [] if nothing.
    issues: row.issues_json ? JSON.parse(row.issues_json) : [],
    paymentMethod: get(row, "payment_method"),
    brand: get(row, "brand"),
    modelNumber: get(row, "model_number"),
    parts: parts ?? [],
    serviceChanges: serviceChanges ?? [],
    scheduledAt: get(row, "scheduled_at"),
    customerPhone: get(row, "customer_phone"),
    // Only ever shown to the customer, who hands it to the technician in
    // person — advanceBooking refuses "In Progress" without it.
    startCode: includeStartCode ? get(row, "start_code") : null,
    beforePhotoReady: Boolean(row.before_photo_b64),
    afterPhotoReady: Boolean(row.after_photo_b64),
    signatureReady: Boolean(row.signature_b64),
  };
  if (redactCustomerContact) {
    // The broadcast "available requests" feed reaches every matching
    // technician before any is assigned; the privacy policy promises the
    // customer's exact location/phone aren't shared until one is.
    for (const f of ["addressLine", "lat", "lng", "directions", "notes", "customerPhone"]) d[f] = null;
  }
  return d;
}

function complaintRowToDict(row) {
  return {
    id: row.id,
    bookingId: row.booking_id,
    text: row.text,
    status: row.status,
    response: row.response,
    createdAt: row.created_at,
  };
}

/** A technician can be skilled in several categories (categories_json);
 * older rows only have the single `category` column. Always a list. */
function technicianCategories(row) {
  const raw = get(row, "categories_json");
  if (raw) {
    try {
      const cats = JSON.parse(raw);
      if (Array.isArray(cats) && cats.length) return cats;
    } catch {
      // fall through
    }
  }
  return row.category ? [row.category] : [];
}

function technicianRowToDict(row, { redactDocuments = false } = {}) {
  const d = {
    id: row.id,
    name: row.name,
    category: row.category,
    categories: technicianCategories(row),
    area: get(row, "area", ""),
    email: get(row, "email"),
    verified: "verified" in row ? Boolean(row.verified) : true,
    online: Boolean(row.online),
    rating: pyRound(row.rating, 1),
    ratingCount: row.rating_count,
    jobsCompleted: row.jobs_completed,
    photoUrl: get(row, "photo_url"),
    experienceYears: get(row, "experience_years"),
    idDocumentUrl: get(row, "id_document_url"),
    bankAccountName: get(row, "bank_account_name"),
    bankAccountNumber: get(row, "bank_account_number"),
    bankIfsc: get(row, "bank_ifsc"),
    panNumber: get(row, "pan_number"),
    aadharNumber: get(row, "aadhar_number"),
    dateOfBirth: get(row, "date_of_birth"),
    gstNumber: get(row, "gst_number"),
    emergencyContactName: get(row, "emergency_contact_name"),
    emergencyContactPhone: get(row, "emergency_contact_phone"),
    aadharDocumentUrl: get(row, "aadhar_document_url"),
    aadharDocumentBackUrl: get(row, "aadhar_document_back_url"),
    panDocumentUrl: get(row, "pan_document_url"),
    bankPassbookUrl: get(row, "bank_passbook_url"),
    address: get(row, "address"),
    upiId: get(row, "upi_id"),
    applicationSubmitted: "application_submitted" in row ? Boolean(row.application_submitted) : true,
    partnerCode: get(row, "partner_code"),
    // Self-declared once at KYC, never admin-editable — drives which
    // commission formula applies.
    employmentType: get(row, "employment_type", "outsourced"),
  };
  // Always present so the Admin app's "missing document" chips work even
  // when the URLs themselves are redacted below.
  d.aadharDocumentReady = Boolean(d.aadharDocumentUrl);
  d.aadharDocumentBackReady = Boolean(d.aadharDocumentBackUrl);
  d.panDocumentReady = Boolean(d.panDocumentUrl);
  d.bankPassbookReady = Boolean(d.bankPassbookUrl);
  if (redactDocuments) {
    // Long-lived Firebase Storage URLs whose only "auth" is a token in the
    // query string — staff view them through the authenticated document
    // proxy instead (see technicianDocument).
    for (const f of ["aadharDocumentUrl", "aadharDocumentBackUrl", "panDocumentUrl", "bankPassbookUrl"]) d[f] = null;
  }
  return d;
}

function userRowToDict(row) {
  return {
    id: row.id,
    email: row.email,
    name: row.name,
    phone: row.phone,
    created_at: row.created_at,
    coinsBalance: get(row, "coins_balance", 0),
  };
}

function shopOrderRowToDict(row) {
  return {
    id: row.id,
    items: JSON.parse(row.items_json),
    totalPaise: row.total_paise,
    status: row.status,
    createdAt: row.created_at,
  };
}

const applianceRowToDict = (row) => ({ id: row.id, name: row.name, category: row.category, mono: row.mono });

function serviceRowToDict(row) {
  return {
    id: row.id,
    appliance_id: row.appliance_id,
    appliance_name: row.appliance_name,
    category: row.category,
    name: row.name,
    price: row.price,
    quick_fix: Boolean(row.quick_fix),
  };
}

function staffRowToDict(row) {
  return {
    id: row.id,
    name: row.name,
    phone: row.phone,
    email: get(row, "email"),
    role: row.role,
    active: Boolean(row.active),
    createdAt: row.created_at,
  };
}

function inventoryRowToDict(row) {
  return {
    id: row.id,
    name: row.name,
    sku: row.sku,
    category: row.category,
    quantity: row.quantity,
    reorderLevel: row.reorder_level,
    lowStock: row.quantity < row.reorder_level,
    updatedAt: row.updated_at,
  };
}

function applianceHealthRowToDict(row) {
  return {
    id: row.id,
    appliance_id: row.appliance_id,
    appliance_name: row.appliance_name,
    metric_name: row.metric_name,
    value_pct: row.value_pct,
    status_label: row.status_label,
    updated_at: row.updated_at,
  };
}

// ---------------------------------------------------------------- auth
function generateToken(userId) {
  return jwt.sign({ sub: userId }, JWT_SECRET, { algorithm: "HS256", expiresIn: JWT_EXPIRY });
}

function generateStaffToken(staffId) {
  return jwt.sign({ sub: staffId, typ: "staff" }, JWT_SECRET, { algorithm: "HS256", expiresIn: JWT_EXPIRY });
}

function decodePayload(token) {
  try {
    return jwt.verify(token, JWT_SECRET, { algorithms: ["HS256"] });
  } catch {
    return null;
  }
}

/** User id from a valid backend-issued token, else null. */
function decodeToken(token) {
  return decodePayload(token)?.sub ?? null;
}

function decodeStaffToken(token) {
  const payload = decodePayload(token);
  return payload && payload.typ === "staff" ? payload.sub ?? null : null;
}

function getBearerToken(req) {
  const header = req.get("Authorization") || "";
  if (!header.startsWith("Bearer ")) return null;
  return header.slice("Bearer ".length).trim();
}

async function selectOne(sql, params) {
  const conn = await getDb();
  try {
    return await conn.get(sql, params);
  } finally {
    conn.close();
  }
}

/** The user row for a valid Bearer token (backend JWT or Firebase ID
 * token), or null — never rejects the request itself. */
async function getCurrentUserOptional(req) {
  const token = getBearerToken(req);
  if (!token) return null;
  const userId = decodeToken(token);
  if (userId) return selectOne("SELECT * FROM users WHERE id = ?", [userId]);
  const claims = await integrations.verifyFirebaseToken(token);
  if (claims) return selectOne("SELECT * FROM users WHERE firebase_uid = ?", [claims.uid]);
  return null;
}

async function getCurrentStaffOptional(req) {
  const token = getBearerToken(req);
  if (!token) return null;
  const staffId = decodeStaffToken(token);
  if (staffId) return selectOne("SELECT * FROM staff WHERE id = ?", [staffId]);
  const claims = await integrations.verifyFirebaseToken(token);
  if (claims) return selectOne("SELECT * FROM staff WHERE firebase_uid = ?", [claims.uid]);
  return null;
}

async function getCurrentTechnicianOptional(req) {
  const token = getBearerToken(req);
  if (!token) return null;
  const claims = await integrations.verifyFirebaseToken(token);
  if (!claims) return null;
  return selectOne("SELECT * FROM technicians WHERE firebase_uid = ?", [claims.uid]);
}

const TOO_MANY = { error: "Too Many Requests", message: "Slow down and try again shortly" };

async function requireAuth(req, res, next) {
  if (!getBearerToken(req)) return res.status(401).json({ error: "Unauthorized", message: "Missing bearer token" });
  const row = await getCurrentUserOptional(req);
  if (!row) return res.status(401).json({ error: "Unauthorized", message: "Invalid or expired token" });
  if (rateLimitAuthenticated(`user:${row.id}`)) return res.status(429).json(TOO_MANY);
  req.user = row;
  return next();
}

async function requireStaffAuth(req, res, next) {
  if (!getBearerToken(req)) return res.status(401).json({ error: "Unauthorized", message: "Missing bearer token" });
  const row = await getCurrentStaffOptional(req);
  if (!row || !row.active) {
    return res.status(401).json({ error: "Unauthorized", message: "Staff account not found or inactive" });
  }
  if (rateLimitAuthenticated(`staff:${row.id}`)) return res.status(429).json(TOO_MANY);
  req.staff = row;
  return next();
}

const requireOwner = [
  requireStaffAuth,
  (req, res, next) => {
    if (req.staff.role !== "owner") return res.status(403).json({ error: "Forbidden", message: "Owner role required" });
    return next();
  },
];

/** Technicians only ever authenticate via Firebase (the Partner app). */
async function requireTechnicianAuth(req, res, next) {
  const token = getBearerToken(req);
  const claims = token ? await integrations.verifyFirebaseToken(token) : null;
  if (!claims) return res.status(401).json({ error: "Unauthorized", message: "Invalid or missing Firebase token" });
  const row = await selectOne("SELECT * FROM technicians WHERE firebase_uid = ?", [claims.uid]);
  if (!row) {
    return res.status(401).json({
      error: "Unauthorized", message: "No technician profile — call /api/technician/bootstrap first",
    });
  }
  if (rateLimitAuthenticated(`tech:${row.id}`)) return res.status(429).json(TOO_MANY);
  req.technician = row;
  return next();
}

async function firebaseClaims(req) {
  const token = getBearerToken(req);
  return token ? integrations.verifyFirebaseToken(token) : null;
}

// ---------------------------------------------------------------- business rules
// The Partner app's five service cities (see careplus_partner's
// tech_apply_screen.dart) with each city's approximate centre.
const PARTNER_CITY_CENTERS = {
  Nashik: [19.9975, 73.7898],
  Pune: [18.5204, 73.8567],
  Mumbai: [19.076, 72.8777],
  Nagpur: [21.1458, 79.0882],
  Aurangabad: [19.8762, 75.3433],
};

/** Which service city a booking is in, for dispatch matching: nearest
 * city centre when coordinates were sent, else a substring match on the
 * address text, else null (visible to every matching-category technician). */
function inferCity(addressLine, lat, lng) {
  if (lat !== null && lng !== null) {
    let best = null;
    let bestDist = Infinity;
    for (const [city, [clat, clng]] of Object.entries(PARTNER_CITY_CENTERS)) {
      const dist = (clat - lat) ** 2 + (clng - lng) ** 2;
      if (dist < bestDist) {
        best = city;
        bestDist = dist;
      }
    }
    return best;
  }
  if (addressLine) {
    const lowered = addressLine.toLowerCase();
    for (const city of Object.keys(PARTNER_CITY_CENTERS)) {
      if (lowered.includes(city.toLowerCase())) return city;
    }
  }
  return null;
}

const CART_VISIT_FEE = 49;
const CART_COUPON_THRESHOLD = 1700;
const CART_COUPON_DISCOUNT = 200;
const CART_GST_RATE = 0.18;

// Cancellable at any of these statuses — not once Completed or Cancelled.
const CANCELLABLE_STATUSES = new Set(["Requested", "Accepted", "On the way", "In Progress"]);

// Tiered by how close the customer's scheduled slot is: more than 12h out
// is free, within 12h is ₹100, within 3h is ₹200 — credited to the
// technician, whose time was genuinely reserved.
const CANCELLATION_FEE_FAR_HOURS = envInt("CANCELLATION_FEE_FAR_HOURS", 12);
const CANCELLATION_FEE_NEAR_HOURS = envInt("CANCELLATION_FEE_NEAR_HOURS", 3);
const CANCELLATION_FEE_FAR_RUPEES = envInt("CANCELLATION_FEE_FAR_RUPEES", 100);
const CANCELLATION_FEE_NEAR_RUPEES = envInt("CANCELLATION_FEE_NEAR_RUPEES", 200);
// Fallback for bookings with no scheduled_at, tiered by progress instead.
const CANCELLATION_FEE_BY_STATUS_FALLBACK = {
  Requested: 0,
  Accepted: CANCELLATION_FEE_FAR_RUPEES,
  "On the way": CANCELLATION_FEE_NEAR_RUPEES,
  "In Progress": CANCELLATION_FEE_NEAR_RUPEES,
};

// Technician commission, by self-declared employment type. Both rates
// apply to the booking total with GST backed out and the flat visit fee
// removed — e.g. ₹1,944 -> /1.18 = ₹1,648 -> minus ₹49 = ₹1,599.
const GST_RATE = envFloat("GST_RATE", 0.18);
const PAYROLL_COMMISSION_RATE = envFloat("PAYROLL_COMMISSION_RATE", 0.1);
const OUTSOURCED_COMMISSION_RATE = envFloat("OUTSOURCED_COMMISSION_RATE", 0.6);
// Must match kVisitFeePaise in careplus_flutter/lib/state/providers.dart.
const VISIT_CHARGE_PAISE = envInt("VISIT_CHARGE_PAISE", 4900);

// Auto-computed ledger entries, fired deterministically off real activity.
const WEEKLY_JOBS_FOR_BONUS = envInt("WEEKLY_JOBS_FOR_BONUS", 15);
const WEEKLY_BONUS_PAISE = envInt("WEEKLY_BONUS_PAISE", 20000);
const MONTHLY_JOBS_FOR_BONUS = envInt("MONTHLY_JOBS_FOR_BONUS", 75);
const MONTHLY_BONUS_PAISE = envInt("MONTHLY_BONUS_PAISE", 50000);
const LATE_ARRIVAL_GRACE_MINUTES = envInt("LATE_ARRIVAL_GRACE_MINUTES", 60);
const LATE_ARRIVAL_FINE_PAISE = envInt("LATE_ARRIVAL_FINE_PAISE", 5000);

/** Monday 00:00:00 UTC of d's calendar week. */
function weekStartIso(d) {
  const start = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  start.setUTCDate(start.getUTCDate() - ((start.getUTCDay() + 6) % 7));
  return isoSeconds(start);
}

function monthStartIso(d) {
  return isoSeconds(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1)));
}

function commissionRate(employmentType) {
  return employmentType === "payroll" ? PAYROLL_COMMISSION_RATE : OUTSOURCED_COMMISSION_RATE;
}

function computeCommissionPaise(totalAmountRupees, employmentType) {
  if (!totalAmountRupees) return 0;
  const basicPaise = pyRound((totalAmountRupees * 100) / (1 + GST_RATE));
  const billablePaise = Math.max(0, basicPaise - VISIT_CHARGE_PAISE);
  return pyRound(billablePaise * commissionRate(employmentType));
}

async function countCompletedSince(conn, technicianId, sinceIso) {
  const row = await conn.get(
    "SELECT COUNT(*) AS n FROM bookings WHERE technician_id = ? AND status = 'Completed' AND updated_at >= ?",
    [technicianId, sinceIso],
  );
  return Number(row.n);
}

/** Itemized earnings: a commission per completed job (computed fresh, never
 * stored) plus every ledger entry. Shared by the technician's own endpoint
 * and the staff one so both always agree. */
async function technicianEarningsPayload(conn, tech) {
  const employmentType = get(tech, "employment_type", "outsourced");
  const bookings = await conn.all(
    "SELECT id, service, total_amount, updated_at FROM bookings "
      + "WHERE technician_id = ? AND status = 'Completed' ORDER BY updated_at DESC",
    [tech.id],
  );
  let commissionTotalPaise = 0;
  const jobs = bookings.map((b) => {
    const commissionPaise = computeCommissionPaise(b.total_amount, employmentType);
    commissionTotalPaise += commissionPaise;
    return {
      bookingId: b.id,
      service: b.service,
      totalAmountPaise: (b.total_amount || 0) * 100,
      commissionPaise,
      completedAt: b.updated_at,
    };
  });
  const ledgerRows = await conn.all(
    "SELECT * FROM technician_ledger WHERE technician_id = ? ORDER BY created_at DESC", [tech.id],
  );
  const ledger = ledgerRows.map((r) => ({
    id: r.id,
    bookingId: r.booking_id,
    kind: r.kind,
    amountPaise: r.amount_paise,
    reason: r.reason,
    createdAt: r.created_at,
  }));
  const sum = (rows) => rows.reduce((acc, r) => acc + r.amount_paise, 0);
  const t = new Date();
  return {
    employmentType,
    commissionRate: commissionRate(employmentType),
    visitChargePaise: VISIT_CHARGE_PAISE,
    jobs,
    commissionTotalPaise,
    ledger,
    incentiveTotalPaise: sum(ledgerRows.filter((r) => r.kind === "incentive")),
    fineTotalPaise: sum(ledgerRows.filter((r) => r.kind === "fine")),
    netTotalPaise: commissionTotalPaise + sum(ledgerRows),
    jobsCompletedThisWeek: await countCompletedSince(conn, tech.id, weekStartIso(t)),
    jobsCompletedThisMonth: await countCompletedSince(conn, tech.id, monthStartIso(t)),
    weeklyJobsForBonus: WEEKLY_JOBS_FOR_BONUS,
    weeklyBonusPaise: WEEKLY_BONUS_PAISE,
    monthlyJobsForBonus: MONTHLY_JOBS_FOR_BONUS,
    monthlyBonusPaise: MONTHLY_BONUS_PAISE,
    lateArrivalGraceMinutes: LATE_ARRIVAL_GRACE_MINUTES,
    lateArrivalFinePaise: LATE_ARRIVAL_FINE_PAISE,
  };
}

/** The fee (rupees) cancelling `row` right now would apply. Never throws. */
function cancellationFeeFor(row) {
  const fallback = CANCELLATION_FEE_BY_STATUS_FALLBACK[row.status] ?? 0;
  const scheduled = parseIso(get(row, "scheduled_at"));
  if (!scheduled) return fallback;
  const hoursLeft = (scheduled.getTime() - Date.now()) / 3600000;
  if (hoursLeft > CANCELLATION_FEE_FAR_HOURS) return 0;
  if (hoursLeft > CANCELLATION_FEE_NEAR_HOURS) return CANCELLATION_FEE_FAR_RUPEES;
  return CANCELLATION_FEE_NEAR_RUPEES;
}

const SHOP_PRODUCTS = {
  chimney_kit: { name: "Chimney Cleaning Kit", price_paise: 14900 },
  cooktop_kit: { name: "Cooktop & Hob Cleaning Kit", price_paise: 11900 },
  dishwasher_kit: { name: "Dishwasher Cleaning Kit", price_paise: 12900 },
  microwave_kit: { name: "Microwave Cleaning Kit", price_paise: 11900 },
  refrigerator_kit: { name: "Refrigerator Cleaning Kit", price_paise: 9900 },
};

// Mirrors homeservices.html's SERVICES list — Home Services bookings are
// priced from here, never from the client.
const HS_SERVICES = {
  "water-purifier": ["Water Purifier", 399],
  otg: ["OTG", 449],
  hob: ["Hob & Cooktop", 499],
  microwave: ["Microwave", 549],
  chimney: ["Chimney", 599],
  fridge: ["Refrigerator", 649],
  dishwasher: ["Dishwasher", 699],
};

const PERIOD_DAYS = { week: 7, month: 30, quarter: 90 };
const TECH_PAYOUT_RATE = 0.65; // assumed share of revenue paid out — not a real ledger figure

// Only Firebase Storage's own hosts — the URLs come from a technician's
// own profile, so without an allowlist the document proxy would be an SSRF.
const DOCUMENT_PROXY_ALLOWED_HOSTS = ["firebasestorage.googleapis.com", "storage.googleapis.com"];
const DOCUMENT_PROXY_FIELD_BY_KIND = {
  "aadhar-front": "aadhar_document_url",
  "aadhar-back": "aadhar_document_back_url",
  pan: "pan_document_url",
  "bank-passbook": "bank_passbook_url",
};

// Excludes 0/O and 1/I — easy to confuse when read aloud or copied by hand.
const PARTNER_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const PHOTO_MIME = { before: "image/jpeg", after: "image/jpeg", signature: "image/png" };

const sendSms = (...args) => integrations.sendSms(...args);

// ---------------------------------------------------------------- app
const app = express();
app.disable("x-powered-by");
app.set("etag", false);

app.use((req, res, next) => {
  res.set({
    "Strict-Transport-Security": "max-age=63072000; includeSubDomains",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  next();
});

app.use(rl.globalRateLimit);

// Every body is read as raw bytes and parsed as JSON regardless of
// Content-Type (clients don't always set it); anything that isn't valid
// JSON becomes null, which validateJson rejects with a 400.
app.use(express.raw({ type: () => true, limit: MAX_CONTENT_LENGTH }));
app.use((req, res, next) => {
  let parsed = null;
  if (Buffer.isBuffer(req.body) && req.body.length) {
    try {
      parsed = JSON.parse(req.body.toString("utf8"));
    } catch {
      parsed = null;
    }
  }
  req.body = parsed;
  next();
});

const body = (req) => (req.body && typeof req.body === "object" && !Array.isArray(req.body) ? req.body : {});

// ---------------------------------------------------------------- static pages
for (const [route, file] of [
  ["/", "index.html"],
  ["/customer", "customer.html"],
  ["/technician", "technician.html"],
  ["/admin", "admin.html"],
  ["/smiler", "smiler.html"],
  ["/homeservices", "homeservices.html"],
]) {
  app.get(route, (req, res) => res.sendFile(path.join(FRONTEND_DIR, file)));
}

app.get("/api/legal/terms", rateLimitPublic, (req, res) => {
  res.json(legal.legalDocPayload("Terms of Service", legal.TERMS_OF_SERVICE_SECTIONS));
});

app.get("/api/legal/privacy", rateLimitPublic, (req, res) => {
  res.json(legal.legalDocPayload("Privacy Policy", legal.PRIVACY_POLICY_SECTIONS));
});

app.get("/terms", (req, res) => {
  res.type("text/html").send(legal.legalDocHtml("Terms of Service", legal.TERMS_OF_SERVICE_SECTIONS));
});

app.get("/privacy", (req, res) => {
  res.type("text/html").send(legal.legalDocHtml("Privacy Policy", legal.PRIVACY_POLICY_SECTIONS));
});

app.options(/^\/api\/.+/, (req, res) => res.status(204).end());

// ---------------------------------------------------------------- staff
app.post(
  "/api/staff/login",
  validateJson({
    phone: new Field("str", { required: true, pattern: P.PHONE }),
    pin: new Field("str", { required: true, pattern: P.PIN, strip: false }),
  }),
  async (req, res) => {
    // PINs are short — AUTH tier, gated per phone and per IP with backoff.
    const data = body(req);
    const phone = (data.phone || "").trim();
    const pin = data.pin || "";
    if (authGate(req, res, phone)) return;
    const row = await selectOne("SELECT * FROM staff WHERE phone = ?", [phone]);
    const ok = Boolean(row && row.active && checkPasswordHash(row.pin_hash, pin));
    authGateRecord(req, phone, ok);
    if (!ok) return res.status(401).json({ error: "Invalid phone or PIN" });
    return res.json({ token: generateStaffToken(row.id), staff: staffRowToDict(row) });
  },
);

app.get("/api/staff/me", requireStaffAuth, (req, res) => res.json(staffRowToDict(req.staff)));

app.post(
  "/api/staff/bootstrap",
  validateJson({
    name: new Field("str", { maxLen: 100 }),
    role: new Field("str", { choices: ["owner", "staff"] }),
  }),
  async (req, res) => {
    // Called right after Firebase sign-in in the Admin app. The very first
    // staff member ever becomes owner; everyone after is plain staff,
    // whatever `role` they send — only an owner's invite can mint an owner.
    const claims = await firebaseClaims(req);
    if (!claims) return res.status(401).json({ error: "Unauthorized", message: "Invalid or missing Firebase token" });
    const data = body(req);
    const name = (data.name || claims.name || "").trim() || "Staff";
    const conn = await getDb();
    try {
      let row = await conn.get("SELECT * FROM staff WHERE firebase_uid = ?", [claims.uid]);
      if (!row && claims.email && claims.email_verified) {
        row = await conn.get("SELECT * FROM staff WHERE email = ?", [claims.email]);
      }
      let staffId;
      if (row) {
        await conn.run("UPDATE staff SET firebase_uid = ?, name = ? WHERE id = ?", [claims.uid, name, row.id]);
        staffId = row.id;
      } else {
        const anyStaff = await conn.get("SELECT 1 AS x FROM staff LIMIT 1");
        staffId = newUuidId("STF");
        await conn.run(
          "INSERT INTO staff (id, name, phone, email, pin_hash, role, active, created_at, firebase_uid) "
            + "VALUES (?,?,?,?,?,?,1,?,?)",
          [staffId, name, `fb-${claims.uid.slice(0, 24)}`, claims.email, "firebase-auth",
            anyStaff ? "staff" : "owner", now(), claims.uid],
        );
      }
      await conn.commit();
      row = await conn.get("SELECT * FROM staff WHERE id = ?", [staffId]);
      if (!row.active) {
        return res.status(401).json({ error: "Unauthorized", message: "Staff account not found or inactive" });
      }
      return res.json(staffRowToDict(row));
    } finally {
      conn.close();
    }
  },
);

app.get("/api/staff", requireStaffAuth, async (req, res) => {
  const conn = await getDb();
  try {
    res.json((await conn.all("SELECT * FROM staff ORDER BY name")).map(staffRowToDict));
  } finally {
    conn.close();
  }
});

app.post(
  "/api/staff",
  requireOwner,
  validateJson({
    name: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    phone: new Field("str", { required: true, pattern: P.PHONE }),
    pin: new Field("str", { required: true, pattern: P.PIN, strip: false }),
    role: new Field("str", { choices: ["owner", "staff"] }),
  }),
  async (req, res) => {
    const data = body(req);
    const name = (data.name || "").trim();
    const phone = (data.phone || "").trim();
    const pin = data.pin || "";
    const role = data.role || "staff";
    if (!name || !phone || pin.length < 4) {
      return res.status(400).json({ error: "name, phone, and a pin of at least 4 digits are required" });
    }
    if (!["owner", "staff"].includes(role)) return res.status(400).json({ error: "role must be 'owner' or 'staff'" });
    const conn = await getDb();
    try {
      if (await conn.get("SELECT id FROM staff WHERE phone = ?", [phone])) {
        return res.status(409).json({ error: "A staff account with this phone already exists" });
      }
      const staffId = newUuidId("STF");
      await conn.run(
        "INSERT INTO staff (id, name, phone, pin_hash, role, active, created_at) VALUES (?,?,?,?,?,1,?)",
        [staffId, name, phone, generatePasswordHash(pin), role, now()],
      );
      await conn.commit();
      return res.status(201).json(staffRowToDict(await conn.get("SELECT * FROM staff WHERE id = ?", [staffId])));
    } finally {
      conn.close();
    }
  },
);

app.patch(
  "/api/staff/:staffId",
  requireOwner,
  validateJson({
    role: new Field("str", { choices: ["owner", "staff"] }),
    active: new Field("bool"),
  }),
  async (req, res) => {
    const data = body(req);
    const { staffId } = req.params;
    const conn = await getDb();
    try {
      let row = await conn.get("SELECT * FROM staff WHERE id = ?", [staffId]);
      if (!row) return notFound(res);
      const role = "role" in data ? data.role : row.role;
      const active = typeof data.active === "boolean" ? Number(data.active) : row.active;
      if (!["owner", "staff"].includes(role)) return res.status(400).json({ error: "role must be 'owner' or 'staff'" });
      await conn.run("UPDATE staff SET role = ?, active = ? WHERE id = ?", [role, active, staffId]);
      await conn.commit();
      row = await conn.get("SELECT * FROM staff WHERE id = ?", [staffId]);
      return res.json(staffRowToDict(row));
    } finally {
      conn.close();
    }
  },
);

// ---------------------------------------------------------------- customer auth
app.post(
  "/api/auth/register",
  validateJson({
    email: new Field("str", { required: true, maxLen: 254, pattern: P.EMAIL }),
    password: new Field("str", { required: true, minLen: 6, maxLen: 128, strip: false }),
    name: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    phone: new Field("str", { pattern: P.PHONE }),
  }),
  async (req, res) => {
    // AUTH tier — gated per email and per IP; there's no legitimate reason
    // to hit registration repeatedly in a short window.
    const data = body(req);
    const email = (data.email || "").trim().toLowerCase();
    const password = data.password || "";
    const name = (data.name || "").trim();
    const phone = data.phone ?? null;
    if (authGate(req, res, email)) return;
    if (!email || !P.EMAIL.test(email)) {
      authGateRecord(req, email, false);
      return res.status(400).json({ error: "A valid email is required" });
    }
    if (password.length < 6) {
      authGateRecord(req, email, false);
      return res.status(400).json({ error: "Password must be at least 6 characters" });
    }
    if (!name) {
      authGateRecord(req, email, false);
      return res.status(400).json({ error: "Name is required" });
    }
    const conn = await getDb();
    try {
      if (await conn.get("SELECT id FROM users WHERE email = ?", [email])) {
        authGateRecord(req, email, false);
        return res.status(409).json({ error: "Email already registered" });
      }
      const userId = newUuidId("USR");
      await conn.run(
        "INSERT INTO users (id, email, password_hash, name, phone, created_at) VALUES (?,?,?,?,?,?)",
        [userId, email, generatePasswordHash(password), name, phone, now()],
      );
      await conn.commit();
      const row = await conn.get("SELECT * FROM users WHERE id = ?", [userId]);
      authGateRecord(req, email, true);
      return res.status(201).json({ token: generateToken(userId), user: userRowToDict(row) });
    } finally {
      conn.close();
    }
  },
);

app.post(
  "/api/auth/login",
  validateJson({
    email: new Field("str", { required: true, maxLen: 254, pattern: P.EMAIL }),
    password: new Field("str", { required: true, minLen: 1, maxLen: 128, strip: false }),
  }),
  async (req, res) => {
    const data = body(req);
    const email = (data.email || "").trim().toLowerCase();
    const password = data.password || "";
    if (authGate(req, res, email)) return;
    const row = await selectOne("SELECT * FROM users WHERE email = ?", [email]);
    const ok = Boolean(row && checkPasswordHash(row.password_hash, password));
    authGateRecord(req, email, ok);
    if (!ok) return res.status(401).json({ error: "Invalid email or password" });
    return res.json({ token: generateToken(row.id), user: userRowToDict(row) });
  },
);

app.post(
  "/api/auth/phone/send-otp",
  validateJson({ phone: new Field("str", { required: true, pattern: P.PHONE }) }),
  async (req, res) => {
    // The Customer web app's phone sign-in. AUTH tier, so it can't be used
    // to enumerate numbers or burn the SMS budget.
    const { phone } = body(req);
    const key = `webphone:${phone}`;
    if (authGate(req, res, key)) return;
    const code = webPhoneOtps.request(phone);
    const sent = await sendSms(
      `+91${phone}`,
      `Rasoi Care: your sign-in code is ${code}. It expires in ${Math.floor(WEB_PHONE_OTP_TTL_SECONDS / 60)} minutes.`,
      { requestId: `webphone-${phone}` },
    );
    authGateRecord(req, key, true);
    if (!sent) {
      return res.json({ sent: false, message: "We couldn't text you a code just now — try again in a moment." });
    }
    return res.json({ sent: true });
  },
);

app.post(
  "/api/auth/phone/verify-otp",
  validateJson({
    phone: new Field("str", { required: true, pattern: P.PHONE }),
    otp: new Field("str", { required: true, pattern: P.CODE, strip: false }),
  }),
  async (req, res) => {
    // An existing account with this phone logs straight in; otherwise the
    // phone is marked verified so /register can finish without a second code.
    const { phone, otp } = body(req);
    const key = `webphone:${phone}`;
    if (authGate(req, res, key)) return;
    const error = webPhoneOtps.verify(phone, otp, "Request a code first.");
    authGateRecord(req, key, error === null);
    if (error) return res.status(400).json({ error: "Invalid code", message: error });
    webPhoneVerified.mark(phone);
    const row = await selectOne("SELECT * FROM users WHERE phone = ?", [phone]);
    if (row) return res.json({ token: generateToken(row.id), user: userRowToDict(row) });
    return res.json({ needsRegistration: true });
  },
);

app.post(
  "/api/auth/phone/register",
  validateJson({
    phone: new Field("str", { required: true, pattern: P.PHONE }),
    name: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    email: new Field("str", { maxLen: 254, pattern: P.EMAIL }),
  }),
  async (req, res) => {
    // The new account's password is a random secret never disclosed
    // anywhere — sign-in only ever happens through phone OTP again.
    const data = body(req);
    const { phone } = data;
    const name = data.name.trim();
    const email = (data.email || "").trim().toLowerCase() || `${phone}@rasoicare.demo`;
    if (!webPhoneVerified.take(phone)) {
      return res.status(400).json({ error: "Phone not verified", message: "Verify your phone with a fresh code first." });
    }
    const conn = await getDb();
    try {
      const existing = await conn.get("SELECT * FROM users WHERE phone = ?", [phone]);
      if (existing) return res.json({ token: generateToken(existing.id), user: userRowToDict(existing) });
      if (await conn.get("SELECT id FROM users WHERE email = ?", [email])) {
        return res.status(409).json({ error: "Email already registered" });
      }
      const userId = newUuidId("USR");
      await conn.run(
        "INSERT INTO users (id, email, password_hash, name, phone, created_at) VALUES (?,?,?,?,?,?)",
        [userId, email, generatePasswordHash(crypto.randomBytes(32).toString("base64url")), name, phone, now()],
      );
      await conn.commit();
      const row = await conn.get("SELECT * FROM users WHERE id = ?", [userId]);
      return res.status(201).json({ token: generateToken(userId), user: userRowToDict(row) });
    } finally {
      conn.close();
    }
  },
);

app.get("/api/auth/me", requireAuth, (req, res) => res.json(userRowToDict(req.user)));

app.post(
  "/api/me/bootstrap",
  validateJson({
    name: new Field("str", { maxLen: 100 }),
    phone: new Field("str", { pattern: P.PHONE }),
  }),
  async (req, res) => {
    // Called right after Firebase sign-in in the Customer app. Finds or
    // creates the matching users row (by Firebase uid, falling back to a
    // *verified* email so an old password account keeps its history).
    const claims = await firebaseClaims(req);
    if (!claims) return res.status(401).json({ error: "Unauthorized", message: "Invalid or missing Firebase token" });
    const data = body(req);
    const name = (data.name || claims.name || "").trim() || "Customer";
    // A Firebase-verified phone beats whatever the client claims.
    const phone = claims.phone_number || data.phone || null;
    const conn = await getDb();
    try {
      let row = await conn.get("SELECT * FROM users WHERE firebase_uid = ?", [claims.uid]);
      if (!row && claims.email && claims.email_verified) {
        row = await conn.get("SELECT * FROM users WHERE email = ?", [claims.email]);
      }
      let userId;
      if (row) {
        await conn.run(
          "UPDATE users SET firebase_uid = ?, name = ?, phone = COALESCE(?, phone) WHERE id = ?",
          [claims.uid, name, phone, row.id],
        );
        userId = row.id;
      } else {
        userId = newUuidId("USR");
        // An unverified email can't become this row's email either (UNIQUE,
        // and it may already belong to someone else's real account).
        const safeEmail = claims.email_verified ? claims.email : null;
        await conn.run(
          "INSERT INTO users (id, email, password_hash, name, phone, created_at, firebase_uid) VALUES (?,?,?,?,?,?,?)",
          [userId, safeEmail || `${claims.uid}@firebase.local`, "firebase-auth", name, phone, now(), claims.uid],
        );
      }
      await conn.commit();
      return res.json(userRowToDict(await conn.get("SELECT * FROM users WHERE id = ?", [userId])));
    } finally {
      conn.close();
    }
  },
);

// ---------------------------------------------------------------- shop
app.post(
  "/api/shop/orders",
  requireAuth,
  validateJson({ items: new Field("list", { required: true, minLen: 1, maxLen: 50, itemType: "dict" }) }),
  async (req, res) => {
    // Prices come from SHOP_PRODUCTS, never the client. Pay-on-delivery:
    // placing the order just records it for fulfilment.
    const { items } = body(req);
    if (!Array.isArray(items) || !items.length) return res.status(400).json({ error: "items must be a non-empty list" });
    const orderItems = [];
    let totalPaise = 0;
    for (const entry of items) {
      const productId = entry.productId ?? null;
      const product = Object.hasOwn(SHOP_PRODUCTS, productId) ? SHOP_PRODUCTS[productId] : null;
      if (!product) return res.status(400).json({ error: `Unknown product: ${productId}` });
      const qty = Number(entry.qty ?? 0);
      if (!Number.isFinite(qty)) return res.status(400).json({ error: "qty must be a whole number" });
      const wholeQty = Math.trunc(qty);
      if (wholeQty <= 0) return res.status(400).json({ error: "qty must be positive" });
      const subtotal = product.price_paise * wholeQty;
      orderItems.push({
        productId, name: product.name, qty: wholeQty, unitPricePaise: product.price_paise, subtotalPaise: subtotal,
      });
      totalPaise += subtotal;
    }
    const orderId = newUuidId("ORD");
    const conn = await getDb();
    try {
      await conn.run(
        "INSERT INTO shop_orders (id, user_id, items_json, total_paise, status, created_at) VALUES (?,?,?,?,?,?)",
        [orderId, req.user.id, JSON.stringify(orderItems), totalPaise, "Placed", now()],
      );
      await conn.commit();
      return res.status(201).json(shopOrderRowToDict(await conn.get("SELECT * FROM shop_orders WHERE id = ?", [orderId])));
    } finally {
      conn.close();
    }
  },
);

app.get("/api/shop/orders", requireAuth, async (req, res) => {
  const conn = await getDb();
  try {
    const rows = await conn.all("SELECT * FROM shop_orders WHERE user_id = ? ORDER BY created_at DESC", [req.user.id]);
    res.json(rows.map(shopOrderRowToDict));
  } finally {
    conn.close();
  }
});

app.post(
  "/api/me/coins/redeem",
  requireAuth,
  validateJson({ amount: new Field("int", { required: true, minVal: 1, maxVal: 1000000 }) }),
  async (req, res) => {
    const amount = Math.trunc(Number(body(req).amount ?? 0));
    if (!Number.isFinite(amount)) return res.status(400).json({ error: "amount must be a whole number of coins" });
    if (amount <= 0) return res.status(400).json({ error: "amount must be positive" });
    const conn = await getDb();
    try {
      // Check-and-decrement in one statement, so two concurrent requests
      // can't both spend the same coins.
      const cur = await conn.run(
        "UPDATE users SET coins_balance = coins_balance - ? WHERE id = ? AND coins_balance >= ?",
        [amount, req.user.id, amount],
      );
      await conn.commit();
      if (cur.changes === 0) return res.status(400).json({ error: "Not enough Care Coins" });
      return res.json(userRowToDict(await conn.get("SELECT * FROM users WHERE id = ?", [req.user.id])));
    } finally {
      conn.close();
    }
  },
);

// ---------------------------------------------------------------- catalog
app.get("/api/health", rateLimitPublic, (req, res) => res.json({ ok: true, service: "rasoicare-backend" }));

app.get("/api/appliances", rateLimitPublic, async (req, res) => {
  const { category } = req.query;
  const conn = await getDb();
  try {
    const rows = category
      ? await conn.all("SELECT * FROM appliances WHERE category = ? ORDER BY name", [String(category)])
      : await conn.all("SELECT * FROM appliances ORDER BY name");
    res.json(rows.map(applianceRowToDict));
  } finally {
    conn.close();
  }
});

app.get("/api/appliances/:applianceId", rateLimitPublic, async (req, res) => {
  const row = await selectOne("SELECT * FROM appliances WHERE id = ?", [req.params.applianceId]);
  if (!row) return res.status(404).json({ error: "Appliance not found" });
  return res.json(applianceRowToDict(row));
});

app.get("/api/services", rateLimitPublic, async (req, res) => {
  const { category } = req.query;
  const quickFix = req.query.quick_fix;
  const clauses = [];
  const params = [];
  if (category) {
    clauses.push("services.category = ?");
    params.push(String(category));
  }
  if (quickFix !== undefined) {
    clauses.push("services.quick_fix = ?");
    params.push(["true", "1", "yes"].includes(String(quickFix).toLowerCase()) ? 1 : 0);
  }
  let sql = SERVICE_SELECT;
  if (clauses.length) sql += ` WHERE ${clauses.join(" AND ")}`;
  sql += " ORDER BY services.name";
  const conn = await getDb();
  try {
    res.json((await conn.all(sql, params)).map(serviceRowToDict));
  } finally {
    conn.close();
  }
});

app.get("/api/services/:serviceId", rateLimitPublic, async (req, res) => {
  const row = await selectOne(`${SERVICE_SELECT} WHERE services.id = ?`, [req.params.serviceId]);
  if (!row) return res.status(404).json({ error: "Service not found" });
  return res.json(serviceRowToDict(row));
});

// ---------------------------------------------------------------- kitchen health score
app.get("/api/health-score", requireAuth, async (req, res) => {
  const conn = await getDb();
  try {
    const rows = await conn.all(
      `${HEALTH_SELECT} WHERE appliance_health.user_id = ? ORDER BY appliance_health.updated_at DESC`,
      [req.user.id],
    );
    res.json(rows.map(applianceHealthRowToDict));
  } finally {
    conn.close();
  }
});

app.post(
  "/api/bookings/:bookingId/health-update",
  requireTechnicianAuth,
  validateJson({
    metric_name: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    status_label: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    value_pct: new Field("int", { required: true, minVal: 0, maxVal: 100 }),
  }),
  async (req, res) => {
    // Only the technician assigned to this booking can post its health
    // update. 404 (not 403) everywhere so sequential ids can't be probed.
    const data = body(req);
    const metricName = data.metric_name.trim();
    const statusLabel = data.status_label.trim();
    const { bookingId } = req.params;
    const conn = await getDb();
    try {
      const booking = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      if (!booking || booking.technician_id !== req.technician.id) return notFound(res);
      if (!booking.user_id) return res.status(400).json({ error: "This booking has no associated user account" });
      let applianceId = null;
      if (booking.service_id) {
        const s = await conn.get("SELECT appliance_id FROM services WHERE id = ?", [booking.service_id]);
        if (s) applianceId = s.appliance_id;
      }
      if (!applianceId) {
        // Legacy bookings (Bachat Package etc.) have no service_id — fall
        // back to the first appliance in the booking's category family.
        const fallback = await conn.get("SELECT id FROM appliances WHERE category = ? LIMIT 1", [booking.category]);
        applianceId = fallback ? fallback.id : null;
      }
      if (!applianceId) return res.status(400).json({ error: "Could not resolve an appliance for this booking" });
      const upsert = conn.dialect === "mysql"
        ? "ON DUPLICATE KEY UPDATE metric_name = VALUES(metric_name), value_pct = VALUES(value_pct), "
          + "status_label = VALUES(status_label), updated_at = VALUES(updated_at)"
        : "ON CONFLICT(user_id, appliance_id) DO UPDATE SET metric_name=excluded.metric_name, "
          + "value_pct=excluded.value_pct, status_label=excluded.status_label, updated_at=excluded.updated_at";
      await conn.run(
        "INSERT INTO appliance_health (id, user_id, appliance_id, metric_name, value_pct, status_label, updated_at) "
          + `VALUES (?,?,?,?,?,?,?) ${upsert}`,
        [newUuidId("HEALTH"), booking.user_id, applianceId, metricName, data.value_pct, statusLabel, now()],
      );
      await conn.commit();
      const row = await conn.get(
        `${HEALTH_SELECT} WHERE appliance_health.user_id = ? AND appliance_health.appliance_id = ?`,
        [booking.user_id, applianceId],
      );
      return res.status(201).json(applianceHealthRowToDict(row));
    } finally {
      conn.close();
    }
  },
);

// ---------------------------------------------------------------- bookings
app.get("/api/bookings", async (req, res) => {
  // A customer token scopes to that customer's own bookings; a staff token
  // gets the full (paginated) ops list. No token, no data.
  const user = await getCurrentUserOptional(req);
  const staff = user ? null : await getCurrentStaffOptional(req);
  if (!user && !staff) return res.status(401).json({ error: "Unauthorized", message: "Missing or invalid bearer token" });
  const conn = await getDb();
  try {
    let rows;
    if (user) {
      rows = await conn.all(`${BOOKING_SELECT} WHERE user_id = ? ORDER BY created_at DESC`, [user.id]);
    } else {
      const [limit, offset] = paginationArgs(req);
      rows = await conn.all(`${BOOKING_SELECT} ORDER BY created_at DESC LIMIT ? OFFSET ?`, [limit, offset]);
    }
    const ids = rows.map((r) => r.id);
    const partsBy = await fetchBulk(conn, "booking_parts", ids, partRowToDict);
    const changesBy = await fetchBulk(conn, "booking_service_changes", ids, serviceChangeRowToDict);
    return res.json(rows.map((r) => bookingRowToDict(r, {
      includeStartCode: Boolean(user), parts: partsBy.get(r.id), serviceChanges: changesBy.get(r.id),
    })));
  } finally {
    conn.close();
  }
});

app.get("/api/bookings/:bookingId", async (req, res) => {
  const user = await getCurrentUserOptional(req);
  const staff = user ? null : await getCurrentStaffOptional(req);
  if (!user && !staff) return res.status(401).json({ error: "Unauthorized", message: "Missing or invalid bearer token" });
  const { bookingId } = req.params;
  const conn = await getDb();
  try {
    const row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
    if (!row) return notFound(res);
    if (user && row.user_id && row.user_id !== user.id) return notFound(res);
    return res.json(bookingRowToDict(row, {
      includeStartCode: Boolean(user),
      parts: await fetchBookingParts(conn, bookingId),
      serviceChanges: await fetchBookingServiceChanges(conn, bookingId),
    }));
  } finally {
    conn.close();
  }
});

const BOOKING_LOCATION_SCHEMA = {
  scheduledAt: new Field("str", { maxLen: 40, pattern: P.ISO_DATETIME, strip: false }),
  area: new Field("str", { maxLen: 200 }),
  addressLine: new Field("str", { maxLen: 300 }),
  lat: new Field("number", { minVal: -90, maxVal: 90 }),
  lng: new Field("number", { minVal: -180, maxVal: 180 }),
  directions: new Field("str", { maxLen: 500 }),
  notes: new Field("str", { maxLen: 2000 }),
  issues: new Field("list", { maxLen: 30, itemType: "str" }),
};

/** The address/schedule/issue fields shared by single and cart checkout. */
function bookingLocationFields(data) {
  const lat = isNum(data.lat) ? data.lat : null;
  const lng = isNum(data.lng) ? data.lng : null;
  const addressLine = trimOrNull(data.addressLine);
  return {
    scheduledAt: data.scheduledAt ?? null,
    area: trimOrNull(data.area),
    addressLine,
    lat,
    lng,
    directions: trimOrNull(data.directions),
    notes: trimOrNull(data.notes),
    issuesJson: Array.isArray(data.issues) && data.issues.length ? JSON.stringify(data.issues) : null,
    city: inferCity(addressLine, lat, lng),
  };
}

async function insertBooking(conn, {
  bookingId, category, service, price, user, bachatSlot, serviceId, totalAmount, loc, startCode, ts,
}) {
  await conn.run(
    "INSERT INTO bookings (id, category, service, price, technician_id, customer_name, "
      + "status, bachat_slot, service_rating, tech_rating, area, created_at, updated_at, "
      + "user_id, service_id, total_amount, lat, lng, directions, notes, issues_json, "
      + "start_code, scheduled_at, address_line, city) "
      + "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
    [bookingId, category, service, price, null, user.name, "Requested", bachatSlot, null, null, loc.area, ts, ts,
      user.id, serviceId, totalAmount, loc.lat, loc.lng, loc.directions, loc.notes, loc.issuesJson,
      startCode, loc.scheduledAt, loc.addressLine, loc.city],
  );
}

async function sendStartCodeSms(user, service, startCode, bookingId) {
  if (!user.phone) return;
  await sendSms(
    `+91${user.phone}`,
    `Rasoi Care: your start code for ${service} is ${startCode}. `
      + "Share it with your technician when they arrive to begin the job.",
    { requestId: bookingId },
  );
}

const NO_TECHNICIAN = { error: "No technician is available for this service yet" };

app.post(
  "/api/bookings",
  requireAuth,
  validateJson({
    service_id: new Field("str", { maxLen: 50 }),
    category: new Field("str", { maxLen: 100 }),
    service: new Field("str", { maxLen: 200 }),
    price: new Field("number", { minVal: 0, maxVal: 10000000 }),
    bachatSlot: new Field("str", { maxLen: 100 }),
    ...BOOKING_LOCATION_SCHEMA,
  }),
  async (req, res) => {
    // Either a catalog service_id (priced server-side) or the legacy
    // category/service/price shape the Bachat Package promo uses.
    const data = body(req);
    let serviceId = data.service_id || null;
    const loc = bookingLocationFields(data);
    let category;
    let service;
    let price;
    if (serviceId) {
      const s = await selectOne(`${SERVICE_SELECT} WHERE services.id = ?`, [serviceId]);
      if (!s) return res.status(400).json({ error: "Unknown service_id" });
      category = s.category;
      service = `${s.appliance_name} · ${s.name}`;
      price = s.price;
    } else {
      category = data.category;
      service = data.service;
      price = data.price ?? 0;
      serviceId = null;
      if (!category || !service) {
        return res.status(400).json({ error: "service_id, or category and service, are required" });
      }
    }
    const conn = await getDb();
    let row;
    let startCode;
    let bookingId;
    try {
      // Dispatch is a broadcast: the booking goes out unassigned and the
      // first eligible technician to claim it gets it. This only refuses a
      // booking nobody could ever fulfil (no technicians signed up at all).
      if (!(await conn.get("SELECT 1 AS x FROM technicians LIMIT 1"))) return res.status(503).json(NO_TECHNICIAN);
      bookingId = await nextId(conn, "order", "RC");
      startCode = rl.fourDigitCode();
      await insertBooking(conn, {
        bookingId, category, service, price, user: req.user, bachatSlot: data.bachatSlot ?? null,
        serviceId, totalAmount: price, loc, startCode, ts: now(),
      });
      await conn.commit();
      row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
    } finally {
      conn.close();
    }
    // Best-effort — the code is in the response regardless.
    await sendStartCodeSms(req.user, service, startCode, bookingId);
    return res.status(201).json(bookingRowToDict(row, { includeStartCode: true }));
  },
);

app.post(
  "/api/bookings/cart",
  requireAuth,
  validateJson({
    serviceIds: new Field("list", { required: true, minLen: 1, maxLen: 20, itemType: "str" }),
    useCoins: new Field("bool"),
    ...BOOKING_LOCATION_SCHEMA,
  }),
  async (req, res) => {
    // Real checkout for the Customer app's Service tab: one or more catalog
    // services sharing one visit. Every rupee comes from a value only the
    // server knows — catalog prices, the visit-fee/coupon/GST rules
    // (mirrored from PricingBreakdown in providers.dart) and the caller's
    // real coin balance — never a client-supplied total.
    const data = body(req);
    const serviceIds = data.serviceIds || [];
    const useCoins = Boolean(data.useCoins);
    const loc = bookingLocationFields(data);
    const conn = await getDb();
    let bookingsOut;
    let createdIds;
    let pricing;
    try {
      const rows = [];
      for (const sid of serviceIds) {
        const r = await conn.get(`${SERVICE_SELECT} WHERE services.id = ?`, [sid]);
        if (!r) return res.status(400).json({ error: `Unknown serviceId: ${sid}` });
        rows.push(r);
      }
      if (!(await conn.get("SELECT 1 AS x FROM technicians LIMIT 1"))) return res.status(503).json(NO_TECHNICIAN);

      const subtotal = rows.reduce((acc, r) => acc + r.price, 0);
      const preGstBase = subtotal + CART_VISIT_FEE;
      const coupon = preGstBase > CART_COUPON_THRESHOLD ? CART_COUPON_DISCOUNT : 0;
      const afterCoupon = preGstBase - coupon;
      const gst = pyRound(afterCoupon * CART_GST_RATE);
      const beforeCoins = afterCoupon + gst;

      let coinsRedeemed = 0;
      if (useCoins && beforeCoins > 0) {
        // Compare-and-swap: the UPDATE re-checks the balance hasn't moved
        // since it was read, so two concurrent checkouts can't both spend
        // it. On MySQL the read also locks the row for this transaction.
        const lock = conn.dialect === "mysql" ? " FOR UPDATE" : "";
        let redeemed = false;
        for (let attempt = 0; attempt < 5; attempt++) {
          const userRow = await conn.get(`SELECT coins_balance FROM users WHERE id = ?${lock}`, [req.user.id]);
          coinsRedeemed = Math.min(userRow.coins_balance, beforeCoins);
          if (coinsRedeemed <= 0) {
            redeemed = true;
            break;
          }
          const cur = await conn.run(
            "UPDATE users SET coins_balance = coins_balance - ? WHERE id = ? AND coins_balance = ?",
            [coinsRedeemed, req.user.id, userRow.coins_balance],
          );
          if (cur.changes === 1) {
            redeemed = true;
            break;
          }
        }
        if (!redeemed) return res.status(409).json({ error: "Could not redeem Care Coins — try again." });
      }
      const grandTotal = beforeCoins - coinsRedeemed;

      // Same proportional split as the app's _allocate(): each booking row
      // carries a meaningful price, the last absorbs the rounding remainder.
      const allocations = [];
      let allocated = 0;
      rows.forEach((r, i) => {
        if (i === rows.length - 1) {
          allocations.push(grandTotal - allocated);
        } else {
          const share = subtotal ? pyRound((grandTotal * r.price) / subtotal) : 0;
          allocations.push(share);
          allocated += share;
        }
      });

      createdIds = [];
      const ts = now();
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const bookingId = await nextId(conn, "order", "RC");
        const startCode = rl.fourDigitCode();
        const service = `${r.appliance_name} · ${r.name}`;
        await insertBooking(conn, {
          bookingId, category: r.category, service, price: allocations[i], user: req.user, bachatSlot: null,
          serviceId: r.id, totalAmount: allocations[i], loc, startCode, ts,
        });
        createdIds.push([bookingId, service, startCode]);
      }
      await conn.commit();

      bookingsOut = [];
      for (const [bookingId] of createdIds) {
        const row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
        bookingsOut.push(bookingRowToDict(row, {
          includeStartCode: true,
          parts: await fetchBookingParts(conn, bookingId),
          serviceChanges: await fetchBookingServiceChanges(conn, bookingId),
        }));
      }
      pricing = {
        subtotal, visitFee: CART_VISIT_FEE, couponDiscount: coupon, gst, coinsRedeemed, grandTotal,
      };
    } finally {
      conn.close();
    }
    for (const [bookingId, service, startCode] of createdIds) {
      await sendStartCodeSms(req.user, service, startCode, bookingId);
    }
    return res.status(201).json({ bookings: bookingsOut, pricing });
  },
);

app.get("/api/technician/bookings/available", requireTechnicianAuth, async (req, res) => {
  // The Partner app's broadcast request feed: every verified, on-duty
  // technician whose category matches sees the same unclaimed bookings
  // (oldest first). A booking with a city only reaches technicians in it.
  const tech = req.technician;
  if (!tech.verified || !tech.online) return res.json([]);
  const myCategories = technicianCategories(tech);
  const rows = await (async () => {
    const conn = await getDb();
    try {
      return await conn.all(
        `${BOOKING_SELECT} WHERE bookings.technician_id IS NULL AND bookings.status = 'Requested' `
          + "ORDER BY bookings.created_at ASC",
      );
    } finally {
      conn.close();
    }
  })();
  const matching = rows.filter((r) => myCategories.includes(r.category) && (!r.city || r.city === tech.area));
  return res.json(matching.map((r) => bookingRowToDict(r, { redactCustomerContact: true })));
});

app.patch("/api/bookings/:bookingId/claim", requireTechnicianAuth, async (req, res) => {
  // The UPDATE's own WHERE is the race guard: if two technicians accept at
  // once, only one UPDATE can match. Verification is enforced here too —
  // the /available feed is not an access-control boundary.
  if (!req.technician.verified) {
    return res.status(403).json({
      error: "Forbidden", message: "Your account needs to be verified before you can accept jobs.",
    });
  }
  const { bookingId } = req.params;
  const conn = await getDb();
  try {
    const cur = await conn.run(
      "UPDATE bookings SET technician_id = ?, status = 'Accepted', updated_at = ? "
        + "WHERE id = ? AND technician_id IS NULL AND status = 'Requested'",
      [req.technician.id, now(), bookingId],
    );
    await conn.commit();
    if (cur.changes !== 1) {
      const row = await conn.get("SELECT status, technician_id FROM bookings WHERE id = ?", [bookingId]);
      if (!row) return notFound(res);
      if (row.technician_id !== null) {
        return res.status(409).json({ error: "Already claimed", message: "Another technician already accepted this job." });
      }
      return res.status(409).json({ error: "No longer available", message: "This request isn't open to accept any more." });
    }
    return res.json(bookingRowToDict(await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId])));
  } finally {
    conn.close();
  }
});

async function insertLedger(conn, technicianId, bookingId, kind, amountPaise, reason, ts) {
  await conn.run(
    "INSERT INTO technician_ledger (id, technician_id, booking_id, kind, amount_paise, reason, created_at) "
      + "VALUES (?,?,?,?,?,?,?)",
    [newUuidId("LEDG"), technicianId, bookingId, kind, amountPaise, reason, ts],
  );
}

app.patch(
  "/api/bookings/:bookingId/advance",
  requireTechnicianAuth,
  validateJson({
    startCode: new Field("str", { pattern: P.CODE, strip: false }),
    suctionBefore: new Field("number", { minVal: 0, maxVal: 100000 }),
    suctionAfter: new Field("number", { minVal: 0, maxVal: 100000 }),
  }),
  async (req, res) => {
    // Moves a job to its next status. Only the assigned technician can, and
    // the two meaningful steps are gated on real proof: "In Progress" needs
    // the customer's start code; "Completed" needs both photos, the
    // signature, and a decision on every part quote.
    const data = body(req);
    const { bookingId } = req.params;
    const conn = await getDb();
    const smsQueue = [];
    let result;
    try {
      let row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      if (!row || row.technician_id !== req.technician.id) return notFound(res);
      const idx = Math.max(0, STATUS_ORDER.indexOf(row.status));
      if (idx >= STATUS_ORDER.length - 1) return res.json(bookingRowToDict(row));
      const newStatus = STATUS_ORDER[idx + 1];

      if (newStatus === "In Progress") {
        const submitted = (data.startCode || "").trim();
        if (!submitted || submitted !== (row.start_code || "")) {
          return res.status(400).json({
            error: "Incorrect verification code", message: "Ask the customer for the 4-digit code shown in their app.",
          });
        }
      }

      if (newStatus === "Completed") {
        const missing = [
          ["a before photo", row.before_photo_b64],
          ["an after photo", row.after_photo_b64],
          ["the customer's signature", row.signature_b64],
        ].filter(([, present]) => !present).map(([label]) => label);
        if (missing.length) {
          return res.status(400).json({
            error: "Job not ready to complete", message: `Still missing: ${missing.join(", ")}.`,
          });
        }
        // There's no re-invoicing flow, so an undecided quote can't be left
        // dangling past completion.
        const pending = await conn.all(
          "SELECT name FROM booking_parts WHERE booking_id = ? AND status = 'pending' ORDER BY created_at",
          [bookingId],
        );
        if (pending.length) {
          return res.status(400).json({
            error: "Awaiting customer approval",
            message: `The customer still needs to approve or reject: ${pending.map((p) => p.name).join(", ")}.`,
          });
        }
      }

      const ts = now();
      await conn.run("UPDATE bookings SET status = ?, updated_at = ? WHERE id = ?", [newStatus, ts, bookingId]);

      if (newStatus === "In Progress") {
        await conn.run("UPDATE bookings SET in_progress_at = ? WHERE id = ?", [ts, bookingId]);
        // Auto-fine for starting later than the slot's grace window. Skipped
        // for a booking with no real scheduled slot to measure against.
        const scheduled = parseIso(row.scheduled_at);
        const started = parseIso(ts);
        if (scheduled && started > new Date(scheduled.getTime() + LATE_ARRIVAL_GRACE_MINUTES * 60000)) {
          await insertLedger(
            conn, row.technician_id, bookingId, "fine", -LATE_ARRIVAL_FINE_PAISE,
            `Late arrival on ${bookingId} (started more than ${LATE_ARRIVAL_GRACE_MINUTES} min after the scheduled slot)`,
            ts,
          );
        }
      }

      if (newStatus === "Completed") {
        await conn.run("UPDATE technicians SET jobs_completed = jobs_completed + 1 WHERE id = ?", [row.technician_id]);
        // Weekly and monthly incentives, each firing exactly once per period
        // the moment the completed count first reaches its threshold. This
        // booking already counts — it was updated above on this connection.
        const completedAt = parseIso(ts);
        if (await countCompletedSince(conn, row.technician_id, weekStartIso(completedAt)) === WEEKLY_JOBS_FOR_BONUS) {
          await insertLedger(conn, row.technician_id, bookingId, "incentive", WEEKLY_BONUS_PAISE,
            `${WEEKLY_JOBS_FOR_BONUS} jobs completed this week`, ts);
        }
        if (await countCompletedSince(conn, row.technician_id, monthStartIso(completedAt)) === MONTHLY_JOBS_FOR_BONUS) {
          await insertLedger(conn, row.technician_id, bookingId, "incentive", MONTHLY_BONUS_PAISE,
            `${MONTHLY_JOBS_FOR_BONUS} jobs completed this month`, ts);
        }
        // Care Coins — 2% of the real total, credited only once the job is
        // actually done. Completed is terminal, so this runs at most once.
        if (row.user_id && row.total_amount) {
          const coinsEarned = Math.floor((row.total_amount * 2) / 100);
          if (coinsEarned > 0) {
            await conn.run("UPDATE users SET coins_balance = coins_balance + ? WHERE id = ?", [coinsEarned, row.user_id]);
            if (row.customer_phone) {
              smsQueue.push([
                `+91${row.customer_phone}`,
                `Rasoi Care: you earned ${coinsEarned} Care Coins for your ${row.service} booking. Redeem them on your next visit!`,
                { requestId: `coins-${bookingId}` },
              ]);
            }
          }
        }
        const suctionBefore = data.suctionBefore ?? null;
        const suctionAfter = data.suctionAfter ?? null;
        if (suctionBefore !== null || suctionAfter !== null) {
          await conn.run(
            "UPDATE bookings SET suction_before = ?, suction_after = ? WHERE id = ?",
            [suctionBefore, suctionAfter, bookingId],
          );
        }
        const startedAt = parseIso(row.in_progress_at);
        if (startedAt) {
          const minutes = Math.max(1, pyRound((parseIso(ts) - startedAt) / 60000));
          await conn.run("UPDATE bookings SET time_on_site_min = ? WHERE id = ?", [minutes, bookingId]);
        }
      }
      await conn.commit();
      row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      result = bookingRowToDict(row);
    } finally {
      conn.close();
    }
    for (const args of smsQueue) await sendSms(...args);
    return res.json(result);
  },
);

/** Shared by the photo/signature uploads: the booking must be this
 * technician's. Stores straight into the booking row, so completing a job
 * never depends on a Storage bucket existing. The column is chosen by the
 * caller from a fixed list — no request value ever reaches the SQL text. */
async function storeJobImage(req, res, column, dataB64) {
  const { bookingId } = req.params;
  const conn = await getDb();
  try {
    const row = await conn.get("SELECT technician_id FROM bookings WHERE id = ?", [bookingId]);
    if (!row || row.technician_id !== req.technician.id) return notFound(res);
    await conn.run(`UPDATE bookings SET ${column} = ? WHERE id = ?`, [dataB64, bookingId]);
    await conn.commit();
    return res.json({ ok: true });
  } finally {
    conn.close();
  }
}

app.patch(
  "/api/bookings/:bookingId/photo",
  requireTechnicianAuth,
  validateJson({
    kind: new Field("str", { required: true, choices: ["before", "after"] }),
    dataBase64: new Field("str", { required: true, minLen: 1, maxLen: 12000000, pattern: P.BASE64, strip: false }),
  }),
  async (req, res) => {
    const { kind, dataBase64 } = body(req);
    if (kind !== "before" && kind !== "after") return res.status(400).json({ error: "kind must be 'before' or 'after'" });
    if (!dataBase64) return res.status(400).json({ error: "dataBase64 is required" });
    return storeJobImage(req, res, kind === "before" ? "before_photo_b64" : "after_photo_b64", dataBase64);
  },
);

app.patch(
  "/api/bookings/:bookingId/signature",
  requireTechnicianAuth,
  validateJson({
    dataBase64: new Field("str", { required: true, minLen: 1, maxLen: 4000000, pattern: P.BASE64, strip: false }),
  }),
  async (req, res) => {
    const { dataBase64 } = body(req);
    if (!dataBase64) return res.status(400).json({ error: "dataBase64 is required" });
    return storeJobImage(req, res, "signature_b64", dataBase64);
  },
);

app.get("/api/bookings/:bookingId/photo/:kind", async (req, res) => {
  // Serves a stored photo/signature as an image. Booking ids are
  // sequential, so the caller must be this booking's customer, its
  // assigned technician, or staff.
  const { bookingId, kind } = req.params;
  if (!Object.hasOwn(PHOTO_MIME, kind)) {
    return res.status(400).json({ error: "kind must be 'before', 'after', or 'signature'" });
  }
  const user = await getCurrentUserOptional(req);
  const staff = user ? null : await getCurrentStaffOptional(req);
  const technician = user || staff ? null : await getCurrentTechnicianOptional(req);
  if (!user && !staff && !technician) {
    return res.status(401).json({ error: "Unauthorized", message: "Missing or invalid bearer token" });
  }
  const column = { before: "before_photo_b64", after: "after_photo_b64", signature: "signature_b64" }[kind];
  const conn = await getDb();
  let row;
  try {
    const owner = await conn.get("SELECT user_id, technician_id FROM bookings WHERE id = ?", [bookingId]);
    if (!owner) return notFound(res);
    if (user && owner.user_id !== user.id) return notFound(res);
    if (technician && owner.technician_id !== technician.id) return notFound(res);
    row = await conn.get(`SELECT ${column} AS data FROM bookings WHERE id = ?`, [bookingId]);
  } finally {
    conn.close();
  }
  if (!row || !row.data) return notFound(res);
  return res.type(PHOTO_MIME[kind]).send(Buffer.from(row.data, "base64"));
});

app.patch("/api/bookings/:bookingId/decline", requireTechnicianAuth, async (req, res) => {
  // A technician backing out of a job they claimed, before heading over —
  // puts it back in the broadcast pool for whoever claims it next.
  const { bookingId } = req.params;
  const conn = await getDb();
  try {
    const row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
    if (!row || row.technician_id !== req.technician.id) return notFound(res);
    if (row.status !== "Accepted") {
      return res.status(400).json({ error: `Cannot back out of a ${row.status.toLowerCase()} job` });
    }
    await conn.run(
      "UPDATE bookings SET technician_id = NULL, status = 'Requested', updated_at = ? WHERE id = ?",
      [now(), bookingId],
    );
    await conn.commit();
    return res.json(bookingRowToDict(await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId])));
  } finally {
    conn.close();
  }
});

app.patch(
  "/api/bookings/:bookingId/payment",
  requireTechnicianAuth,
  validateJson({ paymentMethod: new Field("str", { required: true, choices: ["upi", "card", "cash", "link"] }) }),
  async (req, res) => {
    // Which way the customer paid the technician in person — no gateway.
    const method = (body(req).paymentMethod || "").trim();
    if (!["upi", "card", "cash", "link"].includes(method)) {
      return res.status(400).json({ error: "paymentMethod must be one of: upi, card, cash, link" });
    }
    const { bookingId } = req.params;
    const conn = await getDb();
    try {
      const row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      if (!row || row.technician_id !== req.technician.id) return notFound(res);
      await conn.run("UPDATE bookings SET payment_method = ?, updated_at = ? WHERE id = ?", [method, now(), bookingId]);
      await conn.commit();
      return res.json(bookingRowToDict(await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId])));
    } finally {
      conn.close();
    }
  },
);

app.post("/api/bookings/:bookingId/cancel/request-otp", requireAuth, async (req, res) => {
  // Texts the customer the code PATCH .../cancel requires. The response
  // only says whether the SMS went out — never the code itself.
  const { bookingId } = req.params;
  const row = await selectOne(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
  if (!row || row.user_id !== req.user.id) return notFound(res);
  if (!CANCELLABLE_STATUSES.has(row.status)) {
    return res.status(400).json({ error: `Cannot cancel a ${row.status.toLowerCase()} booking` });
  }
  if (!req.user.phone) {
    return res.status(400).json({ error: "No phone on file", message: "Add a phone number to your account before cancelling." });
  }
  const code = cancelOtps.request(bookingId);
  const sent = await sendSms(
    `+91${req.user.phone}`,
    `Rasoi Care: your cancellation code is ${code}. It expires in ${Math.floor(CANCEL_OTP_TTL_SECONDS / 60)} minutes.`,
    { requestId: `cancel-${bookingId}` },
  );
  if (!sent) {
    return res.json({ sent: false, message: "We couldn't text you a code just now — try again in a moment." });
  }
  return res.json({ sent });
});

app.patch(
  "/api/bookings/:bookingId/cancel",
  requireAuth,
  validateJson({ otp: new Field("str", { required: true, pattern: P.CODE, strip: false }) }),
  async (req, res) => {
    const { bookingId } = req.params;
    const conn = await getDb();
    try {
      let row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      if (!row || row.user_id !== req.user.id) return notFound(res);
      if (!CANCELLABLE_STATUSES.has(row.status)) {
        return res.status(400).json({ error: `Cannot cancel a ${row.status.toLowerCase()} booking` });
      }
      const otpError = cancelOtps.verify(bookingId, body(req).otp, "Request a cancellation code first.");
      if (otpError) return res.status(400).json({ error: "Invalid code", message: otpError });
      const fee = cancellationFeeFor(row);
      const ts = now();
      await conn.run(
        "UPDATE bookings SET status = 'Cancelled', updated_at = ?, cancelled_at = ?, cancellation_fee = ? WHERE id = ?",
        [ts, ts, fee, bookingId],
      );
      await conn.commit();
      row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      return res.json(bookingRowToDict(row));
    } finally {
      conn.close();
    }
  },
);

app.patch(
  "/api/bookings/:bookingId/assign",
  requireStaffAuth,
  validateJson({ technician_id: new Field("str", { required: true, minLen: 1, maxLen: 50 }) }),
  async (req, res) => {
    // Admin assigning/reassigning a booking's technician.
    const technicianId = body(req).technician_id;
    if (!technicianId) return res.status(400).json({ error: "technician_id is required" });
    const { bookingId } = req.params;
    const conn = await getDb();
    try {
      const booking = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      if (!booking) return notFound(res);
      // Reassigning a finished job would silently move commission credit
      // away from whoever actually did the work.
      if (["Completed", "Cancelled"].includes(booking.status)) {
        return res.status(400).json({ error: `Cannot reassign a ${booking.status.toLowerCase()} booking` });
      }
      const tech = await conn.get("SELECT * FROM technicians WHERE id = ?", [technicianId]);
      if (!tech) return res.status(400).json({ error: "Unknown technician_id" });
      if (!tech.verified) return res.status(400).json({ error: "This technician hasn't been verified yet" });
      const newStatus = booking.status === "Requested" ? "Accepted" : booking.status;
      await conn.run(
        "UPDATE bookings SET technician_id = ?, status = ?, updated_at = ? WHERE id = ?",
        [technicianId, newStatus, now(), bookingId],
      );
      await conn.commit();
      return res.json(bookingRowToDict(await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId])));
    } finally {
      conn.close();
    }
  },
);

app.post(
  "/api/bookings/:bookingId/rating",
  requireAuth,
  validateJson({
    serviceRating: new Field("int", { minVal: 0, maxVal: 5 }),
    techRating: new Field("int", { minVal: 0, maxVal: 5 }),
    raiseComplaint: new Field("bool"),
    complaintText: new Field("str", { maxLen: 2000 }),
  }),
  async (req, res) => {
    // Only the booking's own customer, and only once — otherwise a replay
    // could roll the technician's average again and again.
    const data = body(req);
    const serviceRating = data.serviceRating ?? 0;
    const techRating = data.techRating ?? 0;
    const raiseComplaint = Boolean(data.raiseComplaint);
    const complaintText = data.complaintText || "Customer flagged this service as unsatisfactory.";
    const { bookingId } = req.params;
    const conn = await getDb();
    try {
      const booking = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      if (!booking || booking.user_id !== req.user.id) return notFound(res);
      if (booking.service_rating !== null || booking.tech_rating !== null) {
        return res.status(400).json({ error: "This booking has already been rated" });
      }
      await conn.run(
        "UPDATE bookings SET service_rating = ?, tech_rating = ?, updated_at = ? WHERE id = ?",
        [serviceRating, techRating, now(), bookingId],
      );
      const tech = await conn.get("SELECT * FROM technicians WHERE id = ?", [booking.technician_id]);
      if (tech) {
        const newCount = tech.rating_count + 1;
        const newRating = pyRound((tech.rating * tech.rating_count + techRating) / newCount, 2);
        await conn.run("UPDATE technicians SET rating = ?, rating_count = ? WHERE id = ?", [newRating, newCount, tech.id]);
      }
      let complaint = null;
      if (raiseComplaint) {
        const complaintId = await nextId(conn, "complaint", "CMP");
        const ts = now();
        await conn.run(
          "INSERT INTO complaints (id, booking_id, text, status, response, created_at) VALUES (?,?,?,?,?,?)",
          [complaintId, bookingId, complaintText, "New", null, ts],
        );
        complaint = { id: complaintId, bookingId, text: complaintText, status: "New", response: null, createdAt: ts };
      }
      await conn.commit();
      const row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      return res.json({ booking: bookingRowToDict(row), complaint });
    } finally {
      conn.close();
    }
  },
);

// ---------------------------------------------------------------- complaints
app.get("/api/complaints", requireStaffAuth, async (req, res) => {
  const [limit, offset] = paginationArgs(req);
  const conn = await getDb();
  try {
    const rows = await conn.all("SELECT * FROM complaints ORDER BY created_at DESC LIMIT ? OFFSET ?", [limit, offset]);
    res.json(rows.map(complaintRowToDict));
  } finally {
    conn.close();
  }
});

app.patch(
  "/api/complaints/:complaintId",
  requireStaffAuth,
  validateJson({
    response: new Field("str", { maxLen: 2000 }),
    status: new Field("str", { maxLen: 50 }),
  }),
  async (req, res) => {
    const data = body(req);
    const { complaintId } = req.params;
    const conn = await getDb();
    try {
      let row = await conn.get("SELECT * FROM complaints WHERE id = ?", [complaintId]);
      if (!row) return notFound(res);
      const response = "response" in data ? data.response : row.response;
      const status = "status" in data ? data.status : row.status;
      await conn.run("UPDATE complaints SET response = ?, status = ? WHERE id = ?", [response, status, complaintId]);
      await conn.commit();
      row = await conn.get("SELECT * FROM complaints WHERE id = ?", [complaintId]);
      return res.json(complaintRowToDict(row));
    } finally {
      conn.close();
    }
  },
);

// ---------------------------------------------------------------- technicians (staff)
// Staff-only: technicianRowToDict carries a full KYC dossier, and verify/
// create must never be self-service.
app.get("/api/technicians", requireStaffAuth, async (req, res) => {
  const [limit, offset] = paginationArgs(req);
  const conn = await getDb();
  try {
    const rows = await conn.all("SELECT * FROM technicians ORDER BY name LIMIT ? OFFSET ?", [limit, offset]);
    res.json(rows.map((r) => technicianRowToDict(r, { redactDocuments: true })));
  } finally {
    conn.close();
  }
});

app.get("/api/technicians/:technicianId/document/:kind", requireStaffAuth, async (req, res) => {
  // Proxies a KYC document through a staff-authenticated request instead
  // of handing out the raw, non-expiring Firebase Storage URL.
  const field = DOCUMENT_PROXY_FIELD_BY_KIND[req.params.kind];
  if (!field || !Object.hasOwn(DOCUMENT_PROXY_FIELD_BY_KIND, req.params.kind)) {
    return res.status(400).json({ error: `kind must be one of: ${Object.keys(DOCUMENT_PROXY_FIELD_BY_KIND).join(", ")}` });
  }
  const row = await selectOne("SELECT * FROM technicians WHERE id = ?", [req.params.technicianId]);
  if (!row) return notFound(res);
  const url = get(row, field);
  if (!url) return notFound(res);
  let parsed = null;
  try {
    parsed = new URL(url);
  } catch {
    parsed = null;
  }
  // The fetch target is rebuilt from the allowlist's own constant, so only
  // the path/query ever come from the stored URL.
  const trustedHost = parsed && parsed.protocol === "https:"
    ? DOCUMENT_PROXY_ALLOWED_HOSTS.find((h) => h === parsed.hostname)
    : undefined;
  if (!trustedHost) {
    return res.status(502).json({ error: "Document URL is not from a trusted host" });
  }
  const target = new URL(`${parsed.pathname}${parsed.search}`, `https://${trustedHost}`);
  try {
    const resp = await fetch(target, { signal: AbortSignal.timeout(10000), redirect: "error" });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const data = Buffer.from(await resp.arrayBuffer());
    return res.type(resp.headers.get("Content-Type") || "application/octet-stream").send(data);
  } catch {
    return res.status(502).json({ error: "Could not fetch this document right now" });
  }
});

app.post(
  "/api/technicians",
  requireStaffAuth,
  validateJson({
    name: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    category: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    area: new Field("str", { required: true, minLen: 1, maxLen: 200 }),
  }),
  async (req, res) => {
    // New hires start unverified and offline until an admin verifies them.
    const data = body(req);
    const techId = newUuidId("TECH");
    const conn = await getDb();
    try {
      await conn.run(
        "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
          + "VALUES (?,?,?,?,0,0,5.0,0,0)",
        [techId, data.name.trim(), data.category.trim(), data.area.trim()],
      );
      await conn.commit();
      const row = await conn.get("SELECT * FROM technicians WHERE id = ?", [techId]);
      return res.status(201).json(technicianRowToDict(row, { redactDocuments: true }));
    } finally {
      conn.close();
    }
  },
);

async function generatePartnerCode(conn) {
  for (;;) {
    let code = "RC-";
    for (let i = 0; i < 6; i++) code += PARTNER_CODE_CHARS[crypto.randomInt(PARTNER_CODE_CHARS.length)];
    if (!(await conn.get("SELECT 1 AS x FROM technicians WHERE partner_code = ?", [code]))) return code;
  }
}

app.patch("/api/technicians/:technicianId/verify", requireStaffAuth, async (req, res) => {
  // Flips verified + online. The first verification also mints a permanent,
  // human-shareable partner code; re-verifying keeps the existing one.
  const { technicianId } = req.params;
  const conn = await getDb();
  try {
    let row = await conn.get("SELECT * FROM technicians WHERE id = ?", [technicianId]);
    if (!row) return notFound(res);
    if (row.partner_code) {
      await conn.run("UPDATE technicians SET verified = 1, online = 1 WHERE id = ?", [technicianId]);
    } else {
      await conn.run(
        "UPDATE technicians SET verified = 1, online = 1, partner_code = ? WHERE id = ?",
        [await generatePartnerCode(conn), technicianId],
      );
    }
    await conn.commit();
    row = await conn.get("SELECT * FROM technicians WHERE id = ?", [technicianId]);
    return res.json(technicianRowToDict(row, { redactDocuments: true }));
  } finally {
    conn.close();
  }
});

app.get("/api/technicians/:technicianId/earnings", requireStaffAuth, async (req, res) => {
  const conn = await getDb();
  try {
    const row = await conn.get("SELECT * FROM technicians WHERE id = ?", [req.params.technicianId]);
    if (!row) return notFound(res);
    return res.json(await technicianEarningsPayload(conn, row));
  } finally {
    conn.close();
  }
});

// ---------------------------------------------------------------- technician self-service
app.post(
  "/api/technician/bootstrap",
  validateJson({
    name: new Field("str", { maxLen: 100 }),
    category: new Field("str", { maxLen: 100 }),
    area: new Field("str", { maxLen: 200 }),
  }),
  async (req, res) => {
    // Called right after Firebase sign-in in the Partner app. A self-
    // registered technician starts unverified/offline.
    const claims = await firebaseClaims(req);
    if (!claims) return res.status(401).json({ error: "Unauthorized", message: "Invalid or missing Firebase token" });
    const data = body(req);
    const name = (data.name || claims.name || "").trim() || "Technician";
    const category = (data.category || "").trim() || "RasoiSpark";
    const area = (data.area || "").trim();
    const conn = await getDb();
    try {
      let row = await conn.get("SELECT * FROM technicians WHERE firebase_uid = ?", [claims.uid]);
      if (!row && claims.email && claims.email_verified) {
        row = await conn.get("SELECT * FROM technicians WHERE email = ?", [claims.email]);
      }
      let techId;
      if (row) {
        await conn.run("UPDATE technicians SET firebase_uid = ?, name = ? WHERE id = ?", [claims.uid, name, row.id]);
        techId = row.id;
      } else {
        techId = newUuidId("TECH");
        await conn.run(
          "INSERT INTO technicians (id, name, category, area, verified, online, rating, "
            + "rating_count, jobs_completed, email, firebase_uid) VALUES (?,?,?,?,0,0,5.0,0,0,?,?)",
          [techId, name, category, area, claims.email, claims.uid],
        );
      }
      await conn.commit();
      return res.json(technicianRowToDict(await conn.get("SELECT * FROM technicians WHERE id = ?", [techId])));
    } finally {
      conn.close();
    }
  },
);

app.get("/api/technician/me", requireTechnicianAuth, (req, res) => res.json(technicianRowToDict(req.technician)));

app.get("/api/technician/earnings", requireTechnicianAuth, async (req, res) => {
  const conn = await getDb();
  try {
    res.json(await technicianEarningsPayload(conn, req.technician));
  } finally {
    conn.close();
  }
});

// Request field -> technicians column, for PATCH /api/technician/me.
const TECHNICIAN_ME_COLUMNS = {
  name: "name",
  area: "area",
  photoUrl: "photo_url",
  experienceYears: "experience_years",
  idDocumentUrl: "id_document_url",
  bankAccountName: "bank_account_name",
  bankAccountNumber: "bank_account_number",
  bankIfsc: "bank_ifsc",
  panNumber: "pan_number",
  aadharNumber: "aadhar_number",
  dateOfBirth: "date_of_birth",
  gstNumber: "gst_number",
  emergencyContactName: "emergency_contact_name",
  emergencyContactPhone: "emergency_contact_phone",
  aadharDocumentUrl: "aadhar_document_url",
  aadharDocumentBackUrl: "aadhar_document_back_url",
  panDocumentUrl: "pan_document_url",
  bankPassbookUrl: "bank_passbook_url",
  address: "address",
  upiId: "upi_id",
};

app.patch(
  "/api/technician/me",
  requireTechnicianAuth,
  validateJson({
    name: new Field("str", { maxLen: 100 }),
    area: new Field("str", { maxLen: 200 }),
    photoUrl: new Field("str", { maxLen: 2000, pattern: P.URL }),
    experienceYears: new Field("int", { minVal: 0, maxVal: 80 }),
    idDocumentUrl: new Field("str", { maxLen: 2000, pattern: P.URL }),
    bankAccountName: new Field("str", { maxLen: 200 }),
    bankAccountNumber: new Field("str", { pattern: P.BANK_ACCOUNT, strip: false }),
    bankIfsc: new Field("str", { pattern: P.IFSC, strip: false }),
    panNumber: new Field("str", { pattern: P.PAN, strip: false }),
    aadharNumber: new Field("str", { pattern: P.AADHAAR, strip: false }),
    dateOfBirth: new Field("str", { pattern: P.DATE, strip: false }),
    gstNumber: new Field("str", { pattern: P.GSTIN, strip: false }),
    emergencyContactName: new Field("str", { maxLen: 100 }),
    emergencyContactPhone: new Field("str", { pattern: P.PHONE, strip: false }),
    aadharDocumentUrl: new Field("str", { maxLen: 2000, pattern: P.URL }),
    aadharDocumentBackUrl: new Field("str", { maxLen: 2000, pattern: P.URL }),
    panDocumentUrl: new Field("str", { maxLen: 2000, pattern: P.URL }),
    bankPassbookUrl: new Field("str", { maxLen: 2000, pattern: P.URL }),
    address: new Field("str", { maxLen: 500 }),
    upiId: new Field("str", { maxLen: 256, pattern: P.UPI_ID, strip: false }),
    categories: new Field("list", { maxLen: 20, itemType: "str" }),
    employmentType: new Field("str", { choices: ["payroll", "outsourced"] }),
    submit: new Field("bool"),
  }),
  async (req, res) => {
    // The Partner app's KYC application. `submit: true` marks it ready for
    // admin review. employmentType is one-way: only written while the
    // application hasn't been submitted, and no admin endpoint touches it.
    const data = body(req);
    const tech = req.technician;
    const conn = await getDb();
    try {
      for (const [key, column] of Object.entries(TECHNICIAN_ME_COLUMNS)) {
        if (data[key] !== undefined && data[key] !== null) {
          await conn.run(`UPDATE technicians SET ${column} = ? WHERE id = ?`, [data[key], tech.id]);
        }
      }
      // Keep `category` in sync with the first pick so single-column
      // queries still match the primary skill.
      if (Array.isArray(data.categories) && data.categories.length) {
        await conn.run(
          "UPDATE technicians SET categories_json = ?, category = ? WHERE id = ?",
          [JSON.stringify(data.categories), data.categories[0], tech.id],
        );
      }
      if (data.employmentType && !tech.application_submitted) {
        await conn.run("UPDATE technicians SET employment_type = ? WHERE id = ?", [data.employmentType, tech.id]);
      }
      if (data.submit) await conn.run("UPDATE technicians SET application_submitted = 1 WHERE id = ?", [tech.id]);
      await conn.commit();
      return res.json(technicianRowToDict(await conn.get("SELECT * FROM technicians WHERE id = ?", [tech.id])));
    } finally {
      conn.close();
    }
  },
);

app.patch(
  "/api/technician/online",
  requireTechnicianAuth,
  validateJson({ online: new Field("bool", { required: true }) }),
  async (req, res) => {
    const conn = await getDb();
    try {
      await conn.run("UPDATE technicians SET online = ? WHERE id = ?", [body(req).online ? 1 : 0, req.technician.id]);
      await conn.commit();
      return res.json(technicianRowToDict(await conn.get("SELECT * FROM technicians WHERE id = ?", [req.technician.id])));
    } finally {
      conn.close();
    }
  },
);

app.get("/api/technician/bookings", requireTechnicianAuth, async (req, res) => {
  // Only jobs assigned to this technician, scoped by their verified identity.
  const conn = await getDb();
  try {
    const rows = await conn.all(
      `${BOOKING_SELECT} WHERE technician_id = ? ORDER BY created_at DESC`, [req.technician.id],
    );
    const ids = rows.map((r) => r.id);
    const partsBy = await fetchBulk(conn, "booking_parts", ids, partRowToDict);
    const changesBy = await fetchBulk(conn, "booking_service_changes", ids, serviceChangeRowToDict);
    return res.json(rows.map((r) => bookingRowToDict(r, {
      parts: partsBy.get(r.id), serviceChanges: changesBy.get(r.id),
    })));
  } finally {
    conn.close();
  }
});

app.patch(
  "/api/technician/bookings/:bookingId/appliance",
  requireTechnicianAuth,
  validateJson({
    brand: new Field("str", { maxLen: 100 }),
    modelNumber: new Field("str", { maxLen: 100 }),
  }),
  async (req, res) => {
    // Brand/model read off the appliance on-site. An empty string clears it.
    const data = body(req);
    const { bookingId } = req.params;
    const conn = await getDb();
    try {
      const row = await conn.get("SELECT technician_id FROM bookings WHERE id = ?", [bookingId]);
      if (!row || row.technician_id !== req.technician.id) return notFound(res);
      if (typeof data.brand === "string") {
        await conn.run("UPDATE bookings SET brand = ? WHERE id = ?", [data.brand.trim(), bookingId]);
      }
      if (typeof data.modelNumber === "string") {
        await conn.run("UPDATE bookings SET model_number = ? WHERE id = ?", [data.modelNumber.trim(), bookingId]);
      }
      await conn.commit();
      const updated = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      return res.json(bookingRowToDict(updated, { parts: await fetchBookingParts(conn, bookingId) }));
    } finally {
      conn.close();
    }
  },
);

app.patch(
  "/api/technician/bookings/:bookingId/service",
  requireTechnicianAuth,
  validateJson({ serviceId: new Field("str", { required: true, maxLen: 50 }) }),
  async (req, res) => {
    // Swaps the booking's service for another in the same category (e.g.
    // an upgrade asked for mid-visit). Repriced from the catalog, logged to
    // booking_service_changes; blocked once the job is finished.
    const { serviceId } = body(req);
    const { bookingId } = req.params;
    const conn = await getDb();
    try {
      const row = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      if (!row || row.technician_id !== req.technician.id) return notFound(res);
      if (["Completed", "Cancelled"].includes(row.status)) {
        return res.status(400).json({
          error: "Job already finished", message: "Can't change the service on a completed or cancelled job.",
        });
      }
      const s = await conn.get(`${SERVICE_SELECT} WHERE services.id = ?`, [serviceId]);
      if (!s) return res.status(400).json({ error: "Unknown serviceId" });
      if (s.category !== row.category) {
        return res.status(400).json({
          error: "Service category mismatch", message: "That service isn't offered for this job's category.",
        });
      }
      const newServiceName = `${s.appliance_name} · ${s.name}`;
      const ts = now();
      await conn.run(
        "INSERT INTO booking_service_changes (id, booking_id, old_service, new_service, old_price, new_price, created_at) "
          + "VALUES (?,?,?,?,?,?,?)",
        [newUuidId("SVCC"), bookingId, row.service, newServiceName, row.price, s.price, ts],
      );
      await conn.run(
        "UPDATE bookings SET service = ?, price = ?, total_amount = ?, updated_at = ? WHERE id = ?",
        [newServiceName, s.price, s.price, ts, bookingId],
      );
      await conn.commit();
      const updated = await conn.get(`${BOOKING_SELECT} WHERE bookings.id = ?`, [bookingId]);
      return res.json(bookingRowToDict(updated, {
        parts: await fetchBookingParts(conn, bookingId),
        serviceChanges: await fetchBookingServiceChanges(conn, bookingId),
      }));
    } finally {
      conn.close();
    }
  },
);

app.post(
  "/api/technician/bookings/:bookingId/parts",
  requireTechnicianAuth,
  validateJson({
    name: new Field("str", { required: true, minLen: 1, maxLen: 200 }),
    sku: new Field("str", { maxLen: 100 }),
    qty: new Field("int", { required: true, minVal: 1, maxVal: 99 }),
    pricePaise: new Field("number", { required: true, minVal: 0, maxVal: 10000000 }),
  }),
  async (req, res) => {
    // A part/extra-work quote raised mid-job. Starts 'pending' until the
    // customer approves or rejects it; nothing is charged just by adding it.
    const data = body(req);
    const { bookingId } = req.params;
    const conn = await getDb();
    try {
      const row = await conn.get("SELECT technician_id FROM bookings WHERE id = ?", [bookingId]);
      if (!row || row.technician_id !== req.technician.id) return notFound(res);
      const partId = newUuidId("PART");
      await conn.run(
        "INSERT INTO booking_parts (id, booking_id, name, sku, qty, price_paise, status, created_at) "
          + "VALUES (?,?,?,?,?,?,'pending',?)",
        [partId, bookingId, data.name.trim(), trimOrNull(data.sku), data.qty, data.pricePaise, now()],
      );
      await conn.commit();
      return res.status(201).json(partRowToDict(await conn.get("SELECT * FROM booking_parts WHERE id = ?", [partId])));
    } finally {
      conn.close();
    }
  },
);

app.delete("/api/technician/bookings/:bookingId/parts/:partId", requireTechnicianAuth, async (req, res) => {
  // Retract a quote raised by mistake — only while still pending.
  const { bookingId, partId } = req.params;
  const conn = await getDb();
  try {
    const booking = await conn.get("SELECT technician_id FROM bookings WHERE id = ?", [bookingId]);
    if (!booking || booking.technician_id !== req.technician.id) return notFound(res);
    const part = await conn.get("SELECT * FROM booking_parts WHERE id = ? AND booking_id = ?", [partId, bookingId]);
    if (!part) return notFound(res);
    if (part.status !== "pending") {
      return res.status(400).json({
        error: "Already decided",
        message: "The customer has already approved or rejected this — it can't be removed.",
      });
    }
    await conn.run("DELETE FROM booking_parts WHERE id = ?", [partId]);
    await conn.commit();
    return res.json({ ok: true });
  } finally {
    conn.close();
  }
});

app.patch(
  "/api/bookings/:bookingId/parts/:partId",
  requireAuth,
  validateJson({ status: new Field("str", { required: true, choices: ["approved", "rejected"] }) }),
  async (req, res) => {
    // The customer's decision on a technician's quote.
    const { bookingId, partId } = req.params;
    const conn = await getDb();
    try {
      const booking = await conn.get("SELECT user_id FROM bookings WHERE id = ?", [bookingId]);
      if (!booking || booking.user_id !== req.user.id) return notFound(res);
      const part = await conn.get("SELECT * FROM booking_parts WHERE id = ? AND booking_id = ?", [partId, bookingId]);
      if (!part) return notFound(res);
      if (part.status !== "pending") {
        return res.status(400).json({ error: "Already decided", message: "This quote was already decided." });
      }
      await conn.run("UPDATE booking_parts SET status = ?, decided_at = ? WHERE id = ?", [body(req).status, now(), partId]);
      await conn.commit();
      return res.json(partRowToDict(await conn.get("SELECT * FROM booking_parts WHERE id = ?", [partId])));
    } finally {
      conn.close();
    }
  },
);

// ---------------------------------------------------------------- inventory
app.get("/api/inventory", requireStaffAuth, async (req, res) => {
  const conn = await getDb();
  try {
    res.json((await conn.all("SELECT * FROM inventory ORDER BY name")).map(inventoryRowToDict));
  } finally {
    conn.close();
  }
});

app.post(
  "/api/inventory",
  requireStaffAuth,
  validateJson({
    name: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    sku: new Field("str", { required: true, minLen: 1, maxLen: 50 }),
    category: new Field("str", { required: true, minLen: 1, maxLen: 100 }),
    quantity: new Field("int", { minVal: 0, maxVal: 1000000 }),
    reorderLevel: new Field("int", { minVal: 0, maxVal: 1000000 }),
  }),
  async (req, res) => {
    const data = body(req);
    const itemId = newUuidId("INV");
    const conn = await getDb();
    try {
      await conn.run(
        "INSERT INTO inventory (id, name, sku, category, quantity, reorder_level, updated_at) VALUES (?,?,?,?,?,?,?)",
        [itemId, data.name.trim(), data.sku.trim(), data.category.trim(), data.quantity ?? 0, data.reorderLevel ?? 10, now()],
      );
      await conn.commit();
      return res.status(201).json(inventoryRowToDict(await conn.get("SELECT * FROM inventory WHERE id = ?", [itemId])));
    } finally {
      conn.close();
    }
  },
);

app.patch(
  "/api/inventory/:itemId",
  requireStaffAuth,
  validateJson({
    quantity: new Field("int", { minVal: 0, maxVal: 1000000 }),
    reorderLevel: new Field("int", { minVal: 0, maxVal: 1000000 }),
  }),
  async (req, res) => {
    const data = body(req);
    const { itemId } = req.params;
    const conn = await getDb();
    try {
      let row = await conn.get("SELECT * FROM inventory WHERE id = ?", [itemId]);
      if (!row) return notFound(res);
      const quantity = "quantity" in data ? data.quantity : row.quantity;
      const reorderLevel = "reorderLevel" in data ? data.reorderLevel : row.reorder_level;
      await conn.run(
        "UPDATE inventory SET quantity = ?, reorder_level = ?, updated_at = ? WHERE id = ?",
        [quantity, reorderLevel, now(), itemId],
      );
      await conn.commit();
      row = await conn.get("SELECT * FROM inventory WHERE id = ?", [itemId]);
      return res.json(inventoryRowToDict(row));
    } finally {
      conn.close();
    }
  },
);

// ---------------------------------------------------------------- stats
app.get("/api/stats/overview", requireStaffAuth, async (req, res) => {
  const conn = await getDb();
  try {
    const n = async (sql) => Number((await conn.get(sql)).n);
    res.json({
      totalBookings: await n("SELECT COUNT(*) AS n FROM bookings"),
      revenue: await n("SELECT COALESCE(SUM(price),0) AS n FROM bookings WHERE status = 'Completed'"),
      openComplaints: await n("SELECT COUNT(*) AS n FROM complaints WHERE status != 'Resolved'"),
      onlineTechnicians: await n("SELECT COUNT(*) AS n FROM technicians WHERE online = 1"),
      totalTechnicians: await n("SELECT COUNT(*) AS n FROM technicians"),
    });
  } finally {
    conn.close();
  }
});

app.get("/api/stats/reports", requireStaffAuth, async (req, res) => {
  const period = String(req.query.period ?? "week");
  const days = PERIOD_DAYS[period] ?? 7;
  const cutoff = isoSeconds(new Date(Date.now() - days * 86400000));
  // Optional district filter (careplus_admin's State -> District picker).
  const area = trimOrNull(typeof req.query.area === "string" ? req.query.area : null);
  const conn = await getDb();
  let bookings;
  let complaints;
  let technicians;
  try {
    if (area) {
      bookings = await conn.all(
        `${BOOKING_SELECT} WHERE bookings.created_at >= ? AND bookings.area = ? ORDER BY created_at`, [cutoff, area],
      );
      complaints = await conn.all(
        "SELECT complaints.* FROM complaints JOIN bookings ON bookings.id = complaints.booking_id "
          + "WHERE complaints.created_at >= ? AND bookings.area = ?",
        [cutoff, area],
      );
      technicians = await conn.all("SELECT * FROM technicians WHERE area = ?", [area]);
    } else {
      bookings = await conn.all(`${BOOKING_SELECT} WHERE bookings.created_at >= ? ORDER BY created_at`, [cutoff]);
      complaints = await conn.all("SELECT * FROM complaints WHERE created_at >= ?", [cutoff]);
      technicians = await conn.all("SELECT * FROM technicians");
    }
  } finally {
    conn.close();
  }

  const completed = bookings.filter((b) => b.status === "Completed");
  const amountOf = (b) => (b.total_amount !== null && b.total_amount !== undefined ? b.total_amount : b.price);
  const add = (map, key, v) => map.set(key, (map.get(key) || 0) + v);

  const revenueByDay = new Map();
  const ratingSumByDay = new Map();
  const ratingCountByDay = new Map();
  const revenueByCategory = new Map();
  const jobsByTech = new Map();
  const revenueByTech = new Map();
  for (const b of completed) {
    const day = b.updated_at.slice(0, 10);
    add(revenueByDay, day, amountOf(b));
    if (b.service_rating !== null) {
      add(ratingSumByDay, day, b.service_rating);
      add(ratingCountByDay, day, 1);
    }
    add(revenueByCategory, b.category, amountOf(b));
    add(jobsByTech, b.technician_id, 1);
    add(revenueByTech, b.technician_id, amountOf(b));
  }
  const sortedKeys = (map) => [...map.keys()].sort();
  const grossRevenue = [...revenueByDay.values()].reduce((a, v) => a + v, 0);
  const complaintStatusBreakdown = new Map();
  for (const c of complaints) add(complaintStatusBreakdown, c.status, 1);

  const isOwner = req.staff.role === "owner";
  const result = {
    period,
    revenueTrend: sortedKeys(revenueByDay).map((d) => ({ date: d, revenue: revenueByDay.get(d) })),
    ratingTrend: sortedKeys(ratingCountByDay).map((d) => ({
      date: d, avgRating: pyRound(ratingSumByDay.get(d) / ratingCountByDay.get(d), 2),
    })),
    revenueByCategory: [...revenueByCategory.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([category, revenue]) => ({ category, revenue })),
    technicianLeaderboard: technicians
      .map((t) => ({
        id: t.id,
        name: t.name,
        jobsInPeriod: jobsByTech.get(t.id) || 0,
        revenueInPeriod: revenueByTech.get(t.id) || 0,
        rating: pyRound(t.rating, 1),
      }))
      .sort((a, b) => b.revenueInPeriod - a.revenueInPeriod),
    complaintStatusBreakdown: [...complaintStatusBreakdown.entries()].map(([status, count]) => ({ status, count })),
    grossRevenue,
    completedJobs: completed.length,
    isOwner,
    pnl: null,
  };
  if (isOwner) {
    const payout = pyRound(grossRevenue * TECH_PAYOUT_RATE);
    result.pnl = {
      grossRevenue, technicianPayout: payout, netMargin: grossRevenue - payout, payoutRateAssumed: TECH_PAYOUT_RATE,
    };
  }
  return res.json(result);
});

// Re-runs schema setup/seeding idempotently — no fake data is created.
app.post("/api/reset", requireStaffAuth, async (req, res) => {
  await initDb();
  res.json({ ok: true });
});

// ---------------------------------------------------------------- Home Services
// Backs homeservices.html. Reuses the RasoiCare login; every row is scoped
// to the signed-in user.
function hsBookingRowToDict(row) {
  return {
    id: row.id,
    serviceId: row.service_id,
    serviceName: row.service_name,
    price: row.price,
    date: row.date,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function hsWalletState(conn, userId) {
  const wallet = await conn.get("SELECT * FROM hs_wallet WHERE user_id = ?", [userId]);
  const tx = await conn.all("SELECT * FROM hs_wallet_tx WHERE user_id = ? ORDER BY created_at DESC", [userId]);
  return {
    points: wallet ? wallet.points : 100,
    tx: tx.map((t) => ({ label: t.label, amount: t.amount, ts: t.created_at })),
  };
}

function hsProfileDict(row, fallbackName) {
  if (!row) return { name: fallbackName, plan: null };
  return { name: row.name || fallbackName, plan: row.plan };
}

/** First Home Services call for a user creates their wallet (100 starter
 * points) and profile; a no-op afterwards. */
async function hsEnsureWalletAndProfile(conn, userId, fallbackName) {
  if (!(await conn.get("SELECT 1 AS x FROM hs_wallet WHERE user_id = ?", [userId]))) {
    await conn.run("INSERT INTO hs_wallet (user_id, points) VALUES (?, 100)", [userId]);
  }
  if (!(await conn.get("SELECT 1 AS x FROM hs_profile WHERE user_id = ?", [userId]))) {
    await conn.run("INSERT INTO hs_profile (user_id, name, plan) VALUES (?, ?, NULL)", [userId, fallbackName]);
  }
  await conn.commit();
}

app.get("/api/hs/state", requireAuth, async (req, res) => {
  const userId = req.user.id;
  const conn = await getDb();
  try {
    await hsEnsureWalletAndProfile(conn, userId, req.user.name);
    const bookings = await conn.all("SELECT * FROM hs_bookings WHERE user_id = ? ORDER BY created_at DESC", [userId]);
    const profile = await conn.get("SELECT * FROM hs_profile WHERE user_id = ?", [userId]);
    return res.json({
      bookings: bookings.map(hsBookingRowToDict),
      wallet: await hsWalletState(conn, userId),
      profile: hsProfileDict(profile, req.user.name),
    });
  } finally {
    conn.close();
  }
});

app.post(
  "/api/hs/bookings",
  requireAuth,
  validateJson({
    serviceId: new Field("str", { required: true, minLen: 1, maxLen: 50 }),
    date: new Field("str", { required: true, minLen: 1, maxLen: 50 }),
  }),
  async (req, res) => {
    const { serviceId, date } = body(req);
    if (!Object.hasOwn(HS_SERVICES, serviceId)) return res.status(400).json({ error: `Unknown serviceId: ${serviceId}` });
    const [serviceName, price] = HS_SERVICES[serviceId];
    const conn = await getDb();
    try {
      await hsEnsureWalletAndProfile(conn, req.user.id, req.user.name);
      const bookingId = newUuidId("HS");
      const ts = now();
      await conn.run(
        "INSERT INTO hs_bookings (id, user_id, service_id, service_name, price, date, status, created_at, updated_at) "
          + "VALUES (?,?,?,?,?,?,?,?,?)",
        [bookingId, req.user.id, serviceId, serviceName, price, date, STATUS_ORDER[0], ts, ts],
      );
      await conn.commit();
      return res.status(201).json(hsBookingRowToDict(await conn.get("SELECT * FROM hs_bookings WHERE id = ?", [bookingId])));
    } finally {
      conn.close();
    }
  },
);

app.patch("/api/hs/bookings/:bookingId/advance", requireAuth, async (req, res) => {
  // Moves a booking to its next status; 5% cashback on reaching Completed.
  const userId = req.user.id;
  const { bookingId } = req.params;
  const conn = await getDb();
  try {
    let row = await conn.get("SELECT * FROM hs_bookings WHERE id = ? AND user_id = ?", [bookingId, userId]);
    if (!row) return notFound(res);
    await hsEnsureWalletAndProfile(conn, userId, req.user.name);
    const idx = Math.max(0, STATUS_ORDER.indexOf(row.status));
    if (idx < STATUS_ORDER.length - 1) {
      const newStatus = STATUS_ORDER[idx + 1];
      await conn.run("UPDATE hs_bookings SET status = ?, updated_at = ? WHERE id = ?", [newStatus, now(), bookingId]);
      if (newStatus === "Completed") {
        const earned = pyRound(row.price * 0.05);
        await conn.run("UPDATE hs_wallet SET points = points + ? WHERE user_id = ?", [earned, userId]);
        await conn.run(
          "INSERT INTO hs_wallet_tx (id, user_id, label, amount, created_at) VALUES (?,?,?,?,?)",
          [newUuidId("TX"), userId, `Cashback: ${row.service_name}`, earned, now()],
        );
      }
      await conn.commit();
      row = await conn.get("SELECT * FROM hs_bookings WHERE id = ?", [bookingId]);
    }
    return res.json({ booking: hsBookingRowToDict(row), wallet: await hsWalletState(conn, userId) });
  } finally {
    conn.close();
  }
});

app.post("/api/hs/wallet/redeem", requireAuth, async (req, res) => {
  const userId = req.user.id;
  const conn = await getDb();
  try {
    await hsEnsureWalletAndProfile(conn, userId, req.user.name);
    const wallet = await conn.get("SELECT * FROM hs_wallet WHERE user_id = ?", [userId]);
    if (wallet.points < 50) return res.status(400).json({ error: "Not enough points" });
    await conn.run("UPDATE hs_wallet SET points = points - 50 WHERE user_id = ?", [userId]);
    await conn.run(
      "INSERT INTO hs_wallet_tx (id, user_id, label, amount, created_at) VALUES (?,?,?,?,?)",
      [newUuidId("TX"), userId, "Redeemed for ₹5 off", -50, now()],
    );
    await conn.commit();
    return res.json(await hsWalletState(conn, userId));
  } finally {
    conn.close();
  }
});

app.patch(
  "/api/hs/profile",
  requireAuth,
  validateJson({
    name: new Field("str", { maxLen: 100 }),
    plan: new Field("str", { maxLen: 100 }),
  }),
  async (req, res) => {
    const data = body(req);
    const userId = req.user.id;
    const conn = await getDb();
    try {
      await hsEnsureWalletAndProfile(conn, userId, req.user.name);
      if (data.name) await conn.run("UPDATE hs_profile SET name = ? WHERE user_id = ?", [data.name.trim(), userId]);
      if ("plan" in data) await conn.run("UPDATE hs_profile SET plan = ? WHERE user_id = ?", [data.plan ?? null, userId]);
      await conn.commit();
      const row = await conn.get("SELECT * FROM hs_profile WHERE user_id = ?", [userId]);
      return res.json(hsProfileDict(row, req.user.name));
    } finally {
      conn.close();
    }
  },
);

app.post("/api/hs/reset", requireAuth, async (req, res) => {
  const userId = req.user.id;
  const conn = await getDb();
  try {
    await conn.run("DELETE FROM hs_bookings WHERE user_id = ?", [userId]);
    await conn.run("DELETE FROM hs_wallet_tx WHERE user_id = ?", [userId]);
    await conn.run("UPDATE hs_wallet SET points = 100 WHERE user_id = ?", [userId]);
    await conn.run("UPDATE hs_profile SET name = ?, plan = NULL WHERE user_id = ?", [req.user.name, userId]);
    await conn.commit();
    return res.json({ ok: true });
  } finally {
    conn.close();
  }
});

// ---------------------------------------------------------------- fallbacks
app.use((req, res) => res.status(404).json({ error: "Not Found" }));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err.type === "entity.too.large" || err.status === 413) {
    return res.status(413).json({ error: "Payload Too Large", message: "Request body is too large." });
  }
  console.error(err);
  return res.status(500).json({ error: "Internal Server Error" });
});

module.exports = { app, pyRound, inferCity, computeCommissionPaise, weekStartIso, monthStartIso };
