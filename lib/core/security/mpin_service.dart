// lib/core/security/mpin_service.dart
//
// App-level 4-digit MPIN para sa rider at lender.
//
// Ito ang kapalit ng device credential (screen lock / fingerprint / Face ID)
// kapag WALANG naka-set na password ang phone ng user. Naka-hash (SHA-256 +
// random salt) ang MPIN sa encrypted storage ng device lang — hindi ito
// kailanman ipinapadala sa server.
//
// Naka-scope sa user id ang storage keys kaya:
//   * hindi umaabot ang MPIN ng isang account sa ibang account na gagamit ng
//     parehong phone, at
//   * hindi ito nabubura kapag nag-log out at nag-log in muli ang parehong user.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
/// Safe ang lahat ng method kahit hindi pa naka-set ang MPIN — ang
/// [isSet] ang dapat tawagin bago mag-hingi ng MPIN.
class MpinService {
  MpinService({FlutterSecureStorage? storage})
      : _storage = storage ?? _defaultStorage;

  final FlutterSecureStorage _storage;

  /// Haba ng MPIN — 4 na digit ayon sa requirement.
  static const int pinLength = 4;

  /// Ilang maling attempt bago pansamantalang i-lock ang MPIN input.
  static const int maxAttempts = 5;

  /// Tagal ng lockout pagkatapos maubos ang attempts.
  static const Duration lockoutDuration = Duration(seconds: 60);

  /// Maximum na PALIT ng MPIN sa loob ng isang window (unang set-up na lang
  /// ang hindi binibilang).
  static const int maxChangesPerWindow = 10;

  /// Haba ng window bago muling ma-reset ang bilang ng palit (15 araw).
  static const Duration changeWindow = Duration(days: 15);

