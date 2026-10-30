// test/features/lender/notifications/payment_due_reminder_backend_contract_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS RULE: 2 araw bago ang due date ng installment (base sa loan term
// na kinuha ng lender), dapat may reminder ang lender:
//   • FCM push + in-app notification (notifications row → 00126 trigger), at
//   • TextBee SMS (sms-send?fn=send-reminder),
// at dapat nakasaad ang NATITIRANG BALANSE — hindi lang ang installment.
//
// Nangyari na kasing tahimik na nabigo ang TextBee query dahil ang `loans`
// embed ay walang `!inner`: kapag left-joined ang to-one embed, tinatanggihan
// ng PostgREST ang filter sa `loan.status` at walang SMS na lumalabas.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('migration 00193 — 2-day due reminder', () {
    late String sql;
    setUpAll(() {
      sql = _squash(_read(
        'supabase/migrations/00193_payment_due_reminder_remaining_balance.sql',
      ));
    });

    test('N araw bago ang due date (default 2)', () {
      expect(sql, contains('public.send_payment_due_reminders()'));
      expect(sql, contains("config_key = 'payment_reminder_days'"));
      expect(sql, contains('s.due_date = (now_manila())::date + v_days'));
    });

    test('in-app + FCM: notification insert ay pinapasa sa push trigger', () {
      final insertStart = sql.indexOf('INSERT INTO notifications');
      expect(insertStart, greaterThanOrEqualTo(0));
      expect(sql, contains("'payment_due'"));

      // Huwag i-claim ang fcm_sent sa INSERT — ang
      // trg_notification_enqueue_push (00126) ang nag-e-enqueue ng device push.
      final insertBlock = sql.substring(
        insertStart,
        sql.indexOf("'payment_due'", insertStart),
      );
      expect(insertBlock, isNot(contains('fcm_sent')));
    });

    test('ang reminder ay may natitirang balanse, hindi lang installment', () {
      expect(sql, contains('public.loan_outstanding_balance(v_target.loan_id)'));
      expect(sql, contains('Your remaining balance is'));
      // Net amount: amount_due - verified payments (partial payment aware).
      expect(
        sql,
        contains('v_target.amount_due - COALESCE(v_target.amount_paid, 0)'),
      );
    });

    test('TextBee SMS batch ay ini-enqueue', () {
      expect(sql, contains("config_key = 'sms_reminder_function_url'"));
      expect(sql, contains("'?fn=send-reminder'"));
      expect(sql, contains("'x-push-secret'"));
    });

    test('idempotent per schedule at naka-cron araw-araw', () {
      expect(sql, contains("n.type = 'payment_due'"));
      expect(sql, contains('n.reference_id = s.id'));
      expect(sql, contains("'send_payment_due_reminders_daily'"));
      expect(sql, contains("SELECT public.send_payment_due_reminders()"));
    });
  });

  group('sms-send?fn=send-reminder — TextBee delivery', () {
    late String src;
    setUpAll(() {
      src = _squash(_read('supabase/functions/sms-send/index.ts'));
    });

    test('may !inner ang loan embed para gumana ang status filter', () {
      // Ang trigger ng PostgREST: filter sa embedded column ay kailangang
      // inner join, kung hindi 400 ang buong query at walang SMS.
      expect(src, contains('loans!loan_schedules_loan_id_fkey!inner('));
      expect(src, contains(".in('loan.status', ['active', 'overdue'])"));
    });

    test('TextBee lang ang provider at may schedule link sa log', () {
      expect(src, contains('sendSms('));
      expect(src, contains('loanScheduleId: schedule.id'));
    });

    test('net installment at remaining balance ang ipinapadala', () {
      expect(src, contains('getLoanFinancials'));
      expect(src, contains('outstanding_balance'));
      expect(
        src,
        contains('Number(schedule.amount_due) - schedulePayment.amount_paid'),
      );
      expect(src, contains('Your remaining balance is'));
    });

    test('FCM backup: unclaimed reminder ay ini-claim at ipinupush', () {
      // Walang retry ang pg_net trigger, kaya kapag pumalya iyon ay dito
      // naipapasa ang push — at most once pa rin dahil sa atomic claim.
      expect(src, contains('claimAndSendPush'));
      expect(src, contains("select('id, fcm_sent')"));
      expect(src, contains('if (!existing.fcm_sent)'));
    });
  });
}
