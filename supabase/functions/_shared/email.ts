// supabase/functions/_shared/email.ts
// ─────────────────────────────────────────────────────────────────────────────
// Resend email helper — used by auth-password (forgot-password) and any other
// function that needs to send branded transactional mail.
//
// Expects the Supabase secret `RESEND_API_KEY` to be set (Dashboard →
// Edge Functions → Secrets or `supabase secrets set RESEND_API_KEY=...`).
// Optional secrets / env:
//
//   RESEND_FROM_EMAIL  — verified sender address (e.g. noreply@jiretaloanscorp.com)
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

export async function sendPasswordResetOtpEmail(params: SendOtpEmailParams): Promise<{ ok: boolean; id?: string; error?: string }> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY not set — skipping Resend send");
    return { ok: false, error: "RESEND_API_KEY not configured" };
  }
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? Deno.env.get("RESEND_FROM") ?? "onboarding@resend.dev";
  const fromName = Deno.env.get("RESEND_FROM_NAME") ?? "Jireta Loans";
  const from = fromEmail.includes("<") ? fromEmail : `${fromName} <${fromEmail}>`;
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
      console.error(`[email] Resend OTP failed ${res.status}: ${body}`);
      return { ok: false, error: `${res.status} ${body}`.slice(0, 500) };
    }
    const data = await res.json().catch(() => ({} as Record<string, unknown>));
    const id = (data as { id?: string })?.id;
    console.log(`[email] Resend OTP sent to ${params.to} id=${id ?? "unknown"}`);
    return { ok: true, id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[email] Resend OTP fetch error:", msg);
    return { ok: false, error: msg };
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

export async function sendLoginOtpEmail(params: SendOtpEmailParams): Promise<{ ok: boolean; id?: string; error?: string }> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY not set — skipping Resend login OTP send");
    return { ok: false, error: "RESEND_API_KEY not configured" };
  }
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? Deno.env.get("RESEND_FROM") ?? "onboarding@resend.dev";
  const fromName = Deno.env.get("RESEND_FROM_NAME") ?? "Jireta Loans";
  const from = fromEmail.includes("<") ? fromEmail : `${fromName} <${fromEmail}>`;
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
      console.error(`[email] Resend login OTP failed ${res.status}: ${body}`);
      return { ok: false, error: `${res.status} ${body}`.slice(0, 500) };
    }
    const data = await res.json().catch(() => ({} as Record<string, unknown>));
    const id = (data as { id?: string })?.id;
    console.log(`[email] Resend login OTP sent to ${params.to} id=${id ?? "unknown"}`);
    return { ok: true, id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[email] Resend login OTP fetch error:", msg);
    return { ok: false, error: msg };
  }
}

/**
 * Sends a password-reset email through Resend (https://resend.com).
 * Returns true on 2xx, false otherwise (caller should log and optionally
 * fall back to Supabase's built-in email).
 */
export async function sendPasswordResetEmail(params: SendResetEmailParams): Promise<{ ok: boolean; id?: string; error?: string }> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY not set — skipping Resend send");
    return { ok: false, error: "RESEND_API_KEY not configured" };
  }

  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? Deno.env.get("RESEND_FROM") ?? "onboarding@resend.dev";
  const fromName = Deno.env.get("RESEND_FROM_NAME") ?? "Jireta Loans";
  // Resend requires `from` in the form `Name <email>` when a name is used.
  const from = fromEmail.includes("<") ? fromEmail : `${fromName} <${fromEmail}>`;

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
      console.error(`[email] Resend failed ${res.status}: ${body}`);
      return { ok: false, error: `${res.status} ${body}`.slice(0, 500) };
    }

    const data = await res.json().catch(() => ({} as Record<string, unknown>));
    const id = (data as { id?: string })?.id;
    console.log(`[email] Resend sent to ${params.to} id=${id ?? "unknown"}`);
    return { ok: true, id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[email] Resend fetch error:", msg);
    return { ok: false, error: msg };
  }
}
