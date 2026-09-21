// lib/core/security/mpin_service.dart
//
// App-level 4-digit MPIN para sa rider at lender — SERVER-SIDE (account-level).
//
// Dati itong DEVICE-LOCAL: ang hash (SHA-256 + salt) ay nasa secure storage ng
// device lang at hindi kailanman ipinapadala sa server. Bunga:
//   * hindi nadadala ang MPIN sa bagong phone — kailangang i-setup muli,
//   * device lang ang nakakaalam kung may MPIN ang account, at
//   * ang pag-restore ng session pagkatapos ng MPIN unlock ay gumagawa ng
//     "stub" user (walang pangalan) sa auth state — sanhi ng pag-ulit ng
//     one-time Terms & Conditions / Fill In Information para sa lumang account.
//
// Ngayon ang `user_mpins` table (Edge Function `auth-mpin`) ang source of truth:
//   * pareho ang MPIN sa lahat ng device ng account,
//   * server-side ang attempts / lockout, at
//   * server-side din ang 10-palit-sa-15-araw na limitasyon.
//
// Ang tanging lokal na natitira ay isang BOOLEAN HINT ("may MPIN ba ang account
// na ito?") para malaman ng login page kung MPIN o OTP ang unang ipapakita —
// hindi ito ang MPIN mismo at hindi ito maaaring gamitin para mag-unlock.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/remote/mpin_remote_datasource.dart';
import '../di/injection.dart';
import '../utils/logger.dart';
import 'secure_storage.dart';

/// Resulta ng isang [MpinService.verify] na tawag.
enum MpinStatus {
  /// Tama ang MPIN.
  success,

  /// Mali ang MPIN pero may natitira pang attempts.
  wrong,

  /// Sobrang dami ng maling attempt — pansamantalang naka-lock.
  locked,

  /// Wala pang naka-set na MPIN sa account na ito.
  notSet,

  /// Hindi naabot ang server (offline / walang valid session). HIWALAY ito sa
  /// [wrong] — hindi "mali ang MPIN", hindi rin "naka-lock": kailangan lang ng
  /// internet para ma-verify ang MPIN (server-side na ito).
  offline,
}

/// Ibinabato kapag naubos na ang 10 palit ng MPIN sa loob ng 15 araw.
class MpinChangeLimitException implements Exception {
  const MpinChangeLimitException(this.retryAfter);

  /// Gaano pa katagal bago ma-reset ang 15-day window (puwede nang magpalit ulit).
  final Duration retryAfter;

  @override
  String toString() =>
      'MpinChangeLimitException(retryAfter: ${retryAfter.inHours}h)';
}

class MpinVerifyResult {
  const MpinVerifyResult(
    this.status, {
    this.attemptsLeft,
    this.lockRemaining,
  });

  final MpinStatus status;

  /// Ilang maling attempt pa bago ma-lock (kapag [MpinStatus.wrong]).
  final int? attemptsLeft;

  /// Gaano pa katagal bago makapag-try muli (kapag [MpinStatus.locked]).
  final Duration? lockRemaining;

  bool get isSuccess => status == MpinStatus.success;
}

/// Nag-iimbak at nag-ve-verify ng 4-digit MPIN ng rider / lender.
///
/// Ang lahat ng tawag ay sa server (maliban sa maliit na boolean hint para sa
/// login page), kaya kailangan ng internet at ng naka-authenticate na session.
class MpinService {
  MpinService({MpinRemoteDataSource? ds}) : _ds = ds;

  /// Iniksyon para sa tests; kapag `null` ay ang registered na datasource
  /// (`sl<MpinRemoteDataSource>()`) ang gamit — lazy para hindi ito abutin sa
  /// oras ng construction (mahalaga sa widget tests).
  final MpinRemoteDataSource? _ds;
  MpinRemoteDataSource get _remote => _ds ?? sl<MpinRemoteDataSource>();

  /// Haba ng MPIN — 4 na digit ayon sa requirement.
  static const int pinLength = 4;

  /// Ilang maling attempt bago pansamantalang i-lock ang MPIN input.
  /// (Tatlo lang — mahigpit na ito dahil 4-digit lang ang MPIN.)
  static const int maxAttempts = 3;

  /// Tagal ng lockout pagkatapos maubos ang attempts (tugma sa server).
  static const Duration lockoutDuration = Duration(seconds: 60);

  /// Maximum na PALIT ng MPIN sa loob ng isang window (unang set-up na lang
  /// ang hindi binibilang).
  static const int maxChangesPerWindow = 10;

  /// Haba ng window bago muling ma-reset ang bilang ng palit (15 araw).
  static const Duration changeWindow = Duration(days: 15);

