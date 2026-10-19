// test/loan_limits_config_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Guards para sa config-driven loan limits:
//   • `LoanSettings` parsing + safe fallback sa ₱3,000 / ₱500,000 / 20%.
//   • Naka-wire ang lender Apply Loan at In-Office Step 3 sa
//     `loanSettingsProvider` (hindi na hardcoded ang labels/validation).
//   • `autoDispose` ang provider → sariwa ang value tuwing bubuksan ang form
//     (kapag nag-save ng config ang Head Manager, makikita agad).
//   • Backend (`loans-apply`, `loans-view`, `in-office-view`) ay `getLoanLimits`
//     ang ine-enforce, at may `get-loan-settings` action para sa app.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/loan_settings.dart';

String _read(String path) => File(path).readAsStringSync();

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('LoanSettings', () {
    test('binabasa ang min/max/interest mula sa settings payload', () {
      final settings = LoanSettings.fromJson({
        'min_amount': 3500,
        'max_amount': 600000,
        'interest_rate': 25,
      });
      expect(settings.minAmount, 3500);
      expect(settings.maxAmount, 600000);
      expect(settings.interestRate, 25);
    });

    test('fallback sa 3,000/500,000/20 kapag kulang o sira', () {
      for (final json in <Map<String, dynamic>>[
        {},
        {'min_amount': 'abc', 'max_amount': 500000},
        {'min_amount': 700000, 'max_amount': 500000},
        {'min_amount': 3000, 'max_amount': 0},
      ]) {
        final settings = LoanSettings.fromJson(json);
        expect(settings.minAmount, 3000, reason: '$json');
        expect(settings.maxAmount, 500000, reason: '$json');
        expect(settings.interestRate, 20, reason: '$json');
      }
    });

    test('compact na piso label ang gamit sa UI', () {
      const settings =
          LoanSettings(minAmount: 3500, maxAmount: 500000, interestRate: 20);
      expect(settings.minLabel, '₱3,500');
      expect(settings.maxLabel, '₱500,000');
    });
  });

  group('Source guards: naka-wire ang settings sa applications', () {
    test('Lender Apply Loan: provider ang gamit, walang hardcoded ₱3,000', () {
      final src = _read(
          'lib/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart');
      expect(src, contains('loanSettingsProvider'));
      expect(src, contains('LoanSettings.defaults.minAmount'));
      // Walang hardcoded na slider label / error message — galing sa settings.
      expect(src, isNot(contains("Text('₱3,000'")));
      expect(src, isNot(contains("Text('₱500,000'")));
      expect(src, isNot(contains("between ₱3,000 and ₱500,000")));
    });

    test('In-Office Step 3: settings din ang gamit', () {
      final src = _read(
          'lib/presentation/features/head_manager/in_office/widgets/step3_loan_details.dart');
      expect(src, contains('loanSettingsProvider'));
      expect(src, contains('_minAmount = settings.minAmount'));
      expect(src, isNot(contains('static const double _minAmount')));
    });

    test('Provider: autoDispose (sariwa tuwing bubuksan) + realtime refresh',
        () {
      final src =
          _read('lib/presentation/shared/providers/loan_settings_provider.dart');
      expect(src, contains('FutureProvider.autoDispose<LoanSettings>'));
      expect(src, contains("subscribe('system_config'"));
      expect(src, contains('invalidateSelf'));
    });

    test('Head Manager save: ini-invalidate ang loan settings cache', () {
      final src = _read(
          'lib/presentation/features/head_manager/settings/screens/hm_settings_screen.dart');
      expect(src, contains('invalidate(loanSettingsProvider)'));
    });
  });

  group('Source guards: backend', () {
    test('getLoanLimits ang ine-enforce sa apply at preview', () {
      final apply = _squash(_read('supabase/functions/loans-apply/index.ts'));
      final view = _squash(_read('supabase/functions/loans-view/index.ts'));
      final inOffice =
          _squash(_read('supabase/functions/in-office-view/index.ts'));
      expect(apply, contains('getLoanLimits'));
      expect(apply, isNot(contains('validateLoanAmount')));
      expect(view, contains('getLoanLimits'));
      expect(inOffice, contains('getLoanLimits'));
    });

    test('Loan settings endpoint para sa lender/staff', () {
      final src = _squash(_read('supabase/functions/system-view/index.ts'));
      expect(src, contains("case 'get-loan-settings'"));
      expect(src, contains('ROLES.LENDER'));
      expect(src, contains('min_amount: limits.min'));
    });

    test('Shared helper: fallback sa ₱3,000–₱500,000', () {
      final src = _squash(_read('supabase/functions/_shared/system_config.ts'));
      expect(src, contains('MIN_LOAN_AMOUNT'));
      expect(src, contains('MAX_LOAN_AMOUNT'));
    });

    test('Migration: hindi na fixed 3,000–500,000 ang DB check', () {
      const path = 'supabase/migrations/00184_loan_limits_from_config.sql';
      expect(File(path).existsSync(), isTrue);
      final sql = _squash(_read(path));
      expect(sql, contains('DROP CONSTRAINT'));
      expect(sql, contains('CHECK (principal_amount > 0'));
    });
  });
}
