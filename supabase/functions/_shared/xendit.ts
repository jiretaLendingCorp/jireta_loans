// supabase/functions/_shared/xendit.ts
const XENDIT_BASE = 'https://api.xendit.co';

function getXenditHeaders(): HeadersInit {
  const secretKey = Deno.env.get('XENDIT_SECRET_KEY')!;
  const encoded = btoa(`${secretKey}:`);
  return {
    Authorization: `Basic ${encoded}`,
    'Content-Type': 'application/json',
  };
}

export async function createInvoice(params: {
  externalId: string;
  amount: number;
  payerEmail?: string;
  description: string;
  successRedirectUrl?: string;
}): Promise<{ invoiceUrl: string; id: string; status: string }> {
  const res = await fetch(`${XENDIT_BASE}/v2/invoices`, {
    method: 'POST',
    headers: getXenditHeaders(),
    body: JSON.stringify({
      external_id: params.externalId,
      amount: params.amount,
      payer_email: params.payerEmail,
      description: params.description,
      success_redirect_url: params.successRedirectUrl,
      currency: 'PHP',
      payment_methods: ['GCASH'],
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(`Xendit invoice error: ${JSON.stringify(err)}`);
  }

  const data = await res.json();
  return { invoiceUrl: data.invoice_url, id: data.id, status: data.status };
}

export async function createDisbursement(params: {
  externalId: string;
  bankCode: string;
  accountHolderName: string;
  accountNumber: string;
  amount: number;
  description: string;
}): Promise<{ id: string; status: string }> {
  const res = await fetch(`${XENDIT_BASE}/disbursements`, {
    method: 'POST',
    headers: getXenditHeaders(),
    body: JSON.stringify({
      external_id: params.externalId,
      bank_code: params.bankCode,
      account_holder_name: params.accountHolderName,
      account_number: params.accountNumber,
      amount: params.amount,
      description: params.description,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(`Xendit disbursement error: ${JSON.stringify(err)}`);
  }

  const data = await res.json();
  return { id: data.id, status: data.status };
}

export function verifyWebhookToken(req: Request): boolean {
  const callbackToken = req.headers.get('x-callback-token');
  const expectedToken = Deno.env.get('XENDIT_WEBHOOK_TOKEN');
  if (!expectedToken || !callbackToken) return false;
  return callbackToken === expectedToken;
}