  /// True kapag 4 na digit (0-9) — ang tanging valid na format ng MPIN.
  static bool isValidFormat(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  /// True kapag may naka-set nang MPIN ang ACCOUNT.
  ///
  /// Sinusubukan muna ang server (auth-mpin `status`). Kapag hindi ito maabot
  /// (offline, o wala pang session), ibinabalik ang HULING nalalaman na
  /// kasagutan mula sa local na hint — hindi ito ang MPIN, flag lang.
  Future<bool> isSet() async {
    try {
      final status = await _remote.status();
      await _cacheExists(status.hasMpin);
      return status.hasMpin;
    } catch (e) {
      final cached = await _cachedExists();
      AppLogger.w('[MPIN] isSet: hindi maabot ang server ($e) — cached=$cached');
      return cached ?? false;
    }
  }

  /// Sine-save ang bagong MPIN sa account (nire-reset din ang attempts at
  /// lockout server-side).
  ///
  /// Kapag may MPIN na ang account, kailangan ang [currentMpin] (pangalawang
  /// tsek ng server, bukod sa `verify` na ginagawa ng UI bago magpalit).
  ///
  /// Limitasyon: 10 palit lang sa loob ng 15 araw. Kapag naabot na ito,
  /// nagbabato ng [MpinChangeLimitException] — kailangan maghintay hanggang
  /// mag-reset ang window. Ang unang set-up (wala pang naka-set na MPIN) ay
  /// hindi binibilang.
  Future<void> setMpin(String pin, {String? currentMpin}) async {
    if (!isValidFormat(pin)) {
      throw ArgumentError('MPIN must be exactly $pinLength digits');
    }
    final reply = await _remote.setMpin(mpin: pin, currentMpin: currentMpin);
    if (!reply.saved) {
      throw MpinChangeLimitException(
        reply.changeLimitRemaining ?? Duration.zero,
      );
    }
    await _cacheExists(true);
    AppLogger.i('[MPIN] MPIN saved (server-side)');
  }

  /// Ini-verify ang MPIN sa server. Hindi ito nagbabalik ng `bool` para
  /// maihatid ng UI ang natitirang attempts at ang lock countdown nang tama.
  Future<MpinVerifyResult> verify(String pin) async {
    try {
      final reply = await _remote.verify(pin);
      switch (reply.outcome) {
        case MpinVerifyOutcome.success:
          return const MpinVerifyResult(MpinStatus.success);
        case MpinVerifyOutcome.wrong:
          return MpinVerifyResult(
            MpinStatus.wrong,
            attemptsLeft: reply.attemptsLeft ?? maxAttempts - 1,
          );
        case MpinVerifyOutcome.locked:
          return MpinVerifyResult(
            MpinStatus.locked,
            lockRemaining: reply.lockRemaining ?? lockoutDuration,
          );
        case MpinVerifyOutcome.notSet:
          await _cacheExists(false);
          return const MpinVerifyResult(MpinStatus.notSet);
      }
    } catch (e) {
      // Hindi naabot ang server — HINDI ito "maling MPIN". Server-side na ang
      // verification, kaya kailangan ng internet.
      AppLogger.w('[MPIN] verify: hindi maabot ang server ($e)');
      return const MpinVerifyResult(MpinStatus.offline);
    }
  }

  /// Natitirang oras ng lockout, o `null` kapag hindi naka-lock.
  Future<Duration?> lockRemaining() async {
    try {
      final status = await _remote.status();
      return status.lockRemaining;
    } catch (_) {
      return null;
    }
  }

  /// Binubura ang MPIN ng account (forgot MPIN).
  ///
  /// Ginagamit pagkatapos ng OTP login (napatunayan na ng OTP ang numero) at ng
  /// "Reset MPIN" sa Profile (pagkatapos ma-verify ang kasalukuyang MPIN).
  Future<void> clear() async {
    try {
      await _remote.reset();
    } finally {
      await _cacheExists(false);
    }
    AppLogger.i('[MPIN] MPIN cleared (server-side)');
  }

  /// Natitirang palit sa kasalukuyang 15-day window at gaano pa katagal bago
  /// ito ma-reset. Ginagamit ng Profile UI para ipakita ang limitasyon bago
  /// pa magtangka ang user na magpalit.
  ///
  /// Kapag hindi maabot ang server, hindi ito humaharang: buo ang ipinapakitang
  /// quota at ang server pa rin ang huling magsasabi kapag nagpalit.
  Future<({int remaining, Duration? resetIn})> changeQuota() async {
    try {
      final status = await _remote.status();
      return (
        remaining: status.changesRemaining,
        resetIn: status.changeResetIn,
      );
    } catch (_) {
      return (remaining: maxChangesPerWindow, resetIn: null);
    }
  }

  // ── Local hint (BOOLEAN lang — hindi ang MPIN) ───────────────────────────

  /// `<user id>` (o ang huling owner ng device kapag wala nang session).
  Future<String?> _scope() async {
    try {
      final id = await SecureStorage.getUserId();
      if (id != null && id.trim().isNotEmpty) return id.trim();
      final owner = await SecureStorage.getLoginOwnerId();
      if (owner != null && owner.trim().isNotEmpty) return owner.trim();
    } catch (_) {}
    return null;
  }

  Future<void> _cacheExists(bool exists) async {
    final scope = await _scope();
    if (scope == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_existsPrefix$scope', exists);
    } catch (_) {}
  }

  Future<bool?> _cachedExists() async {
    final scope = await _scope();
    if (scope == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_existsPrefix$scope');
    } catch (_) {
      return null;
    }
  }

  static const String _existsPrefix = 'app_mpin_exists_';
}

final mpinServiceProvider = Provider<MpinService>((ref) => MpinService());
