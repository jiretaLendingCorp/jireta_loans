// supabase/functions/_shared/loan_status_after_payment.test.ts
//
// Dati, nananatiling `overdue` ang loan kahit bayad na ang lumampas nang
// installment — kaya nakikita pa rin ng Head Manager at Employee na "Overdue"
// sa Loan Records ang loan na bayad na ng lender. Ang mga test na ito ang
// nagpi-pin ng tamang desisyon:
//   * bayad na ang overdue → `active` (o `completed` kapag ubos ang balanse),
//   * may overdue pang installment → `overdue`,
//   * hindi ginagalaw ang ibang status (pending/approved/completed/…).
import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isLatePaymentDate,
  isOverdueInstallment,
  latestLatePaymentByLoan,
  statusAfterPayment,
} from "./loan_financials.ts";

// ── statusAfterPayment ──────────────────────────────────────────────────────

Deno.test("bayad na ang overdue → active", () => {
  assertEquals(
    statusAfterPayment({ currentStatus: "overdue", outstanding: 5600, hasOverdue: false }),
    "active",
  );
});

Deno.test("may overdue pang installment → overdue pa rin", () => {
  assertEquals(
    statusAfterPayment({ currentStatus: "overdue", outstanding: 5600, hasOverdue: true }),
    "overdue",
  );
});

Deno.test("ubos na ang balanse → completed (kahit may overdue record pa)", () => {
  assertEquals(
    statusAfterPayment({ currentStatus: "overdue", outstanding: 0, hasOverdue: true }),
    "completed",
  );
  assertEquals(
    statusAfterPayment({ currentStatus: "active", outstanding: 0, hasOverdue: false }),
    "completed",
  );
});

Deno.test("hindi ginagalaw ang mga loan na wala pang bayad / sarado na", () => {
  for (const status of ["pending", "approved", "rejected", "completed", "cancelled"]) {
    assertEquals(
      statusAfterPayment({ currentStatus: status, outstanding: 1000, hasOverdue: true }),
      null,
    );
  }
});

Deno.test("active loan na may overdue schedule → overdue", () => {
  assertEquals(
    statusAfterPayment({ currentStatus: "active", outstanding: 1000, hasOverdue: true }),
    "overdue",
  );
});

Deno.test("normalisado ang status casing at whitespace", () => {
  assertEquals(
    statusAfterPayment({ currentStatus: " Overdue ", outstanding: 1000, hasOverdue: false }),
    "active",
  );
});

// ── isOverdueInstallment ────────────────────────────────────────────────────

const TODAY = "2026-09-27";

Deno.test("lampas na ang due date at may natitira → overdue", () => {
  assertEquals(
    isOverdueInstallment({ amount_due: "1200.00", amount_paid: "0", due_date: "2026-09-20" }, TODAY),
    true,
  );
});

Deno.test("bayad na ang installment kahit lampas ang due date → hindi overdue", () => {
  assertEquals(
    isOverdueInstallment({ amount_due: 1200, amount_paid: 1200, due_date: "2026-09-20" }, TODAY),
    false,
  );
});

Deno.test("bahagyang bayad pa → overdue pa rin", () => {
  assertEquals(
    isOverdueInstallment({ amount_due: 1200, amount_paid: 500, due_date: "2026-09-20" }, TODAY),
    true,
  );
});

Deno.test("hindi pa dumarating ang due date → hindi overdue", () => {
  assertEquals(
    isOverdueInstallment({ amount_due: 1200, amount_paid: 0, due_date: "2026-10-20" }, TODAY),
    false,
  );
  assertEquals(
    isOverdueInstallment({ amount_due: 1200, amount_paid: 0, due_date: TODAY }, TODAY),
    false,
  );
});

Deno.test("timestamptz na due_date ay inihahambing sa petsa lang", () => {
  assertEquals(
    isOverdueInstallment(
      { amount_due: 1200, amount_paid: 0, due_date: "2026-09-20T00:00:00+08:00" },
      TODAY,
    ),
    true,
  );
});

// ── latestLatePaymentByLoan (“Overdue paid” tag) ───────────────────────────

Deno.test("bayad na ang overdue: may late payment date ang loan", () => {
  const map = latestLatePaymentByLoan([
    { loan_id: "loan-1", due_date: "2026-09-20", paid_at: "2026-09-27T13:32:00+00:00" },
  ]);
  assertEquals(map["loan-1"], "2026-09-27T13:32:00+00:00");
});

Deno.test("on-time na bayad (o mas maaga) ay hindi “overdue paid”", () => {
  const map = latestLatePaymentByLoan([
    { loan_id: "loan-1", due_date: "2026-09-20", paid_at: "2026-09-20T01:00:00+00:00" },
    { loan_id: "loan-2", due_date: "2026-09-20", paid_at: "2026-09-18T01:00:00+00:00" },
  ]);
  assertEquals(map["loan-1"], undefined);
  assertEquals(map["loan-2"], undefined);
});

Deno.test("Manila date ang gamit: 7 AM Manila sa due date ay on time pa", () => {
  // 2026-09-19 23:00 UTC = 2026-09-20 07:00 Manila — same day, on time.
  const map = latestLatePaymentByLoan([
    { loan_id: "loan-1", due_date: "2026-09-20", paid_at: "2026-09-19T23:00:00+00:00" },
  ]);
  assertEquals(map["loan-1"], undefined);
});

Deno.test("isLatePaymentDate: bayad pagkalampas ng due date → overdue payment", () => {
  assertEquals(isLatePaymentDate("2026-09-27T13:32:00+00:00", "2026-09-26"), true);
  assertEquals(isLatePaymentDate("2026-09-26T01:00:00+00:00", "2026-09-26"), false);
  // 7 AM Manila sa due date = 23:00 UTC ng nakaraang araw — on time pa rin.
  assertEquals(isLatePaymentDate("2026-09-25T23:00:00+00:00", "2026-09-26"), false);
  assertEquals(isLatePaymentDate(null, "2026-09-26"), false);
  assertEquals(isLatePaymentDate("2026-09-27T13:32:00+00:00", null), false);
});

Deno.test("pinakahuling late payment ang itinatago kada loan", () => {
  const map = latestLatePaymentByLoan([
    { loan_id: "loan-1", due_date: "2026-08-20", paid_at: "2026-08-25T02:00:00+00:00" },
    { loan_id: "loan-1", due_date: "2026-09-20", paid_at: "2026-09-27T02:00:00+00:00" },
    { loan_id: "loan-2", due_date: "2026-09-20", paid_at: null },
  ]);
  assertEquals(map["loan-1"], "2026-09-27T02:00:00+00:00");
  assertEquals(map["loan-2"], undefined);
});
