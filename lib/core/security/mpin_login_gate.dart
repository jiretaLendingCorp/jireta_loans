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
      // Kailangan may naka-store pang session (refresh token) na maibabalik ng
      // MPIN. Kapag wala na (tunay nang tapos/na-revoke ang session, o hard
      // logout ang nangyari), walang maibabalik ang MPIN — mas tapat na ang
      // "Mobile Number" + Send OTP na form ang lumabas kaysa MPIN na tiyak na
      // bigong mag-restore.
      final hasStoredSession =
          (await SecureStorage.getRefreshToken()) != null;
      if (!hasStoredSession) {
        return MpinLoginChoice(showMpin: false, phone: phone);
      }
      final hasMpin = await _mpin.isSet();
      return MpinLoginChoice(showMpin: hasMpin, phone: phone);
    } catch (_) {
      return const MpinLoginChoice(showMpin: false);
    }
  }
}
