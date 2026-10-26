// test/otp_delivery_notice_test.dart
//
// Ang OTP screen ay dating laging "Your code is on its way" o "OTP sent
// successfully" — hindi tumutugma sa totoong kalagayan ng SMS. Sinisiguro ng
// test na ito na:
//   * "delivered" lang ang sinasabi kapag may delivery report (`confirmed`),
//   * walang "sent" kapag naka-queue pa lang (`queued`) o walang status
//     (`unconfirmed`),
//   * walang ipinapakitang SMS message kapag email ang channel (null).
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/auth/providers/auth_provider.dart';

void main() {
  test('confirmed lang ang nagsasabing delivered', () {
    expect(
      otpDeliveryNoticeFor('confirmed'),
      'Code delivered to your phone.',
    );

    // `sent` = tinanggap ng carrier, walang delivery report: hindi "delivered".
    final carrierAccepted = otpDeliveryNoticeFor('carrier_accepted');
    expect(carrierAccepted, isNotNull);
    expect(carrierAccepted!.toLowerCase().contains('delivered'), isFalse);

    // Nasa queue pa o walang status: hinding hindi "sent"/"delivered".
    final queued = otpDeliveryNoticeFor('queued');
    expect(queued, isNotNull);
    expect(queued!.toLowerCase().contains('delivered'), isFalse);

    final unconfirmed = otpDeliveryNoticeFor('unconfirmed');
    expect(unconfirmed, isNotNull);
    expect(unconfirmed!.toLowerCase().contains('delivered'), isFalse);
    expect(unconfirmed.toLowerCase(), contains('not yet confirmed'));
  });

  test('walang SMS message kapag hindi kilala ang channel', () {
    // Email ang OTP channel: walang `sms_delivery` sa response.
    expect(otpDeliveryNoticeFor(null), isNull);
    expect(otpDeliveryNoticeFor(''), isNull);
    expect(otpDeliveryNoticeFor('something-else'), isNull);
  });
}
