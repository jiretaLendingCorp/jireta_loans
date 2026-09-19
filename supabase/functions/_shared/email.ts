// supabase/functions/_shared/email.ts
// ─────────────────────────────────────────────────────────────────────────────
// Resend email helper — used by auth-password (forgot-password) and any other
// function that needs to send branded transactional mail.
//
// Expects the Supabase secret `RESEND_API_KEY` to be set (Dashboard →
// Edge Functions → Secrets or `supabase secrets set RESEND_API_KEY=...`).
// Secrets / env:
//
//   RESEND_FROM_EMAIL  — REQUIRED in production: a sender on a domain verified
//                        in Resend (e.g. noreply@mail.jireta.com). When unset we
//                        fall back to onboarding@resend.dev, which Resend only
//                        delivers to the account owner — every other recipient
//                        gets HTTP 403 "testing domain restriction".
//   RESEND_FROM_NAME   — display name (default: "Jireta Loans")
//   APP_URL            — web app origin used for reset links (default: https://app.jiretaloanscorp.com)
//
// In local dev (no RESEND_API_KEY) the caller should fall back to
// `db.auth.resetPasswordForEmail(...)` so the email still appears in
// Inbucket (http://127.0.0.1:54324).
// ─────────────────────────────────────────────────────────────────────────────

