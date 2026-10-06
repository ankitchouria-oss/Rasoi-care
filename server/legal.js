/*
 * Real Terms of Service / Privacy Policy text, describing what this
 * codebase actually does. Served as JSON (/api/legal/*) for the apps and
 * as plain HTML (/terms, /privacy). Update LEGAL_CONTACT_EMAIL to a real,
 * monitored address before shipping.
 */

const LEGAL_CONTACT_EMAIL = "support@rasoicare.in";
const LEGAL_LAST_UPDATED = "23 August 2026";

const TERMS_OF_SERVICE_SECTIONS = [
  {
    "heading": "Who we are and what these terms cover",
    "paragraphs": [
      "Rasoi Care operates a marketplace connecting customers who need home-appliance repair, installation, and annual maintenance with independent service technicians (\"Partners\"). These Terms of Service govern your use of the Rasoi Care Customer app, the Rasoi Care Partner app, and the Rasoi Care Admin console (together, the \"Services\"). By creating an account or booking a service you agree to these terms."
    ]
  },
  {
    "heading": "Eligibility",
    "paragraphs": [
      "You must be at least 18 years old to create an account or book a service through Rasoi Care. The Services are not directed at anyone under 18, and we do not knowingly allow accounts for anyone under that age. If we learn an account belongs to someone under 18, we will close it."
    ]
  },
  {
    "heading": "Your account",
    "paragraphs": [
      "You can sign in by phone OTP, email and password, or Google sign-in. You're responsible for the accuracy of the details on your account and for keeping your device and sign-in credentials secure.",
      "Partner accounts go through an extra step: before a technician account can accept jobs, we require identity details, a government ID document, and payout bank details, and a member of our team reviews the application before it goes live."
    ]
  },
  {
    "heading": "Booking a service",
    "paragraphs": [
      "You choose an appliance category and describe the issue, pick an address and time, and a Partner accepts the job. A booking moves through a fixed sequence — Requested, Accepted, On the way, In Progress, Completed — and we show you which stage it's at.",
      "Before a job can be marked Completed, the Partner records a before photo, an after photo, and your signature confirming the work was done."
    ]
  },
  {
    "heading": "Cancelling a booking",
    "paragraphs": [
      "You can cancel a booking at any time before it's completed. If a Partner has already been assigned or has started travelling to you, cancelling may carry a fee that scales with how far the job had progressed — shown to you in the app before you confirm the cancellation. That fee compensates the Partner for time already committed to your job."
    ]
  },
  {
    "heading": "Payment",
    "paragraphs": [
      "You pay the Partner directly — in cash, by UPI, by card, or via a payment link — at the time of service, and the Partner records which method you used. Rasoi Care does not process payments and does not receive or store your card or bank details."
    ]
  },
  {
    "heading": "Partners",
    "paragraphs": [
      "Partners are independent technicians, not Rasoi Care employees. We expect Partners to behave professionally, honour the agreed price, and use the app's photo and signature steps to confirm completed work. We can suspend a Partner account over safety issues, fraud, or conduct complaints."
    ]
  },
  {
    "heading": "Location sharing during a booking",
    "paragraphs": [
      "Once a Partner accepts your booking, their live location is shared with you inside the app so you can track their arrival. That sharing stops as soon as the job is completed or cancelled — we don't track a Partner's location outside an active job, and we don't share your address with a Partner until they're assigned to your booking."
    ]
  },
  {
    "heading": "Reviews and other features",
    "paragraphs": [
      "You can rate and review a completed job — reviews should be honest, since other customers and our Partner-quality process both rely on them. Optional features like referral codes and reward coins are described where you use them in the app and are subject to whatever terms are shown there at the time."
    ]
  },
  {
    "heading": "Liability",
    "paragraphs": [
      "Services are carried out by independent Partners, and we're not liable for pre-existing appliance faults unrelated to the work performed. To the extent the law allows, our liability arising from a booking is limited to the amount you paid for that booking."
    ]
  },
  {
    "heading": "Suspension and account closure",
    "paragraphs": [
      "We may suspend or close an account for fraud, abuse, non-payment, or a breach of these terms. You can stop using the Services and ask us to delete your account at any time by writing to support@rasoicare.in."
    ]
  },
  {
    "heading": "Changes to these terms",
    "paragraphs": [
      "We may update these terms as the Services change. We'll update the date at the top of this page and, for material changes, let you know inside the app."
    ]
  },
  {
    "heading": "Governing law",
    "paragraphs": [
      "These terms are governed by the laws of India, and courts located in India have exclusive jurisdiction over any dispute arising from them."
    ]
  },
  {
    "heading": "Contact us",
    "paragraphs": [
      "Questions about these terms can be sent to support@rasoicare.in."
    ]
  }
];

