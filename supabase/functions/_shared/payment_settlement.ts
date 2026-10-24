// supabase/functions/_shared/payment_settlement.ts
// ─────────────────────────────────────────────────────────────────────────────
// IISANG LUGAR para sa "bayad na sa Xendit → verified na sa app".
//
// Ang `payments.status` lang ang binibilang ng loan balance
// (`_shared/loan_financials.ts` → `getSchedulePayment`), kaya ang pag-flip ng
// `pending` → `verified` ang tanging paraan para bumaba ang utang ng lender.
//
// Dating nasa loob lang ito ng `payments-xendit-webhook`. Ngayon ay shared na
// ito para pareho ang nangyayari sa dalawang pinagmumulan:
//   • `payments-xendit-webhook` — Xendit callback (`status: PAID`).
//   • `payments-xendit-link?fn=sync-payment` — reconciliation kapag hindi
//     umabot ang callback (hindi naka-configure ang webhook URL ng Xendit
//     sandbox, maling `XENDIT_WEBHOOK_TOKEN`, o na-drop na delivery). Ito ang
//     dahilan ng "successfully paid na pero Pending pa rin": ang bayad sa
//     `payments` ay hindi na-update dahil walang callback na dumating.
// ─────────────────────────────────────────────────────────────────────────────
import { getAdminClient } from './db.ts';
import { writeAuditLog } from './audit.ts';
import { sendPushNotification } from './notifications.ts';
import {
  getLoanFinancials,
  getPaymentLoanId,
  round2,
  syncLoanStatusAfterPayment,
} from './loan_financials.ts';

type DbClient = ReturnType<typeof getAdminClient>;

export interface SettlePaidPaymentParams {
  paymentId: string;
  /** Ang Xendit invoice/payment id — para sa audit at logs. */
  xenditId: string;
  /** Ang halagang aktwal na binayad ayon sa Xendit (hindi sa client). */
  amount: number;
  /** Saan galing ang kumpirmasyon — audit/log label lang. */
  source: 'webhook' | 'sync';
}

export interface SettlePaidPaymentResult {
  /** `false` kapag may mismatch o wala ang payment — HINDI ito na-verify. */
  ok: boolean;
  /** `true` kapag verified na ito bago pa man tawagin (idempotent). */
  alreadyVerified: boolean;
  /** Ang amount_due ng installment na dapat bayaran. */
  expectedAmount: number | null;
  paidAmount: number;
  /** Bagong outstanding balance (kapag may loan). */
  newBalance: number | null;
}

/**
 * I-verify ang Xendit payment at i-update ang loan.
 *
 * MAHALAGA: sinusuri muna ang halaga laban sa `loan_schedules.amount_due`.
 * Ang callback/replay na may maling amount ay HINDI dapat magpababa ng utang,
 * kaya `ok: false` at walang isinusulat sa `payments`.
 */
export async function settlePaidXenditPayment(
  db: DbClient,
  params: SettlePaidPaymentParams,
): Promise<SettlePaidPaymentResult> {
  const paidAmount = Number(params.amount ?? 0);
  const { data: payment } = await db
    .from('payments')
    .select('id, loan_schedule_id, collection_assignment_id, status')
    .eq('id', params.paymentId)
    .single();

  if (!payment) {
    return {
      ok: false,
      alreadyVerified: false,
      expectedAmount: null,
      paidAmount,
      newBalance: null,
    };
  }
  if (payment.status === 'verified') {
    return {
      ok: true,
      alreadyVerified: true,
      expectedAmount: null,
      paidAmount,
      newBalance: null,
    };
  }

  let expectedAmount: number | null = null;
  if (payment.loan_schedule_id) {
    const { data: schedule } = await db
      .from('loan_schedules')
      .select('amount_due')
      .eq('id', payment.loan_schedule_id)
      .single();
    expectedAmount = schedule ? Number(schedule.amount_due) : null;
  }
  const amountOk =
    expectedAmount !== null && round2(paidAmount) === round2(expectedAmount);
  if (!amountOk) {
    return {
      ok: false,
      alreadyVerified: false,
      expectedAmount,
      paidAmount,
      newBalance: null,
    };
  }

  await db
    .from('payments')
    .update({ status: 'verified', paid_at: new Date().toISOString() })
    .eq('id', payment.id);

  const loanId = await getPaymentLoanId(db, payment);
  let newBalance: number | null = null;
  if (loanId) {
    const { data: loan } = await db
      .from('loans')
      .select('id, lender_id, status')
      .eq('id', loanId)
      .single();
    const financials = await getLoanFinancials(db, loanId);
    newBalance = Math.max(0, financials?.outstanding_balance ?? 0);
    // Fully paid → `completed`; bayad na ang overdue pero may natitira pang
    // future installments → bumalik sa `active` (hindi na Overdue sa HM/Employee).
    await syncLoanStatusAfterPayment(db, loanId);
    if (loan?.lender_id) {
      await writeAuditLog(
        {
          performedBy: 'system',
          action: params.source === 'webhook'
            ? 'xendit_payment_verified'
            : 'xendit_payment_synced',
          tableName: 'payments',
          recordId: payment.id,
          newValues: {
            amount: paidAmount,
            xendit_id: params.xenditId,
            source: params.source,
          },
        },
        db,
      );
      await sendPushNotification({
        userId: loan.lender_id,
        title: 'GCash Payment Confirmed',
        body: `Payment of ₱${paidAmount.toLocaleString()} confirmed. Remaining balance: ₱${newBalance.toLocaleString()}`,
        type: 'payment_verified',
        referenceId: payment.id,
      });
    }
  }

  return {
    ok: true,
    alreadyVerified: false,
    expectedAmount,
    paidAmount,
    newBalance,
  };
}
