// lib/data/datasources/remote/mpin_remote_datasource.dart
//
// Server-side (ACCOUNT-level) MPIN — `auth-mpin` edge function.
//
// Dating device-local lang ang MPIN (hash sa secure storage). Ngayon, ang
// server ang source of truth kaya:
//   * pareho ang MPIN sa lahat ng device ng account,
//   * server-side ang attempts / lockout, at
//   * server-side din ang quota (10 palit sa loob ng 15 araw).
//
// Hindi kailanman lumalabas ang hash sa response; ang MPIN ay ipinapadala
// (over HTTPS) para ma-verify/hasahin sa server.
import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

/// Resulta ng `?fn=verify`.
enum MpinVerifyOutcome { success, wrong, locked, notSet }

class MpinVerifyReply {
  const MpinVerifyReply(
    this.outcome, {
    this.attemptsLeft,
    this.lockRemaining,
  });

  final MpinVerifyOutcome outcome;

  /// Natitirang attempts pagkatapos ng isang maling MPIN.
  final int? attemptsLeft;

  /// Gaano pa katagal bago makapag-try muli kapag naka-lock.
  final Duration? lockRemaining;
}

/// Resulta ng `?fn=status`.
class MpinStatusReply {
  const MpinStatusReply({
    required this.hasMpin,
    this.lockRemaining,
    this.attemptsLeft = 3,
    this.changesRemaining = 10,
    this.changeResetIn,
  });

  /// May naka-set na MPIN ba ang ACCOUNT (hindi lang ang device na ito)?
  final bool hasMpin;

  /// Lockout na natitira (kapag sumobra sa attempts).
  final Duration? lockRemaining;

  /// Buong attempts budget (nire-reset kapag tama ang MPIN).
  final int attemptsLeft;

  /// Natitirang palit sa kasalukuyang 15-day window.
  final int changesRemaining;

  /// Gaano pa katagal bago mag-reset ang window (kapag naubos na ang palit).
  final Duration? changeResetIn;
}

/// Resulta ng `?fn=set`.
class MpinSetReply {
  const MpinSetReply({required this.saved, this.changeLimitRemaining});

  final bool saved;

  /// Kapag hindi na-save dahil puno na ang 15-day change quota.
  final Duration? changeLimitRemaining;
}

class MpinRemoteDataSource {
  final DioClient _client;
  MpinRemoteDataSource(this._client);

  Future<MpinStatusReply> status() async {
    final res = await _client.get(ApiEndpoints.authMpinStatus);
    final data = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
    return MpinStatusReply(
      hasMpin: data['has_mpin'] == true,
      lockRemaining: _duration(data['retry_after_seconds']),
      attemptsLeft: _int(data['attempts_left']) ?? 3,
      changesRemaining: _int(data['changes_remaining']) ?? 10,
      changeResetIn: _duration(data['change_reset_in_seconds']),
    );
  }

  /// Hindi ito nagbabato para sa MALI / LOCKED / NOT_SET — ang [MpinVerifyReply]
  /// ang nagdadala ng resulta. Ang tanging nagbabato ay ang hindi makarating sa
  /// server (offline / 500), para makilala ng caller ang "offline" mula sa
  /// "maling MPIN".
  Future<MpinVerifyReply> verify(String mpin) async {
    try {
      await _client.post(ApiEndpoints.authMpinVerify, data: {'mpin': mpin});
      return const MpinVerifyReply(MpinVerifyOutcome.success);
    } on DioException catch (e) {
      final code = _errorCode(e);
      final extra = _errorExtra(e);
      switch (code) {
        case 'MPIN_LOCKED':
          return MpinVerifyReply(
            MpinVerifyOutcome.locked,
            lockRemaining: Duration(
              seconds: _int(extra['retry_after_seconds']) ?? 60,
            ),
          );
        case 'MPIN_NOT_SET':
          return const MpinVerifyReply(MpinVerifyOutcome.notSet);
        case 'INVALID_MPIN':
          return MpinVerifyReply(
            MpinVerifyOutcome.wrong,
            attemptsLeft: _int(extra['attempts_left']),
          );
        default:
          rethrow;
      }
    }
  }

  Future<MpinSetReply> setMpin({
    required String mpin,
    String? currentMpin,
  }) async {
    try {
      await _client.post(ApiEndpoints.authMpinSet, data: {
        'mpin': mpin,
        if (currentMpin != null && currentMpin.isNotEmpty)
          'current_mpin': currentMpin,
      });
      return const MpinSetReply(saved: true);
    } on DioException catch (e) {
      if (_errorCode(e) == 'MPIN_CHANGE_LIMIT') {
        return MpinSetReply(
          saved: false,
          changeLimitRemaining: Duration(
            seconds: _int(_errorExtra(e)['retry_after_seconds']) ?? 0,
          ),
        );
      }
      rethrow;
    }
  }

  /// Binubura ang MPIN ng account (forgot MPIN — pagkatapos ng OTP login, kung
  /// saan napatunayan na ng OTP ang pagmamay-ari ng numero).
  Future<void> reset() async {
    await _client.post(ApiEndpoints.authMpinReset);
  }

  // ── Error helpers ─────────────────────────────────────────────────────────

  String? _errorCode(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['code'] != null) return err['code'].toString();
      if (data['code'] != null) return data['code'].toString();
    }
    return null;
  }

  Map _errorExtra(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map) return err;
    }
    return const {};
  }

  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Duration? _duration(Object? seconds) {
    final value = _int(seconds);
    if (value == null || value <= 0) return null;
    return Duration(seconds: value);
  }
}
