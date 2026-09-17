// test/office_cash_release_status_test.dart
//
// BUG: ang Office Cash release ay PENDING pa rin sa Disbursements tab kahit
// ACTIVE na ang loan at natanggap na ng lender ang cash.
//
// ROOT CAUSE: ang `disbursements.status_id` ay may DEFAULT = uuid ng 'pending'
// (00110 §9 "Defaults for new uuid columns"). Ang BEFORE INSERT/UPDATE trigger
// `sync_disbursements_lookup_ids` (00111) ay ganito ang unang branch:
//
//   IF NEW.status_id IS DISTINCT FROM OLD.status_id THEN
//     SELECT code INTO NEW.status FROM disbursement_statuses
//      WHERE id = NEW.status_id;
//
// Sa INSERT, `OLD.status_id` = NULL at `NEW.status_id` = DEFAULT ('pending'
// uuid) → DISTINCT → kaya ang `status: 'completed'` na ipinapadala ng
// `disbursements-delivery?fn=office-cash` ay na-o-overwrite pabalik sa
// 'pending'. Hindi naapektuhan ang `method` (walang default ang `method_id`),
// kaya "Office Cash" ang Method pero "Pending" ang Status.
//
// FIX: `status_id: null` sa INSERT → ang ELSE branch (code → id) ang tatakbo,
// kaya ang status code ang nananaig. Kapareho ng naunang fix sa `payments`
// (payments-manage) at `collection_assignments` (collections-manage).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

/// [start] pataas — ang snippet ng insert block sa paligid ng marker.
String slice(String src, String start, {int length = 900}) {
  final i = src.indexOf(start);
  if (i < 0) return '';
  final end = i + length > src.length ? src.length : i + length;
  return src.substring(i, end);
}

/// Mirror ng status branch ng `sync_disbursements_lookup_ids` (00111).
/// Ang `statusId` ay `null` kapag hindi ito ipinasa (→ DEFAULT ng column).
({String? status, String? statusId}) syncStatus({
  required String? status,
  required String? statusId,
  required String? oldStatus,
  required String? oldStatusId,
}) {
  const pendingId = 'uuid-pending';
  const completedId = 'uuid-completed';
  String codeOf(String id) =>
      id == completedId ? 'completed' : (id == pendingId ? 'pending' : '');

  if (statusId != oldStatusId) {
    // IF NEW.status_id IS DISTINCT FROM OLD.status_id
    return (status: codeOf(statusId!), statusId: statusId);
  } else if (status != oldStatus) {
    // ELSIF NEW.status IS DISTINCT FROM OLD.status
    final id = status == 'completed' ? completedId : pendingId;
    return (status: status, statusId: id);
  }
  return (status: status, statusId: statusId);
}

void main() {
  group('Status sync — kopya ng trigger behavior', () {
    test('BUG: INSERT na walang status_id → DEFAULT pending ang nananaig', () {
      // status: 'completed' ang ipinasa, pero hindi ipinasa ang status_id,
      // kaya ang DEFAULT na 'pending' uuid ang gagamitin ng column.
      final r = syncStatus(
        status: 'completed',
        statusId: 'uuid-pending', // DEFAULT ng column sa INSERT
        oldStatus: null,
        oldStatusId: null,
      );
      expect(r.status, 'pending'); // ⬅ ito ang reported bug
    });

    test('FIX: `status_id: null` sa INSERT → completed ang nananaig', () {
      final r = syncStatus(
        status: 'completed',
        statusId: null, // ipinasang NULL
        oldStatus: null,
        oldStatusId: null,
      );
      expect(r.status, 'completed');
      expect(r.statusId, 'uuid-completed');
    });

    test('UPDATE ay safe — status lang ang binago (rider proof upload)', () {
      final r = syncStatus(
        status: 'completed',
        statusId: 'uuid-pending', // walang binago sa status_id
        oldStatus: 'pending',
        oldStatusId: 'uuid-pending',
      );
      expect(r.status, 'completed');
      expect(r.statusId, 'uuid-completed');
    });

    test('HINDI dapat ipasa ang status_id: null SA UPDATE', () {
      // Kung ipinasa ito sa UPDATE: NULL vs 'uuid-pending' → distinct →
      // ang codeOf(NULL) ay walang laman → mababago ang status (at
      // mababagsak ng NOT NULL ang update). Kaya INSERT lang ang binago.
      final src = readNormalized('supabase/functions/disbursements-delivery/index.ts');
      final proofUpdate = slice(src, 'async function handleUploadProof');
      expect(proofUpdate, isNot(contains('status_id: null')));
    });
  });

  group('Backend wiring — naka-set ang status_id: null sa bawat INSERT', () {
    test('office cash release ay may status_id: null', () {
      final src = readNormalized(
          'supabase/functions/disbursements-delivery/index.ts');
      final officeCash = slice(src, "method: 'office_cash'");
      expect(officeCash, contains("status: 'completed'"));
      expect(officeCash, contains('status_id: null'));
    });

    test('rider delivery assignment ay may status_id: null', () {
      final src = readNormalized(
          'supabase/functions/disbursements-delivery/index.ts');
      final riderDelivery = slice(src, "method: 'rider_delivery'");
      expect(riderDelivery, contains("status: 'pending'"));
      expect(riderDelivery, contains('status_id: null'));
    });

    test('gcash insert (disbursements-select) ay may status_id: null', () {
      final src =
          readNormalized('supabase/functions/disbursements-select/index.ts');
      final gcash = slice(src, "method: 'gcash'");
      expect(gcash, contains('status_id: null'));
    });

    test('pareho ang pattern sa payments (naunang fix)', () {
      final src = readNormalized('supabase/functions/payments-manage/index.ts');
      expect(src, contains('status_id: null'));
    });
  });

  group('Migration 00166 — data repair + defense', () {
    final src =
        readNormalized('supabase/migrations/00166_office_cash_release_status.sql');

    test('inaayos ang pending office_cash ng released na loan', () {
      expect(src, contains('UPDATE public.disbursements'));
      expect(src, contains("d.method = 'office_cash'"));
      expect(src, contains("d.status = 'pending'"));
      expect(src, contains("l.status IN ('active', 'overdue', 'completed')"));
      // Hindi ginalaw ang status_id — ang trigger ang mag-sync nito mula sa
      // bagong status code.
      expect(src, contains("SET status = 'completed'"));
      expect(src, isNot(contains('SET status_id')));
    });

    test('trigger na nagko-complete sa pending office_cash kapag released', () {
      expect(src, contains('complete_office_cash_on_loan_release'));
      expect(src, contains('trg_office_cash_release_sync'));
      expect(src, contains('AFTER UPDATE OF status ON public.loans'));
    });
  });
}
