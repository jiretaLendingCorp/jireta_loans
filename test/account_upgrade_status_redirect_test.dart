// test/account_upgrade_status_redirect_test.dart
//
// Kapag nakapag-submit na ng Account Upgrade, ang pagpapasok sa verification
// screen ay dapat deretsong Account Upgrade Status page — hindi yung blangkong
// screen na may button pa lang.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/lender/account_upgrade/screens/lender_account_upgrade_submit_screen.dart';

void main() {
  bool redirect(String status, {bool loading = false}) =>
      shouldOpenAccountUpgradeStatus(
        status: status,
        isLoading: loading,
        successSubmitted: false,
        isSubmitting: false,
      );

  test('submitted at under_review ay deretso sa status page', () {
    expect(redirect('submitted'), isTrue);
    expect(redirect('under_review'), isTrue);
  });

  test('hindi pa nag-submit o verified na ay hindi nagre-redirect', () {
    expect(redirect('not_submitted'), isFalse);
    expect(redirect('verified'), isFalse);
    expect(redirect('approved'), isFalse);
    expect(redirect('rejected'), isFalse);
  });

  test('hindi pa loaded ang status — huwag mag-redirect', () {
    expect(redirect('submitted', loading: true), isFalse);
  });

  test('kaka-submit lang sa screen na ito — success modal muna', () {
    for (final status in ['submitted', 'under_review']) {
      expect(
        shouldOpenAccountUpgradeStatus(
          status: status,
          isLoading: false,
          successSubmitted: true,
          isSubmitting: false,
        ),
        isFalse,
        reason: 'Hindi dapat agawin ang success modal para sa $status',
      );
      expect(
        shouldOpenAccountUpgradeStatus(
          status: status,
          isLoading: false,
          successSubmitted: false,
          isSubmitting: true,
        ),
        isFalse,
        reason: 'Tumatakbo pa ang submit para sa $status',
      );
    }
  });
}
