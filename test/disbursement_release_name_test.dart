// test/disbursement_release_name_test.dart
//
// BUSINESS RULE: ang "Disbursed By" sa Office Cash Release section ng
// Disbursement Details ay dapat PANGALAN ng nag-release, hindi UUID.
//
// Dati: `disbursements.authorized_by` ay UUID FK sa `users`, at ang
// `disbursements-view?fn=get-list` ay `disbursed_by:authorized_by` lang ang
// ipinapadala — kaya hilaw na UUID (hal.
// `273e7d09-248b-41e9-a9c8-7766ce468e27`) ang lumalabas sa dialog.
//
// Ngayon: nagjo-join na ang function sa `users!disbursements_authorized_by_fkey`
// at nagpapadala ng `disbursed_by_name`; ang UI ay `disbursedByLabel` ang
// ginagamit (name → legacy name → 'N/A', hindi kailanman UUID).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/disbursement_model.dart';

const _uuid = '273e7d09-248b-41e9-a9c8-7766ce468e27';

Map<String, dynamic> _json(Map<String, dynamic> extra) => {
      'id': 'd1',
      'loan_id': 'l1',
      'method': 'office_cash',
      'amount': 10000.0,
      'status': 'completed',
      'created_at': '2026-09-17T06:35:00Z',
      ...extra,
    };

void main() {
  group('Disbursed By label (Office Cash Release)', () {
    test('ginagamit ang disbursed_by_name mula sa users join', () {
      final d = DisbursementModel.fromJson(_json({
        'disbursed_by': _uuid,
        'disbursed_by_name': 'Kyl F Dis',
      }));
      expect(d.disbursedByLabel, 'Kyl F Dis');
    });

    test('hindi ipinapakita ang hilaw na UUID kapag wala ang name join', () {
      // Lumang response (bago i-deploy ang join) — UUID lang ang meron.
      final d = DisbursementModel.fromJson(_json({'disbursed_by': _uuid}));
      expect(d.disbursedByLabel, 'N/A');
      expect(d.disbursedByLabel.contains(_uuid), isFalse);
    });

    test('legacy row na pangalan ang nakaimbak: ipinapakita pa rin', () {
      final d = DisbursementModel.fromJson(_json({'disbursed_by': 'Office Staff'}));
      expect(d.disbursedByLabel, 'Office Staff');
    });

    test('walang laman: N/A', () {
      final d = DisbursementModel.fromJson(_json({}));
      expect(d.disbursedByLabel, 'N/A');
    });

    test('blangkong pangalan sa join: bumabalik sa N/A, hindi sa UUID', () {
      final d = DisbursementModel.fromJson(
          _json({'disbursed_by': _uuid, 'disbursed_by_name': '   '}));
      expect(d.disbursedByLabel, 'N/A');
    });
  });

  group('Source guards', () {
    test('disbursements-view ay nagjo-join sa users para sa authorized_by', () {
      final src =
          File('supabase/functions/disbursements-view/index.ts').readAsStringSync();
      expect(src.contains('disbursements_authorized_by_fkey'), isTrue,
          reason: 'kailangan ng users join para sa pangalan ng nag-release');
      expect(src.contains('disbursed_by_name'), isTrue,
          reason: 'dapat ipadala ang pangalan sa response');
    });

    test('details screen ay disbursedByLabel ang ginagamit (hindi disbursedBy)',
        () {
      final src = File(
              'lib/presentation/features/head_manager/disbursements/screens/hm_disbursement_details_screen.dart')
          .readAsStringSync();
      expect(src.contains("_row('Disbursed By', d.disbursedByLabel)"), isTrue);
      expect(src.contains("d.disbursedBy ??"), isFalse,
          reason: 'huwag nang ibalik ang hilaw na UUID sa UI');
    });
  });
}
