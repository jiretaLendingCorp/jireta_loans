// lib/core/security/mpin_login_gate.dart
//
// Ang desisyon kung alin ang lalabas sa mobile login page:
//   * ang "Enter MPIN" na screen (kasama ang switch number), o
//   * ang "Mobile Number" + Send OTP na form.
//
// Nasa hiwalay na class ito (hindi nakabaon sa widget) para masubukan nang
// direkta — mahalagang hindi na ito masira, dahil dito nakasalalay ang
// pagpasok ng rider / lender gamit ang MPIN.
//
// Tatlong bagay ang kailangan para MPIN screen:
//   1. may NATANDAANG numero (galing lang ito sa mobile OTP login),
//   2. may naka-set na MPIN sa device na ito, at
//   3. hindi staff role (head manager / employee → palaging OTP form).
//
// Ang (1) at (2) ay sadyang hindi binubura ng `SecureStorage.clearAll()`, kaya
// kahit natapos na ang session (logout, expired, revoked) ay MPIN pa rin ang
// unang lumalabas — hindi ang OTP form.
//
// SADYANG WALANG tsek dito kung may natitirang session: laging "Enter MPIN" ang
// unang lalabas basta may natandaang numero at may naka-set na MPIN. Kung
// talagang tapos na ang session, ang MPIN screen mismo ang magsasabi nito at
// dadalhin ang user sa mobile number + OTP.
import '../constants/app_constants.dart';
import 'mpin_service.dart';
import 'secure_storage.dart';

/// Resulta ng [MpinLoginGate.resolve].
class MpinLoginChoice {
  const MpinLoginChoice({required this.showMpin, this.phone});

  /// `true` kapag ang MPIN screen ang dapat ipakita.
  final bool showMpin;

  /// Ang numerong isasama sa MPIN screen (at gagamitin ng Reset MPIN flow).
  final String? phone;
}

class MpinLoginGate {
  MpinLoginGate({MpinService? mpin}) : _mpin = mpin ?? MpinService();

  final MpinService _mpin;

  Future<MpinLoginChoice> resolve() async {
    try {
      final phone = await SecureStorage.getLoginPhone();
      // Fallback sa natandaang "lock owner" kung na-clear na ang session role.
      final role = await SecureStorage.getUserRole() ??
          await SecureStorage.getLoginOwnerRole();
      // Malinaw na staff ang naka-record → hindi ito MPIN screen.
      final isKnownStaffRole = role == AppConstants.roleHeadManager ||
          role == AppConstants.roleEmployee;
      if (phone == null || isKnownStaffRole) {
        return MpinLoginChoice(showMpin: false, phone: phone);
      }
      // TSEK: hindi na sinusuri dito kung may natitirang session (refresh
      // token). Dati ay sinusuri ito — at iyon ang dahilan kung bakit,
      // pagkatapos ng ISANG logout o na-expire na session, permanenteng ang
      // "Mobile Number" + Send OTP na form na ang lumalabas kahit may MPIN
      // pa ang device (at kahit ilang beses pang isara at buksan ang app).
      // Kahilingan mismo ng user: laging "Enter MPIN" na may switch number.
      // Kapag wala nang ma-restore, sasabihin ito ng MPIN screen pagkatapos
      // ipasok ang MPIN at doon dadalhin ang user sa OTP.
      final hasMpin = await _mpin.isSet();
      return MpinLoginChoice(showMpin: hasMpin, phone: phone);
    } catch (_) {
      return const MpinLoginChoice(showMpin: false);
    }
  }
}