  /// Kaparehong options sa [SecureStorage] para pareho ang pinag-iimbakan
  /// (mahalaga sa web, kung saan prefix ang `publicKey` at hindi RSA key).
  static const _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    webOptions: WebOptions(
      dbName: 'jireta_secure_storage',
      publicKey: 'jireta_loans_pub_key',
    ),
  );

  /// True kapag 4 na digit (0-9) — ang tanging valid na format ng MPIN.
  static bool isValidFormat(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  /// True kapag may naka-set nang MPIN para sa kasalukuyang naka-log in.
  Future<bool> isSet() async {
    try {
      final scope = await _scope();
      final hash = await _storage.read(key: _hashKey(scope));
      return hash != null && hash.isNotEmpty;
    } catch (e) {
      AppLogger.w('[MPIN] isSet failed: $e');
      return false;
    }
  }

  /// Sine-save ang bagong MPIN (nire-reset din ang attempts at lockout).
  ///
  /// Limitasyon: 10 palit lang sa loob ng 15 araw. Kapag naabot na ito,
  /// nagbabato ng [MpinChangeLimitException] — kailangan maghintay hanggang
  /// mag-reset ang window. Ang unang set-up (wala pang naka-set na MPIN)
  /// ay hindi binibilang.
  Future<void> setMpin(String pin) async {
    if (!isValidFormat(pin)) {
      throw ArgumentError('MPIN must be exactly $pinLength digits');
    }
    final scope = await _scope();

    final everSet = (await _storage.read(key: _setupDoneKey(scope))) == '1';
    if (everSet) {
      final retryAfter = await _consumeChangeQuota(scope);
      if (retryAfter != null) throw MpinChangeLimitException(retryAfter);
    } else {
      await _storage.write(key: _setupDoneKey(scope), value: '1');
      await _storage.write(
          key: _windowStartKey(scope),
          value: '${DateTime.now().millisecondsSinceEpoch}');
      await _storage.write(key: _changeCountKey(scope), value: '0');
    }

    final salt = _randomSalt();
    await _storage.write(key: _saltKey(scope), value: salt);
    await _storage.write(key: _hashKey(scope), value: _hash(pin, salt));
    await _storage.delete(key: _failKey(scope));
    await _storage.delete(key: _lockKey(scope));
    AppLogger.i('[MPIN] MPIN set for scope=$scope');
  }

  /// Ini-verify ang MPIN. Hindi ito nagbabalik ng `bool` para maihatid ng UI
  /// ang natitirang attempts at ang lock countdown nang tama.
  Future<MpinVerifyResult> verify(String pin) async {
    final scope = await _scope();

    final lockUntil = await _readInt(_lockKey(scope));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lockUntil != null && lockUntil > now) {
      return MpinVerifyResult(
        MpinStatus.locked,
        lockRemaining: Duration(milliseconds: lockUntil - now),
      );
    }

    final salt = await _storage.read(key: _saltKey(scope));
    final hash = await _storage.read(key: _hashKey(scope));
    if (salt == null || salt.isEmpty || hash == null || hash.isEmpty) {
      return const MpinVerifyResult(MpinStatus.notSet);
    }

    if (_hash(pin, salt) == hash) {
      await _storage.delete(key: _failKey(scope));
      await _storage.delete(key: _lockKey(scope));
      return const MpinVerifyResult(MpinStatus.success);
    }

    final fails = (await _readInt(_failKey(scope)) ?? 0) + 1;
    if (fails >= maxAttempts) {
      await _storage.write(key: _failKey(scope), value: '0');
      await _storage.write(
        key: _lockKey(scope),
        value: '${now + lockoutDuration.inMilliseconds}',
      );
      return const MpinVerifyResult(
        MpinStatus.locked,
        lockRemaining: lockoutDuration,
      );
    }
    await _storage.write(key: _failKey(scope), value: '$fails');
    return MpinVerifyResult(
      MpinStatus.wrong,
      attemptsLeft: maxAttempts - fails,
    );
  }

  /// Natitirang oras ng lockout, o `null` kapag hindi naka-lock.
  Future<Duration?> lockRemaining() async {
    try {
      final lockUntil = await _readInt(_lockKey(await _scope()));
      if (lockUntil == null) return null;
      final remaining = lockUntil - DateTime.now().millisecondsSinceEpoch;
      return remaining > 0 ? Duration(milliseconds: remaining) : null;
    } catch (_) {
      return null;
    }
  }

  /// Binubura ang MPIN (kasama ang salt, attempts at lockout) para sa
  /// kasalukuyang naka-log in na user.
  Future<void> clear() async {
    final scope = await _scope();
    for (final key in [
      _hashKey(scope),
      _saltKey(scope),
      _failKey(scope),
      _lockKey(scope),
    ]) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
    AppLogger.i('[MPIN] MPIN cleared for scope=$scope');
  }

  // ── Internals ────────────────────────────────────────────────────────────

  /// Ang user id ang scope ng bawat key. Bago ang unang successful na
  /// login (o sa web na hindi pa naka-hydrate) `guest` ang gamit para hindi
  /// mag-crash — normal nang wala pang MPIN sa ganoong state.
  Future<String> _scope() async {
    try {
      final id = await SecureStorage.getUserId();
      if (id != null && id.trim().isNotEmpty) return id.trim();
    } catch (_) {}
    return 'guest';
  }

  String _hashKey(String scope) => 'app_mpin_hash_$scope';
  String _saltKey(String scope) => 'app_mpin_salt_$scope';
  String _failKey(String scope) => 'app_mpin_fails_$scope';
  String _lockKey(String scope) => 'app_mpin_lock_$scope';
  String _setupDoneKey(String scope) => 'app_mpin_setup_done_$scope';
  String _windowStartKey(String scope) => 'app_mpin_change_window_$scope';
  String _changeCountKey(String scope) => 'app_mpin_change_count_$scope';

  /// Kinokonsumo ang isang palit sa kasalukuyang 15-day window. Nagbabalik ng
  /// natitirang hintay kapag puno na ang 10-palit na limitasyon, o `null`
  /// kapag pinayagan ang palit.
  Future<Duration?> _consumeChangeQuota(String scope) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = await _readInt(_windowStartKey(scope));
    var count = await _readInt(_changeCountKey(scope)) ?? 0;

    if (start == null || now - start >= changeWindow.inMilliseconds) {
      // Bagong window — i-reset ang bilang.
      await _storage.write(key: _windowStartKey(scope), value: '$now');
      count = 0;
    }

    if (count >= maxChangesPerWindow) {
      final resetAt = (start ?? now) + changeWindow.inMilliseconds;
      final remainingMs = resetAt - now;
      return Duration(milliseconds: remainingMs > 0 ? remainingMs : 0);
    }

    await _storage.write(key: _changeCountKey(scope), value: '${count + 1}');
    return null;
  }

  /// Natitirang palit sa kasalukuyang 15-day window at gaano pa katagal bago
  /// ito ma-reset. Ginagamit ng Profile UI para ipakita ang limitasyon bago
  /// pa magtangka ang user na magpalit.
  Future<({int remaining, Duration? resetIn})> changeQuota() async {
    final scope = await _scope();
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = await _readInt(_windowStartKey(scope));
    final count = await _readInt(_changeCountKey(scope)) ?? 0;

    if (start == null || now - start >= changeWindow.inMilliseconds) {
      return (remaining: maxChangesPerWindow, resetIn: null);
    }
    final remainingMs = (start + changeWindow.inMilliseconds) - now;
    final remaining = (maxChangesPerWindow - count).clamp(0, maxChangesPerWindow);
    return (
      remaining: remaining,
      resetIn: remaining > 0
          ? null
          : Duration(milliseconds: remainingMs > 0 ? remainingMs : 0),
    );
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  Future<int?> _readInt(String key) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return null;
      return int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }
}

final mpinServiceProvider = Provider<MpinService>((ref) => MpinService());