export interface SendResetEmailParams {
  to: string;
  resetLink: string;
  recipientName?: string;
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/**
 * Builds the `from` header ("Name <email>") for Resend.
 *
 * Resend rejects the shared testing sender `onboarding@resend.dev` for any
 * recipient other than the Resend account owner, so the fallback below is only
 * useful when someone is testing with their own inbox — warn loudly instead of
 * letting every OTP silently bounce with a 403.
 */
export function resolveFromAddress(): string {
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? Deno.env.get("RESEND_FROM");
  const fromName = Deno.env.get("RESEND_FROM_NAME") ?? "Jireta Loans";
  if (!fromEmail) {
    console.warn(
      "[email] RESEND_FROM_EMAIL is not set — falling back to onboarding@resend.dev. " +
      "Resend only delivers from that address to the account owner's own inbox; " +
      "all other recipients get 403 'testing domain restriction'. Set RESEND_FROM_EMAIL " +
      "to an address on a verified domain (e.g. noreply@mail.jireta.com).",
    );
    return `${fromName} <onboarding@resend.dev>`;
  }
  // Resend requires `from` in the form `Name <email>` when a name is used.
  return fromEmail.includes("<") ? fromEmail : `${fromName} <${fromEmail}>`;
}

/** Why a Resend send failed — callers turn this into a user-facing hint. */
export type EmailFailureKind =
  | "no_api_key"
  | "invalid_api_key"
  | "sender_not_verified"
  | "recipient_rejected"
  | "rate_limited"
  | "timeout"
  | "http_error";

export interface SendEmailResult {
  ok: boolean;
  id?: string;
  error?: string;
  /** Upstream HTTP status from Resend, when there was a response. */
  status?: number;
  /** Coarse cause, so callers can explain the failure instead of guessing. */
  kind?: EmailFailureKind;
}

const FAILURE_HINTS: Record<EmailFailureKind, string> = {
  no_api_key: "set the RESEND_API_KEY secret on the Supabase project",
  invalid_api_key: "RESEND_API_KEY is missing or revoked — create a new key in Resend",
  sender_not_verified:
    "set RESEND_FROM_EMAIL to an address on a domain verified in Resend — " +
    "onboarding@resend.dev only delivers to the Resend account owner's own inbox",
  recipient_rejected: "Resend rejected the recipient address",
  rate_limited: "Resend rate limit reached",
  timeout: "Resend did not answer within 10s",
  http_error: "see the Resend error body above",
};

export function classifyResendFailure(status: number, body: string): EmailFailureKind {
  const text = body.toLowerCase();
  if (status === 401) return "invalid_api_key";
  if (status === 403) {
    if (text.includes("api key")) return "invalid_api_key";
    // "Testing domain restriction" means the sender is still
    // onboarding@resend.dev; any other 403 is an unverified sender domain.
    return "sender_not_verified";
  }
  if (status === 422) return "recipient_rejected";
  if (status === 429) return "rate_limited";
  return "http_error";
}

function failureLog(
  label: string,
  status: number,
  kind: EmailFailureKind,
  from: string,
  to: string,
  body: string,
): string {
  return `[email] Resend ${label} ${status} [${kind}] from=${from} to=${to}: ${body} — ${FAILURE_HINTS[kind]}`;
}

function classifyFetchError(msg: string): EmailFailureKind {
  const lower = msg.toLowerCase();
  return lower.includes("abort") || lower.includes("timeout") ? "timeout" : "http_error";
}

function buildResetHtml(resetLink: string, recipientName?: string): string {
  const safeLink = escapeHtml(resetLink);
  const greeting = recipientName ? `Hi ${escapeHtml(recipientName)},` : "Hi,";
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background-color:#f3f4f6;font-family:Inter,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f3f4f6;padding:24px 0;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e5e7eb;">
        <tr>
          <td style="background:#0f1f3c;padding:24px 28px;text-align:center;">
            <div style="font-family:Playfair Display,serif;font-size:20px;font-weight:700;color:#d4a017;letter-spacing:0.5px;">JIRETA LOANS</div>
            <div style="font-size:11px;color:#ffffff99;letter-spacing:1.2px;text-transform:uppercase;margin-top:4px;">Credit Corp 1966</div>
          </td>
        </tr>
        <tr>
          <td style="padding:28px;">
            <h2 style="margin:0 0 12px;font-size:18px;font-weight:700;color:#0f1f3c;">Reset your password</h2>
            <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#374151;">${greeting}</p>
            <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#374151;">
              We received a request to reset the password for your Jireta Loans account. Click the button below to set a new password. This link expires in <strong>1 hour</strong> and can only be used once.
            </p>
            <table cellpadding="0" cellspacing="0" style="margin:20px 0 16px;">
              <tr>
                <td align="center" style="border-radius:8px;background:#d4a017;">
                  <a href="${safeLink}" target="_blank" style="display:inline-block;padding:12px 28px;font-size:14px;font-weight:700;color:#0f1f3c;text-decoration:none;border-radius:8px;">Reset Password</a>
                </td>
              </tr>
            </table>
            <p style="margin:16px 0 8px;font-size:12px;line-height:1.5;color:#6b7280;">
              If the button doesn't work, copy and paste this URL into your browser:
            </p>
            <p style="margin:0 0 16px;word-break:break-all;font-size:12px;line-height:1.5;">
              <a href="${safeLink}" target="_blank" style="color:#0f1f3c;text-decoration:underline;">${safeLink}</a>
            </p>
            <hr style="border:none;border-top:1px solid #e5e7eb;margin:20px 0;"/>
            <p style="margin:0;font-size:12px;line-height:1.5;color:#9ca3af;">
              If you didn't request a password reset, you can safely ignore this email — your password will not be changed.
            </p>
          </td>
        </tr>
        <tr>
          <td style="background:#f9fafb;padding:16px 28px;text-align:center;border-top:1px solid #e5e7eb;">
            <p style="margin:0;font-size:11px;color:#9ca3af;">&copy; ${new Date().getFullYear()} Jireta Loans &amp; Credit Corp. All rights reserved.</p>
            <p style="margin:4px 0 0;font-size:11px;color:#9ca3af;">This is an automated message, please do not reply.</p>
          </td>
        </tr>
      </table>
      <p style="margin:12px 0 0;font-size:11px;color:#9ca3af;text-align:center;">Sent via Resend &bull; Jireta Loans Transactional Mail</p>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildResetText(resetLink: string): string {
  return `Reset your Jireta Loans password

We received a request to reset your password. Open the link below to set a new password. This link expires in 1 hour and can only be used once.

${resetLink}

If you didn't request this, you can safely ignore this email.

— Jireta Loans & Credit Corp 1966`;
}

// ── OTP-based reset (new flow) ─────────────────────────────────────────────
export interface SendOtpEmailParams {
  to: string;
  otp: string;
  recipientName?: string;
}

function buildOtpHtml(otp: string, recipientName?: string): string {
  const greeting = recipientName ? `Hi ${escapeHtml(recipientName)},` : "Hi,";
  const safeOtp = escapeHtml(otp);
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background-color:#f3f4f6;font-family:Inter,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f3f4f6;padding:24px 0;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e5e7eb;">
        <tr>
          <td style="background:#0f1f3c;padding:24px 28px;text-align:center;">
            <div style="font-family:Playfair Display,serif;font-size:20px;font-weight:700;color:#d4a017;letter-spacing:0.5px;">JIRETA LOANS</div>
            <div style="font-size:11px;color:#ffffff99;letter-spacing:1.2px;text-transform:uppercase;margin-top:4px;">Credit Corp 1966</div>
          </td>
        </tr>
        <tr>
          <td style="padding:28px;">
            <h2 style="margin:0 0 12px;font-size:18px;font-weight:700;color:#0f1f3c;">Your password reset code</h2>
            <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#374151;">${greeting}</p>
            <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#374151;">
              We received a request to reset the password for your Jireta Loans account. Use the code below to verify your email and set a new password. This code expires in <strong>1 minute</strong> and can only be used once.
            </p>
            <table width="100%" cellpadding="0" cellspacing="0" style="margin:24px 0;">
              <tr>
                <td align="center" style="background:#f3f4f6;border:1px dashed #d4a017;border-radius:12px;padding:16px;">
                  <div style="font-size:32px;font-weight:800;letter-spacing:8px;color:#0f1f3c;font-family:monospace;">${safeOtp}</div>
                  <div style="margin-top:8px;font-size:12px;color:#6b7280;letter-spacing:1px;text-transform:uppercase;">One-Time Code</div>
                </td>
              </tr>
            </table>
            <p style="margin:0 0 8px;font-size:12px;line-height:1.5;color:#6b7280;">
              Enter this code in the password reset screen to continue. If you didn't request a password reset, you can safely ignore this email — your password will not be changed.
            </p>
            <hr style="border:none;border-top:1px solid #e5e7eb;margin:20px 0;"/>
            <p style="margin:0;font-size:12px;line-height:1.5;color:#9ca3af;">
              For security, do not share this code with anyone. Jireta Loans will never ask for this code outside the official reset screen.
            </p>
          </td>
        </tr>
        <tr>
          <td style="background:#f9fafb;padding:16px 28px;text-align:center;border-top:1px solid #e5e7eb;">
            <p style="margin:0;font-size:11px;color:#9ca3af;">&copy; ${new Date().getFullYear()} Jireta Loans &amp; Credit Corp. All rights reserved.</p>
            <p style="margin:4px 0 0;font-size:11px;color:#9ca3af;">This is an automated message, please do not reply.</p>
          </td>
        </tr>
      </table>
      <p style="margin:12px 0 0;font-size:11px;color:#9ca3af;text-align:center;">Sent via Resend &bull; Jireta Loans Transactional Mail</p>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildOtpText(otp: string): string {
  return `Your Jireta Loans password reset code

We received a request to reset your password. Use the code below to verify your email:

${otp}

This code expires in 1 minute and can only be used once. If you didn't request this, you can safely ignore this email.

— Jireta Loans & Credit Corp 1966`;
}

export async function sendPasswordResetOtpEmail(params: SendOtpEmailParams): Promise<SendEmailResult> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY not set — skipping Resend send");
    return { ok: false, error: "RESEND_API_KEY not configured" };
  }
  const from = resolveFromAddress();
  const html = buildOtpHtml(params.otp, params.recipientName);
  const text = buildOtpText(params.otp);
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from,
        to: [params.to],
        subject: `Your Jireta Loans reset code is ${params.otp}`,
        html,
        text,
        tags: [{ name: "category", value: "password_reset_otp" }],
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      const kind = classifyResendFailure(res.status, body);
      console.error(failureLog("OTP failed", res.status, kind, from, params.to, body));
      return { ok: false, error: `${res.status} ${body}`.slice(0, 500), status: res.status, kind };
    }
    const data = await res.json().catch(() => ({} as Record<string, unknown>));
    const id = (data as { id?: string })?.id;
    console.log(`[email] Resend OTP sent to ${params.to} id=${id ?? "unknown"}`);
    return { ok: true, id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const kind = classifyFetchError(msg);
    console.error(`[email] Resend OTP fetch error [${kind}]:`, msg);
    return { ok: false, error: msg, kind };
  }
}

