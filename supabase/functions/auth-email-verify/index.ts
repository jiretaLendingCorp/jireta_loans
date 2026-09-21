// supabase/functions/auth-email-verify/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — maraming aksyon sa ISANG deployable function gamit ang
// `?fn=<action>` query parameter (kapareho ng auth-session / auth-password).
//
//   ?fn=send      (kailangan ng auth)  → gumagawa ng one-time LINK token at
//                                        ipinapadala ito sa email via Resend.
//                                        Ito ang tinatawag ng "Resend Email"
//                                        button sa Verify Your Email screen.
//   ?fn=confirm   (PUBLIC)             → ito ang binubuksan ng link sa email.
//                                        Minamarkahan nito ang
//                                        `users.email_verified_at` at nagbabalik
//                                        ng simpleng HTML na "verified" page.
//   ?fn=status    (kailangan ng auth)  → kung verified na ba ang email ng
//                                        account, para makaalis na ang app sa
//                                        Verify Your Email screen.
//
// LINK ang verification dito — HINDI 6-digit OTP. Ang token ay 256-bit random
// at ang SHA-256 hash lang ang naka-store (tingnan ang _shared/reset_token.ts),
// kaya kahit may makakuha ng database dump ay hindi ma-replay ang link.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { isAuthUser, requireAuth } from '../_shared/auth.ts';
import {
  corsHeadersFor,
  errorResponse,
  handleCors,
  jsonResponse,
} from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sendEmailVerificationEmail } from '../_shared/email.ts';
import {
  generateResetToken,
  hashResetToken,
  isResetToken,
} from '../_shared/reset_token.ts';
import { sanitizeString, validateEmail } from '../_shared/validators.ts';

const DEFAULT_ACTION = 'send';

/** Gaano katagal bago ma-expire ang link sa email. */
const LINK_TTL_MINUTES = 60;

/** Pagitan bago muling makapag-resend (iwas-spam / dobleng pindot). */
const RESEND_COOLDOWN_SECONDS = 15;

/**
 * Ang BRANDED na public URL ng Verify Email page — ito ang nakalagay sa link
 * ng email.
 *
 * MAHALAGA: hindi `supabase.co` ang dapat makita ng user, at hindi rin `req.url`
 * ang pinagmulan nito. Sa loob ng Supabase edge runtime, ang `req.url` ay ang
 * INTERNAL/relay URL (walang `/functions/v1` prefix) — kaya nang gawin itong
 * link, ang resulta ay `http://<ref>.supabase.co/auth-email-verify?fn=confirm`
 * at ang tugon ng gateway ay **"requested path is invalid"**.
 *
 * Ang link ay papunta na ngayon sa web app ng Jireta Loans:
 *   https://www.jireta.com/verify-email?t=<token>
 * Nababasa ng app ang `t` at tinatawag ang `?fn=confirm-json` ng function na
 * ito. Maaaring baguhin ang domain sa pamamagitan ng `APP_URL` secret.
 */
function verifyPageUrl(): string {
  const base = (Deno.env.get('APP_URL') ?? '').trim().replace(/\/+$/, '');
  const origin = base || DEFAULT_APP_URL;
  return `${origin}/verify-email`;
}

/** Ang production web app ng Jireta Loans (kung walang `APP_URL` secret). */
const DEFAULT_APP_URL = 'https://www.jireta.com';

/**
 * Mas tapat na paliwanag kung bakit hindi naipadala ang email — hinango mula sa
 * `kind` na isinasauli ng email helper (kapareho ng pattern sa auth-register).
 * Kung generic na mensahe lang ang ipapakita, mahirap ayusin ang totoong
 * dahilan, hal. hindi pa verified ang sender domain sa Resend kaya ang 403
 * "testing domain restriction" ay lumalabas para sa lahat ng recipient maliban
 * sa may-ari ng Resend account.
 */