const PRIVACY_POLICY_SECTIONS = [
  {
    "heading": "Scope",
    "paragraphs": [
      "This Privacy Policy covers the Rasoi Care Customer app, Partner app, and Admin console, and the backend they all talk to."
    ]
  },
  {
    "heading": "Information we collect",
    "paragraphs": [
      "Account information: your name, phone number, and email address, from phone-OTP, email, or Google sign-in (handled by Firebase Authentication).",
      "Profile information: your saved address(es) and their map coordinates, and the appliances you tell us you own.",
      "Booking information: the appliance category and issue you describe, any notes or photos you attach, and the booking's status history.",
      "Location: your saved address coordinates, and — only while a Partner is en route to or working on your active booking — the Partner's live location, so you can track their arrival.",
      "Job-completion records: a before photo, an after photo, and a signature, captured by the Partner to confirm the work performed on your booking.",
      "Partner verification information (Partner app only): date of birth, address, ID numbers (Aadhaar, PAN), ID document photos, and bank account and IFSC details, collected to verify identity and pay out earnings.",
      "Payment method label: whether a booking was paid by cash, UPI, card, or link, as recorded by the Partner — we don't collect or store card numbers or bank credentials for customer payments, since payment happens directly between you and the Partner.",
      "Device preferences: language, theme, and notification choices, stored on your device.",
      "Ratings and reviews you submit about a completed booking."
    ]
  },
  {
    "heading": "How we use this information",
    "paragraphs": [
      "To create and run your account, match you with a Partner, show live tracking, verify Partner applications, calculate and pay out Partner earnings, look into complaints, and keep improving the Services."
    ]
  },
  {
    "heading": "Who we share it with",
    "paragraphs": [
      "The Partner assigned to your booking sees your name, address, phone number, and issue details, so they can carry out the job.",
      "While a booking is active, the Partner app shows the assigned customer's location and profile name for that job only.",
      "Firebase Authentication and Cloud Firestore (Google LLC) provide our sign-in and profile-storage infrastructure.",
      "Google Maps Platform provides maps, address lookup, and live-tracking display.",
      "We do not sell your personal information. Partner verification documents (ID numbers, ID photos, bank details) are used only for verification and payout, and are not shared outside that process."
    ]
  },
  {
    "heading": "Data security",
    "paragraphs": [
      "We use reasonable technical safeguards — including hashed passwords, signed session tokens, and HTTPS in transit — and restrict access to sensitive Partner verification documents to the verification and payout process."
    ]
  },
  {
    "heading": "Data retention",
    "paragraphs": [
      "We keep account and booking records for as long as your account is active, and as long as needed to resolve disputes or meet legal and accounting obligations. You can ask us to delete your account and its associated data at any time; some records (such as completed-transaction history) may need to be retained for longer where the law requires it."
    ]
  },
  {
    "heading": "Your rights",
    "paragraphs": [
      "You can ask to access, correct, or delete your personal information by writing to support@rasoicare.in. Partners can also update most verification details directly from their profile in the Partner app."
    ]
  },
  {
    "heading": "Children's privacy",
    "paragraphs": [
      "The Services are for users aged 18 and over, and we do not knowingly collect personal information from children. If you believe a child has given us information, contact support@rasoicare.in and we'll delete it."
    ]
  },
  {
    "heading": "Changes to this policy",
    "paragraphs": [
      "We may update this policy as the Services change. We'll update the date at the top of this page when we do."
    ]
  },
  {
    "heading": "Contact us",
    "paragraphs": [
      "Questions about this policy can be sent to support@rasoicare.in."
    ]
  }
];

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#x27;");
}

function legalDocPayload(title, sections) {
  return { title, lastUpdated: LEGAL_LAST_UPDATED, sections };
}

function legalDocHtml(title, sections) {
  const body = sections
    .map(({ heading, paragraphs }) =>
      `<h2>${escapeHtml(heading)}</h2>` + paragraphs.map((p) => `<p>${escapeHtml(p)}</p>`).join(""))
    .join("");
  return (
    '<!doctype html><html lang="en"><head><meta charset="utf-8">'
    + '<meta name="viewport" content="width=device-width, initial-scale=1">'
    + `<title>Rasoi Care — ${escapeHtml(title)}</title>`
    + "<style>"
    + "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;"
    + "max-width:700px;margin:0 auto;padding:32px 20px 60px;color:#1c1c1e;line-height:1.55}"
    + "h1{font-size:26px;margin-bottom:4px}"
    + "h2{font-size:17px;margin-top:28px;margin-bottom:8px}"
    + ".updated{color:#6b6b70;font-size:13px;margin-bottom:24px}"
    + "p{font-size:15px;margin:0 0 10px}"
    + "</style></head><body>"
    + `<h1>${escapeHtml(title)}</h1>`
    + `<div class="updated">Last updated ${escapeHtml(LEGAL_LAST_UPDATED)}</div>`
    + body
    + "</body></html>"
  );
}

module.exports = {
  TERMS_OF_SERVICE_SECTIONS,
  PRIVACY_POLICY_SECTIONS,
  legalDocPayload,
  legalDocHtml,
};