// ── Mobile login OTP via Gmail (Resend) ─────────────────────────────────────
function buildLoginOtpHtml(otp: string, recipientName?: string): string {
  const greeting = recipientName ? `Hi ${escapeHtml(recipientName)},` : "Hi,";
  const safeOtp = escapeHtml(otp);
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background-color:#f3f4f6;font-family:Inter,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f3f4f6;padding:24px 0;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e5e7eb;">
        <tr>
          <td style="background:#0f1f3c;padding:24px 28px;text-align:center;">
            <div style="font-family:Playfair Display,serif;font-size:20px;font-weight:700;color:#d4a017;letter-spacing:0.5px;">JIRETA LOANS</div>
            <div style="font-size:11px;color:#ffffff99;letter-spacing:1.2px;text-transform:uppercase;margin-top:4px;">Credit Corp 1966</div>
          </td>
        </tr>
        <tr>
          <td style="padding:28px;">
            <h2 style="margin:0 0 12px;font-size:18px;font-weight:700;color:#0f1f3c;">Your login verification code</h2>
            <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#374151;">${greeting}</p>
            <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#374151;">
              Use the code below to verify your mobile login to Jireta Loans. This code expires in <strong>1 minute</strong> and can only be used once.
            </p>
            <table width="100%" cellpadding="0" cellspacing="0" style="margin:24px 0;">
              <tr>
                <td align="center" style="background:#f3f4f6;border:1px dashed #d4a017;border-radius:12px;padding:16px;">
                  <div style="font-size:32px;font-weight:800;letter-spacing:8px;color:#0f1f3c;font-family:monospace;">${safeOtp}</div>
                  <div style="margin-top:8px;font-size:12px;color:#6b7280;letter-spacing:1px;text-transform:uppercase;">One-Time Code</div>
                </td>
              </tr>
            </table>
            <p style="margin:0 0 8px;font-size:12px;line-height:1.5;color:#6b7280;">
              Enter this code in the OTP screen to continue. If you didn't request this, you can safely ignore this email — your account remains secure.
            </p>
            <hr style="border:none;border-top:1px solid #e5e7eb;margin:20px 0;"/>
            <p style="margin:0;font-size:12px;line-height:1.5;color:#9ca3af;">
              For security, do not share this code with anyone. Jireta Loans will never ask for this code outside the official app.
            </p>
          </td>
        </tr>
        <tr>
          <td style="background:#f9fafb;padding:16px 28px;text-align:center;border-top:1px solid #e5e7eb;">
            <p style="margin:0;font-size:11px;color:#9ca3af;">&copy; ${new Date().getFullYear()} Jireta Loans &amp; Credit Corp. All rights reserved.</p>
            <p style="margin:4px 0 0;font-size:11px;color:#9ca3af;">This is an automated message, please do not reply.</p>
          </td>
        </tr>
      </table>
      <p style="margin:12px 0 0;font-size:11px;color:#9ca3af;text-align:center;">Sent via Resend &bull; Jireta Loans Transactional Mail</p>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildLoginOtpText(otp: string): string {
  return `Your Jireta Loans login verification code

We received a login request for your Jireta Loans account. Use the code below to verify your mobile number:

${otp}

This code expires in 1 minute and can only be used once. If you didn't request this, you can safely ignore this email.

— Jireta Loans & Credit Corp 1966`;
}

// ── Registration OTP via Resend (employee self-register) ──────────────────
function buildRegisterOtpHtml(otp: string, recipientName?: string): string {
  const greeting = recipientName ? `Hi ${escapeHtml(recipientName)},` : "Hi,";
  const safeOtp = escapeHtml(otp);
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background-color:#f3f4f6;font-family:Inter,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f3f4f6;padding:24px 0;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e5e7eb;">
        <tr>
          <td style="background:#0f1f3c;padding:24px 28px;text-align:center;">
            <div style="font-family:Playfair Display,serif;font-size:20px;font-weight:700;color:#d4a017;letter-spacing:0.5px;">JIRETA LOANS</div>
            <div style="font-size:11px;color:#ffffff99;letter-spacing:1.2px;text-transform:uppercase;margin-top:4px;">Credit Corp 1966</div>
          </td>
        </tr>
        <tr>
          <td style="padding:28px;">
            <h2 style="margin:0 0 12px;font-size:18px;font-weight:700;color:#0f1f3c;">Verify your email — registration code</h2>
            <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#374151;">${greeting}</p>
            <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#374151;">
              Thank you for registering as an employee of Jireta Loans. Use the code below to verify your email and complete your registration. This code expires in <strong>1 minute</strong> and can only be used once.
            </p>
            <table width="100%" cellpadding="0" cellspacing="0" style="margin:24px 0;">
              <tr>
                <td align="center" style="background:#f3f4f6;border:1px dashed #d4a017;border-radius:12px;padding:16px;">
                  <div style="font-size:32px;font-weight:800;letter-spacing:8px;color:#0f1f3c;font-family:monospace;">${safeOtp}</div>
                  <div style="margin-top:8px;font-size:12px;color:#6b7280;letter-spacing:1px;text-transform:uppercase;">One-Time Code</div>
                </td>
              </tr>
            </table>
            <p style="margin:0 0 8px;font-size:12px;line-height:1.5;color:#6b7280;">
              Enter this code in the registration screen to continue. If you didn't attempt to register, you can safely ignore this email.
            </p>
            <hr style="border:none;border-top:1px solid #e5e7eb;margin:20px 0;"/>
            <p style="margin:0;font-size:12px;line-height:1.5;color:#9ca3af;">
              For security, do not share this code with anyone. Jireta Loans will never ask for this code outside the official registration screen.
            </p>
          </td>
        </tr>
        <tr>
          <td style="background:#f9fafb;padding:16px 28px;text-align:center;border-top:1px solid #e5e7eb;">
            <p style="margin:0;font-size:11px;color:#9ca3af;">&copy; ${new Date().getFullYear()} Jireta Loans &amp; Credit Corp. All rights reserved.</p>
            <p style="margin:4px 0 0;font-size:11px;color:#9ca3af;">This is an automated message, please do not reply.</p>
          </td>
        </tr>
      </table>
      <p style="margin:12px 0 0;font-size:11px;color:#9ca3af;text-align:center;">Sent via Resend &bull; Jireta Loans Transactional Mail</p>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildRegisterOtpText(otp: string): string {
  return `Your Jireta Loans registration code

Thank you for registering as an employee. Use the code below to verify your email:

${otp}

This code expires in 1 minute and can only be used once. If you didn't attempt to register, you can safely ignore this email.

— Jireta Loans & Credit Corp 1966`;
}

export async function sendRegistrationOtpEmail(params: SendOtpEmailParams): Promise<SendEmailResult> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY not set — skipping Resend registration OTP send");
    return { ok: false, error: "RESEND_API_KEY not configured" };
  }
  const from = resolveFromAddress();
  const html = buildRegisterOtpHtml(params.otp, params.recipientName);
  const text = buildRegisterOtpText(params.otp);
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from,
        to: [params.to],
        subject: `Your Jireta Loans registration code is ${params.otp}`,
        html,
        text,
        tags: [{ name: "category", value: "register_otp" }],
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      const kind = classifyResendFailure(res.status, body);
      console.error(failureLog("register OTP failed", res.status, kind, from, params.to, body));
      return { ok: false, error: `${res.status} ${body}`.slice(0, 500), status: res.status, kind };
    }
    const data = await res.json().catch(() => ({} as Record<string, unknown>));
    const id = (data as { id?: string })?.id;
    console.log(`[email] Resend register OTP sent to ${params.to} id=${id ?? "unknown"}`);
    return { ok: true, id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const kind = classifyFetchError(msg);
    console.error(`[email] Resend register OTP fetch error [${kind}]:`, msg);
    return { ok: false, error: msg, kind };
  }
}