function emailFailureMessage(result: {
  kind?: string;
  status?: number;
}): string {
  switch (result.kind) {
    case 'no_api_key':
      return 'Hindi pa naka-configure ang pagpapadala ng email. Please contact the office.';
    case 'invalid_api_key':
      return 'May problema sa email service (invalid API key). Please contact the office.';
    case 'sender_not_verified':
      return 'Hindi pa verified ang sender ng email sa Resend, kaya hindi ito makakarating sa ibang address. Please contact the office.';
    case 'recipient_rejected':
      return 'Tinanggihan ng email service ang address na ito. Please check it and try again.';
    case 'rate_limited':
      return 'Masyadong maraming email na hiniling. Please wait a minute and try again.';
    case 'timeout':
      return 'Nag-timeout ang email service. Please try again.';
    default:
      return 'Hindi naipadala ang verification email. Please check the address or try again.';
  }
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'send':
        return await handleSend(req);
      case 'confirm':
        return await handleConfirm(req);
      case 'confirm-json':
        return await handleConfirmJson(req);
      case 'status':
        return await handleStatus(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND', undefined, req);
    }
  } catch (err) {
    console.error('auth-email-verify error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR', undefined, req);
  }
});

// ── ?fn=send ────────────────────────────────────────────────────────────────
async function handleSend(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const rawEmail = sanitizeString((body as { email?: unknown }).email ?? '')
    .trim()
    .toLowerCase();

  // Kung walang ipinadalang email, gamitin ang nasa account na.
  const email = rawEmail || (user.email ?? '').trim().toLowerCase();
  if (!email || !validateEmail(email)) {
    return errorResponse('Enter a valid email address', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();

  // ── Cooldown ──────────────────────────────────────────────────────────
  // Ang bawat bagong link ay awtomatikong nagpapawalang-bisa sa nauna (DB
  // trigger), kaya ang isang link lang ang buhay sa isang pagkakataon. Dito
  // hinaharang ang sunod-sunod na pindot ng "Resend Email".
  const { data: recent } = await db
    .from('email_verifications')
    .select('created_at')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (recent?.created_at) {
    const elapsedSeconds =
      (Date.now() - new Date(recent.created_at as string).getTime()) / 1000;
    if (elapsedSeconds < RESEND_COOLDOWN_SECONDS) {
      const wait = Math.ceil(RESEND_COOLDOWN_SECONDS - elapsedSeconds);
      return errorResponse(
        `Please wait ${wait} second(s) before requesting another email.`,
        429,
        'RESEND_COOLDOWN',
        { retry_after_seconds: wait },
        req,
      );
    }
  }

  // ── Bagong one-time link ──────────────────────────────────────────────
  const token = generateResetToken();
  const tokenHash = await hashResetToken(token);
  const expiresAt = new Date(
    Date.now() + LINK_TTL_MINUTES * 60 * 1000,
  ).toISOString();

  const { error: insertErr } = await db.from('email_verifications').insert({
    user_id: user.id,
    email,
    token_hash: tokenHash,
    expires_at: expiresAt,
  });
  if (insertErr) {
    console.error('[email-verify] insert failed:', insertErr.message);
    return errorResponse(
      'We could not create the verification link. Please try again.',
      500,
      'INSERT_FAILED',
      undefined,
      req,
    );
  }

  // ── Ipadala via Resend ────────────────────────────────────────────────
  const verifyLink =
    `${verifyPageUrl()}?t=${encodeURIComponent(token)}`;

  const { data: profile } = await db
    .from('users')
    .select('first_name')
    .eq('id', user.id)
    .maybeSingle();
  const recipientName =
    typeof profile?.first_name === 'string' ? profile.first_name : undefined;

  const sendResult = await sendEmailVerificationEmail({
    to: email,
    verifyLink,
    recipientName,
    expiresInMinutes: LINK_TTL_MINUTES,
  });

  if (!sendResult.ok) {
    console.error(
      `[email-verify] Resend failed [${sendResult.kind ?? 'http_error'}] ` +
        `status=${sendResult.status ?? 'n/a'}:`,
      sendResult.error,
    );
    // Hindi tahimik na nilalamon ang pagkabigo: ang eksaktong dahilan (hal.
    // hindi pa verified ang sender domain sa Resend, kulang ang API key,
    // tinanggihan ang recipient) ang ipinapakita sa app — kung generic na
    // mensahe lang, hindi malalaman ng user/officer kung ano ang aayusin.
    return errorResponse(
      emailFailureMessage(sendResult),
      502,
      'EMAIL_SEND_FAILED',
      undefined,
      req,
    );
  }

  console.log(`[email-verify] verification link sent to ${email}`);
  return jsonResponse(
    {
      ok: true,
      sent_to: email,
      expires_at: expiresAt,
      resend_after_seconds: RESEND_COOLDOWN_SECONDS,
    },
    200,
    req,
  );
}

// ── Token confirmation — isang core para sa HTML AT JSON ────────────────────
//   ?fn=confirm       → HTML page (kapag direktang binuksan ang function URL)
//   ?fn=confirm-json  → JSON (para sa branded na /verify-email page ng web app)
interface ConfirmOutcome {
  ok: boolean;
  email?: string;
  title: string;
  message: string;
}

async function confirmToken(req: Request): Promise<ConfirmOutcome> {
  const token = new URL(req.url).searchParams.get('t');
  if (!isResetToken(token)) {
    return {
      ok: false,
      title: 'Invalid link',
      message:
        'This verification link is not valid. Please request a new one from the app.',
    };
  }

  const db = getAdminClient();
  const tokenHash = await hashResetToken(token);

  const { data: row, error } = await db
    .from('email_verifications')
    .select('id, user_id, email, expires_at, used_at')
    .eq('token_hash', tokenHash)
    .maybeSingle();

  if (error) {
    console.error('[email-verify] lookup failed:', error.message);
    return {
      ok: false,
      title: 'Something went wrong',
      message: 'We could not verify your email right now. Please try again.',
    };
  }

  if (!row) {
    return {
      ok: false,
      title: 'Link not found',
      message:
        'This verification link has already been used or replaced by a newer one. Request a new link from the app.',
    };
  }

  const expired = new Date(row.expires_at as string).getTime() < Date.now();

  if (row.used_at || expired) {
    // Na-tap/nagamit na, o lipas na — PERO kung verified na naman ang email ng
    // account, TAGUMPAY pa rin ang ipapakita.
    //
    // Mahalaga ito: maraming email provider at security scanner (hal. Gmail,
    // Outlook Safe Links) ang AWTOMATIKONG bumibisita sa link bago pa ito
    // pindutin ng user — "nagagamit" na ang isang-besang token bago pa man
    // makarating sa totoong tao. Kung magpapakita tayo ng error doon, akala ng
    // user ay may sira kahit verified na pala siya.
    if (await alreadyVerified(db, row.user_id, row.email)) {
      return {
        ok: true,
        email: row.email,
        title: 'Successfully Verified',
        message:
          `${row.email} is already verified. You can close this page and go back to the app.`,
      };
    }
    return {
      ok: false,
      title: expired ? 'Link expired' : 'Link already used',
      message: expired
        ? 'This verification link has expired. Tap "Resend Email" in the app to get a new one.'
        : 'This link was already used or replaced by a newer one. If your email is not verified yet, tap "Resend Email" in the app.',
    };
  }

  const nowIso = new Date().toISOString();

  const { error: usedErr } = await db
    .from('email_verifications')
    .update({ used_at: nowIso })
    .eq('id', row.id)
    .is('used_at', null);
  if (usedErr) {
    console.error('[email-verify] marking used failed:', usedErr.message);
  }

  // ── Isulat ang VERIFIED email sa account — hindi lang `email_verified_at` ──
  // ANG TOTOONG BUG NA NA-AYOS DITO: ang `email_verifications.email` lang ang
  // may hawak ng address na kinumpirma ng user. Ang `users.email` ay hindi
  // kailanman naisusulat dito, kaya kahit "Successfully Verified" ang link ay
  // NULL pa rin ang `users.email` sa database — "hindi nag-save ang email".
  //
  // Sunod-sunod na epekto nito:
  //   • `?fn=status` → `email: null` kahit verified na.
  //   • `alreadyVerified()` → LAGING false (NULL ≠ typed email) kaya ang
  //     muling pag-tap sa link (o ang auto-visit ng Gmail/Outlook scanner) ay
  //     nagsasabing "Link already used" kahit matagumpay ang verification.
  //   • Ang app pa lang ang nagsusulat ng `users.email` (update-profile), at
  //     kapag nabigo iyon (409 DUPLICATE / GoTrue sync) ay walang nag-a-ayos —
  //     ang link na "verified" na ang nasa email ng user.
  //
  // Sa confirm na ito isinusulat ang verified address kasabay ng verification
  // stamp, dahil ang server na ito ang may hawak ng PINAKA-tunay na pinagmulan
  // (ang link na pinindot sa email). Kapag may IBANG account nang gumagamit ng
  // address na ito (`uq_users_email_lower` → 23505), hindi natin aagawin ito:
  // ita-timestamp pa rin ang verification at malinaw na ipapaliwanag sa user.
  const { error: userErr } = await db
    .from('users')
    .update({ email: row.email, email_verified_at: nowIso })
    .eq('id', row.user_id);
  if (userErr) {
    const code = (userErr as unknown as { code?: string }).code ?? '';
    const duplicate = code === '23505';
    console.error(
      '[email-verify] users.email save failed:',
      userErr.message,
      { user_id: row.user_id, duplicate },
    );
    // Hindi ko na iisahan ang duplicate: kailangang i-stamp pa rin ang
    // verification (verified naman talaga ang link na pinindot).
    const { error: stampErr } = await db
      .from('users')
      .update({ email_verified_at: nowIso })
      .eq('id', row.user_id);
    if (stampErr) {
      console.error('[email-verify] email_verified_at update failed:', stampErr.message);
      return {
        ok: false,
        title: 'Something went wrong',
        message: 'We could not save your verification. Please try again.',
      };
    }
    return duplicate
      ? {
          ok: false,
          title: 'Email already in use',
          message:
            `${row.email} is already registered to another account. Please use a different email address in the app.`,
        }
      : {
          ok: false,
          title: 'Something went wrong',
          message: 'We could not save your verification. Please try again.',
        };
  }

  console.log(`[email-verify] email verified for user=${row.user_id}`);
  return {
    ok: true,
    email: row.email,
    title: 'Successfully Verified',
    message:
      `Thank you! ${row.email} is now verified. You can close this page and go back to the app.`,
  };
}

// ── ?fn=confirm — HTML page (direktang pagbukas sa function URL) ─────────────
async function handleConfirm(req: Request) {
  const outcome = await confirmToken(req);
  return verifyPage(req, outcome.ok, outcome.title, outcome.message);
}

// ── ?fn=confirm-json — para sa branded na /verify-email page ng web app ──────
async function handleConfirmJson(req: Request) {
  const outcome = await confirmToken(req);
  if (!outcome.ok) {
    return errorResponse(
      outcome.message,
      400,
      'VERIFY_FAILED',
      undefined,
      req,
    );
  }
  return jsonResponse(
    { ok: true, email: outcome.email ?? null },
    200,
    req,
  );
}

/**
 * Verified na ba ang email ng account? Idempotent ang confirm kapag oo na —
 * hindi na ito nagbibigay ng error sa paulit-ulit na pag-tap sa link.
 */
async function alreadyVerified(
  db: ReturnType<typeof getAdminClient>,
  userId: string,
  email: string,
): Promise<boolean> {
  try {
    const { data } = await db
      .from('users')
      .select('email, email_verified_at')
      .eq('id', userId)
      .maybeSingle();
    if (!data?.email_verified_at) return false;
    // Ang `email_verified_at` mismo ang senyales ng verification. Ang dating
    // paghahambing sa `users.email` ay LAGING false kapag NULL ang email ng
    // account (bagong lender) — kaya ang paulit-ulit na pag-tap sa link ay
    // nagpapakitang "Link already used" kahit matagumpay ang verification.
    // Kapag may naka-save na email, dito lang natin hinihingi ang tugma.
    const stored = String(data.email ?? '').trim().toLowerCase();
    return stored === '' || stored === email.trim().toLowerCase();
  } catch (e) {
    console.error('[email-verify] alreadyVerified check failed:', e);
    return false;
  }
}

// ── ?fn=status ──────────────────────────────────────────────────────────────
async function handleStatus(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const db = getAdminClient();
  const { data, error } = await db
    .from('users')
    .select('email, email_verified_at')
    .eq('id', user.id)
    .maybeSingle();

  if (error) {
    console.error('[email-verify] status failed:', error.message);
    return errorResponse(
      'Could not check the verification status.',
      500,
      'LOOKUP_FAILED',
      undefined,
      req,
    );
  }

  return jsonResponse(
    {
      verified: !!data?.email_verified_at,
      email: data?.email ?? null,
      verified_at: data?.email_verified_at ?? null,
    },
    200,
    req,
  );
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ── Ang HTML page na nakikita sa browser pagkatapos i-tap ang link ──────────
function verifyPage(
  req: Request,
  ok: boolean,
  title: string,
  message: string,
): Response {
  const accent = ok ? '#16a34a' : '#dc2626';
  // Ang `message` ay may email address na galing sa database — i-escape para
  // hindi maging HTML injection vector ang confirm page.
  const safeTitle = escapeHtml(title);
  const safeMessage = escapeHtml(message);
  const body = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>${safeTitle} — Jireta Loans</title>
</head>
<body style="margin:0;padding:0;background-color:#f3f4f6;font-family:Inter,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f3f4f6;padding:32px 16px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background:#ffffff;border-radius:16px;border:1px solid #e5e7eb;overflow:hidden;">
        <tr>
          <td style="background:#0f1f3c;padding:22px 24px;text-align:center;">
            <div style="font-family:Playfair Display,serif;font-size:19px;font-weight:700;color:#d4a017;letter-spacing:0.5px;">JIRETA LOANS</div>
            <div style="font-size:11px;color:#ffffff99;letter-spacing:1.2px;text-transform:uppercase;margin-top:4px;">Credit Corp 1966</div>
          </td>
        </tr>
        <tr>
          <td style="padding:28px 24px;text-align:center;">
            <div style="width:56px;height:56px;line-height:56px;margin:0 auto 16px;border-radius:50%;background:${accent};color:#ffffff;font-size:28px;">${ok ? '&#10003;' : '!'}</div>
            <h2 style="margin:0 0 10px;font-size:18px;font-weight:700;color:#0f1f3c;">${safeTitle}</h2>
            <p style="margin:0;font-size:14px;line-height:1.6;color:#374151;">${safeMessage}</p>
          </td>
        </tr>
        <tr>
          <td style="background:#f9fafb;padding:14px 24px;text-align:center;border-top:1px solid #e5e7eb;">
            <p style="margin:0;font-size:11px;color:#9ca3af;">&copy; ${new Date().getFullYear()} Jireta Loans &amp; Credit Corp. All rights reserved.</p>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

  return new Response(body, {
    status: ok ? 200 : 400,
    headers: {
      ...corsHeadersFor(req),
      'Content-Type': 'text/html; charset=utf-8',
    },
  });
}
