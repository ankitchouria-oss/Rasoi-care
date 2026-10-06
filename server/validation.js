/*
 * Request-body validation. Every POST/PATCH route declares a schema (field
 * name -> Field) and is wrapped with validateJson(schema). A mismatch —
 * wrong type, too long/short, out of range, wrong format — is rejected
 * outright with a 400 naming every bad field. Nothing is ever coerced,
 * truncated or escaped into shape; a handler only ever reads data that
 * already matched its schema. Fields not named in the schema are left
 * alone.
 */

const TYPE_NAMES = { str: "str", int: "int", number: "int or float", bool: "bool", list: "list", dict: "dict" };

function matchesType(value, type) {
  switch (type) {
    case "str": return typeof value === "string";
    case "int": return typeof value === "number" && Number.isInteger(value);
    case "number": return typeof value === "number" && Number.isFinite(value);
    case "bool": return typeof value === "boolean";
    case "list": return Array.isArray(value);
    case "dict": return value !== null && typeof value === "object" && !Array.isArray(value);
    default: return false;
  }
}

class Field {
  constructor(type, {
    required = false, minLen = null, maxLen = null, minVal = null, maxVal = null,
    pattern = null, choices = null, itemType = null, strip = true,
  } = {}) {
    Object.assign(this, { type, required, minLen, maxLen, minVal, maxVal, pattern, choices, itemType, strip });
  }

  /** Returns an error message, or null if `value` is valid. */
  validate(value) {
    if (!matchesType(value, this.type)) return `must be a ${TYPE_NAMES[this.type]}`;
    if (typeof value === "string") {
      const v = this.strip ? value.trim() : value;
      // An optional field left blank ("" rather than omitted/null) isn't
      // measured against a pattern/length/choices meant for a real value —
      // the Partner app always sends its "(optional)" fields, even empty.
      if (!v && !this.required) return null;
      if (this.minLen !== null && v.length < this.minLen) return `must be at least ${this.minLen} character(s)`;
      if (this.maxLen !== null && v.length > this.maxLen) return `must be at most ${this.maxLen} characters`;
      if (this.pattern !== null && !this.pattern.test(v)) return "is not in the expected format";
      if (this.choices !== null && !this.choices.includes(v)) return "must be one of: " + this.choices.join(", ");
    } else if (typeof value === "number") {
      if (this.minVal !== null && value < this.minVal) return `must be at least ${this.minVal}`;
      if (this.maxVal !== null && value > this.maxVal) return `must be at most ${this.maxVal}`;
      if (this.choices !== null && !this.choices.includes(value)) return "must be one of: " + this.choices.join(", ");
    } else if (Array.isArray(value)) {
      if (this.minLen !== null && value.length < this.minLen) return `must have at least ${this.minLen} item(s)`;
      if (this.maxLen !== null && value.length > this.maxLen) return `must have at most ${this.maxLen} item(s)`;
      if (this.itemType !== null) {
        for (let i = 0; i < value.length; i++) {
          if (!matchesType(value[i], this.itemType)) return `item ${i} must be a ${TYPE_NAMES[this.itemType]}`;
        }
      }
    }
    return null;
  }
}

/** Express middleware applying `schema` to req.body (already parsed by the
 * app's JSON reader — null when the body wasn't valid JSON). */
function validateJson(schema) {
  return (req, res, next) => {
    const data = req.body;
    if (data === null || typeof data !== "object" || Array.isArray(data)) {
      return res.status(400).json({ error: "Invalid request", message: "Request body must be a JSON object" });
    }
    const errors = {};
    for (const [name, field] of Object.entries(schema)) {
      if (!(name in data) || data[name] === null) {
        if (field.required) errors[name] = "is required";
        continue;
      }
      const message = field.validate(data[name]);
      if (message) errors[name] = message;
    }
    if (Object.keys(errors).length) {
      return res.status(400).json({ error: "Invalid request", fields: errors });
    }
    return next();
  };
}

const PATTERNS = {
  // Dot-separated domain labels: one way to match, so no polynomial backtracking.
  EMAIL: /^[^@\s]+@[^@\s.]+(?:\.[^@\s.]+)+$/,
  PHONE: /^[0-9]{10}$/,
  PAN: /^[A-Z]{5}[0-9]{4}[A-Z]$/,
  IFSC: /^[A-Z]{4}0[A-Z0-9]{6}$/,
  AADHAAR: /^[0-9]{12}$/,
  GSTIN: /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z][Z][0-9A-Z]$/,
  UPI_ID: /^[\w.-]{2,256}@[a-zA-Z]{2,64}$/,
  DATE: /^\d{4}-\d{2}-\d{2}$/,
  ISO_DATETIME: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})?$/,
  CODE: /^[0-9]{4}$/,
  PIN: /^[0-9]{4,8}$/,
  BASE64: /^[A-Za-z0-9+/]*={0,2}$/,
  BANK_ACCOUNT: /^[0-9]{5,20}$/,
  URL: /^https?:\/\/\S{1,2000}$/,
};

module.exports = { Field, validateJson, PATTERNS };