export async function sendLoginOtpEmail(params: SendOtpEmailParams): Promise<SendEmailResult> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY not set — skipping Resend login OTP send");
    return { ok: false, error: "RESEND_API_KEY not configured" };
  }
  const from = resolveFromAddress();
  const html = buildLoginOtpHtml(params.otp, params.recipientName);
  const text = buildLoginOtpText(params.otp);
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from,
        to: [params.to],
        subject: `Your Jireta Loans login code is ${params.otp}`,
        html,
        text,
        tags: [{ name: "category", value: "login_otp" }],
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      const kind = classifyResendFailure(res.status, body);
      console.error(failureLog("login OTP failed", res.status, kind, from, params.to, body));
      return { ok: false, error: `${res.status} ${body}`.slice(0, 500), status: res.status, kind };
    }
    const data = await res.json().catch(() => ({} as Record<string, unknown>));
    const id = (data as { id?: string })?.id;
    console.log(`[email] Resend login OTP sent to ${params.to} id=${id ?? "unknown"}`);
    return { ok: true, id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const kind = classifyFetchError(msg);
    console.error(`[email] Resend login OTP fetch error [${kind}]:`, msg);
    return { ok: false, error: msg, kind };
  }
}

/**
 * Sends a password-reset email through Resend (https://resend.com).
 * Returns true on 2xx, false otherwise (caller should log and optionally
 * fall back to Supabase's built-in email).
 */
export async function sendPasswordResetEmail(params: SendResetEmailParams): Promise<SendEmailResult> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY not set — skipping Resend send");
    return { ok: false, error: "RESEND_API_KEY not configured" };
  }

  const from = resolveFromAddress();

  const html = buildResetHtml(params.resetLink, params.recipientName);
  const text = buildResetText(params.resetLink);

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [params.to],
        subject: "Reset your Jireta Loans password",
        html,
        text,
        tags: [{ name: "category", value: "password_reset" }],
      }),
      signal: AbortSignal.timeout(10000),
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      const kind = classifyResendFailure(res.status, body);
      console.error(failureLog("send failed", res.status, kind, from, params.to, body));
      return { ok: false, error: `${res.status} ${body}`.slice(0, 500), status: res.status, kind };
    }

    const data = await res.json().catch(() => ({} as Record<string, unknown>));
    const id = (data as { id?: string })?.id;
    console.log(`[email] Resend sent to ${params.to} id=${id ?? "unknown"}`);
    return { ok: true, id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const kind = classifyFetchError(msg);
    console.error(`[email] Resend fetch error [${kind}]:`, msg);
    return { ok: false, error: msg, kind };
  }
}
