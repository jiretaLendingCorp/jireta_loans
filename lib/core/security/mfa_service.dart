// lib/core/security/mfa_service.dart
//
// ── Google Authenticator (TOTP) na second factor ─────────────────────────────
//
// Ginagamit nito ang SUPABASE AUTH MFA API (`enroll` / `challenge` / `verify` /
// `unenroll`) — hindi ito gumagawa ng sariling secret store. Dahil dito:
//
//   * ang TOTP secret ay nananatili sa GoTrue (`auth.mfa_factors`), HINDI sa
//     alinmang table ng app (walang plaintext secret sa application DB);
//   * ang isang matagumpay na `verify` ang nagpapataas ng session sa `aal2`
//     (`access_token` na may `aal: aal2` claim) — iyon ang pinagbabatayan ng
//     server-side enforcement sa `_shared/mfa.ts`;
//   * walang client-side boolean na itinuturing na "patunay" — ang token mismo
//     (aal2) ang patunay.
//
// ── Paano ito sumasabay sa phone-OTP login ng app ────────────────────────────
// Ang login ng app ay `auth-otp?fn=verify-otp` (Edge Function) na sa loob ay
// `signInWithPassword` (phone/password o synthetic email). Ang ganoong grant ay
// nagbibigay ng `aal1` session kahit may naka-enroll na TOTP factor — kaya
// compatible ito: kailangan lang i-load ang session sa Supabase client
// (`setSession`) at pagkatapos ay `mfa.challenge` + `mfa.verify` para maging
// `aal2`.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/logger.dart';
import 'secure_storage.dart';

/// Ang [MfaService] na ginagamit ng UI (profile card + login gate).
final mfaServiceProvider = Provider<MfaService>((ref) => MfaService());

/// Ang mga factor na nasa account (galing sa GoTrue `/user`).
enum MfaFactorState { verified, unverified }

class MfaFactor {
  const MfaFactor({
    required this.id,
    required this.friendlyName,
    required this.state,
    this.createdAt,
  });

  final String id;
  final String friendlyName;
  final MfaFactorState state;
  final DateTime? createdAt;

  bool get isVerified => state == MfaFactorState.verified;
}

/// Ang `aal` / `nextLevel` ng kasalukuyang session.
class MfaAssurance {
  const MfaAssurance({this.currentLevel, this.nextLevel});

  /// `aal1` (OTP lang) o `aal2` (OTP + authenticator code).
  final String? currentLevel;
  final String? nextLevel;

  bool get isAal2 => currentLevel == 'aal2';
}

class MfaStatus {
  const MfaStatus({
    required this.verifiedFactors,
    required this.unverifiedFactors,
    required this.assurance,
  });

  const MfaStatus.unknown()
      : verifiedFactors = const [],
        unverifiedFactors = const [],
        assurance = const MfaAssurance();

  final List<MfaFactor> verifiedFactors;
  final List<MfaFactor> unverifiedFactors;
  final MfaAssurance assurance;

  bool get enrolled => verifiedFactors.isNotEmpty;

  String? get factorId =>
      verifiedFactors.isEmpty ? null : verifiedFactors.first.id;

  /// Kailangan pa bang ipasa ang authenticator challenge?
  ///
  /// `true` kapag may verified factor ang account PERO `aal1` pa ang session.
  bool get requiresChallenge =>
      mfaChallengeRequired(
        currentLevel: assurance.currentLevel,
        verifiedFactorCount: verifiedFactors.length,
      );
}

/// Ang MFA state na iniuulat ng SERVER sa OTP login response
/// (`auth-otp?fn=verify-otp` → `mfa: { enabled, factors }`).
///
/// Pinagmumulan ng katotohanan ito: ang server (service-role) ang tumitingin sa
/// GoTrue, kaya hindi na kailangang umasa pa sa isang client round-trip bago
/// malaman kung kailangan ang authenticator challenge.
///
/// `enabled == null` = HINDI matukoy ng server (hal. error sa admin API). Hindi
/// ito "wala" — sa ganoong kaso ay may fallback ang app sa Supabase Auth
/// (`getUser().factors`).
class LoginMfaInfo {
  const LoginMfaInfo({required this.enabled, this.factorId, this.friendlyName});

  const LoginMfaInfo.unknown()
      : enabled = null,
        factorId = null,
        friendlyName = null;

  final bool? enabled;
  final String? factorId;
  final String? friendlyName;

  /// `true` kapag sinabi ng server na may VERIFIED factor ang account.
  bool get serverSaysRequired => enabled == true;

  /// Binabasa ang `mfa` block ng login response. Tanging NON-secret na
  /// metadata (factor id + pangalan) ang kinukuha — walang secret.
  factory LoginMfaInfo.fromLoginResponse(Object? raw) {
    if (raw is! Map) return const LoginMfaInfo.unknown();
    final enabled = raw['enabled'];
    final factors = raw['factors'];
    String? factorId;
    String? friendlyName;
    if (factors is List) {
      for (final entry in factors) {
        if (entry is Map && entry['id'] is String) {
          factorId = entry['id'] as String;
          final name = entry['friendly_name'];
          friendlyName = name is String ? name : null;
          break;
        }
      }
    }
    return LoginMfaInfo(
      enabled: enabled is bool ? enabled : null,
      factorId: factorId,
      friendlyName: friendlyName,
    );
  }
}

/// Purong pasya (walang I/O) kung kailangan ang MFA challenge — nasusubukan
/// ito nang walang network (tingnan ang `test/mfa_service_test.dart`).
bool mfaChallengeRequired({
  required String? currentLevel,
  required int verifiedFactorCount,
}) {
  if (verifiedFactorCount <= 0) return false;
  return currentLevel != 'aal2';
}

/// Ang enrollment na sinimulan ng [MfaService.beginEnrollment].
class MfaEnrollment {
  const MfaEnrollment({
    required this.factorId,
    required this.manualKey,
    this.qrSvg,
    this.otpauthUri,
  });

  final String factorId;

  /// Ang base32 setup key para sa MANUAL na pagpasok sa authenticator app.
  final String manualKey;

  /// Ang SVG markup ng QR code na galing sa GoTrue (null kapag hindi ito
  /// ma-parse — ang [manualKey] / [otpauthUri] pa rin ang fallback).
  final String? qrSvg;

  /// `otpauth://totp/...` — kapag hindi ma-render ang QR.
  final String? otpauthUri;
}

enum MfaFailureKind {
  /// Mali / hindi tugmang 6-digit code.
  invalidCode,

  /// Napaso na ang challenge (5 minuto) — gumawa ng bago at subukan muli.
  expiredChallenge,

  /// Sobrang daming maling pagsubok sa maikling panahon.
  tooManyAttempts,

  /// Hindi pa umabot sa `aal2` ang session para sa sensitibong aksyon.
  insufficientAssurance,

  /// Walang naka-enroll na factor (o naalis na ito).
  notEnrolled,

  /// May factor na ang account — hindi na dapat mag-enroll muli.
  alreadyEnrolled,

  /// Hindi naka-configure ang TOTP MFA sa Supabase project (Dashboard).
  unavailable,

  /// Wala nang wastong session (kailangan mag-login muli).
  notAuthenticated,

  /// Hindi maabot ang server.
  network,

  server,
}

/// Ang tanging error na ibinabalik ng [MfaService] sa UI — may FIXED na
/// user-facing na mensahe para hindi kailanman makalusot ang hilaw na GoTrue
/// text (na maaaring maglaman ng detalyeng hindi dapat ipakita).
class MfaFailure implements Exception {
  const MfaFailure(this.kind, {this.retryAfterSeconds});

  final MfaFailureKind kind;
  final int? retryAfterSeconds;

  /// Mensaheng ipinapakita sa user. HINDI ito naglalaman ng secret, code,
  /// factor id, o anumang hilaw na server payload.
  String get message {
    switch (kind) {
      case MfaFailureKind.invalidCode:
        return 'That code is not correct. Enter the latest 6-digit code from '
            'your authenticator app.';
      case MfaFailureKind.expiredChallenge:
        return 'The verification request expired. Please try again.';
      case MfaFailureKind.tooManyAttempts:
        final wait = retryAfterSeconds;
        return wait == null || wait <= 0
            ? 'Too many attempts. Please wait a few minutes before trying '
                'again.'
            : 'Too many attempts. Please try again in $wait seconds.';
      case MfaFailureKind.insufficientAssurance:
        return 'Please verify with your authenticator app before making this '
            'change.';
      case MfaFailureKind.notEnrolled:
        return 'No authenticator app is set up for this account.';
      case MfaFailureKind.alreadyEnrolled:
        return 'Two-factor authentication is already set up for this account.';
      case MfaFailureKind.unavailable:
        return 'Authenticator app verification is not available right now. '
            'Please contact support.';
      case MfaFailureKind.notAuthenticated:
        return 'Your session has expired. Please sign in again.';
      case MfaFailureKind.network:
        return 'Cannot connect to the server. Check your internet connection '
            'and try again.';
      case MfaFailureKind.server:
        return 'Something went wrong while verifying. Please try again.';
    }
  }

  @override
  String toString() => 'MfaFailure(${kind.name})';
}

/// Hinahawakan ang MFA calls ng Supabase client. Hiwalay ito sa [MfaService]
/// para masubukan ang buong logic (validation, cleanup, error mapping) gamit
/// ang isang fake na gateway — walang network sa tests.
abstract class MfaGateway {
  Future<MfaStatus> status();
  Future<MfaEnrollment> enrollTotp({String? friendlyName});
  Future<String> challenge(String factorId);

  Future<void> verify({
    required String factorId,
    required String challengeId,
    required String code,
  });

  Future<void> unenroll(String factorId);

  /// Isinasauli sa SecureStorage ang tokens na ini-rotate ng `verify`
  /// (aal1 → aal2) o ng `setSession` (kapag na-refresh ang token).
  Future<void> persistRotatedTokens();
}

class MfaService {
  MfaService({MfaGateway? gateway}) : _gateway = gateway ?? SupabaseMfaGateway();

  final MfaGateway _gateway;

  /// Ang factor na sinimulan i-enroll pero hindi pa na-verify. Nananatili ito
  /// sa memory para sa (a) pagpapatuloy ng pag-verify at (b) ligtas na
  /// paglilinis kapag kinansela ng user.
  String? _pendingFactorId;

  /// Hanggang 5 maling code bago hilingin ang muling pag-login (ang server ay
  /// may sarili ring rate limit).
  static const int maxVerificationAttempts = 5;

  /// Ang 6-digit na format lang ang tinatanggap (walang spaces / letters).
  static bool isValidCode(String? code) =>
      RegExp(r'^\d{6}$').hasMatch((code ?? '').trim());

  String? get pendingFactorId => _pendingFactorId;

  /// Isinasalin ang ANUMANG error ng gateway sa [MfaFailure] — kaya ang UI ay
  /// laging may fixed na mensahe; hindi kailanman lumalabas ang hilaw na text
  /// ng GoTrue (o anumang detalye ng enrollment) sa screen o snackbar.
  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on MfaFailure {
      rethrow;
    } catch (e) {
      throw mfaFailureFrom(e);
    }
  }

  Future<MfaStatus> status() => _run(() => _gateway.status());

  /// Sinisimulan ang TOTP enrollment: naglilinis muna ng hindi na-verify na
  /// factor (hal. iniwan ng nakanselang setup), tapos nagre-request ng bago.
  Future<MfaEnrollment> beginEnrollment({String? friendlyName}) =>
      _run(() async {
        final current = await _gateway.status();
        if (current.enrolled) {
          throw const MfaFailure(MfaFailureKind.alreadyEnrolled);
        }
        await _cleanupUnverified(current.unverifiedFactors);
        final enrollment = await _gateway.enrollTotp(
          friendlyName: friendlyName ?? _defaultFriendlyName(),
        );
        _pendingFactorId = enrollment.factorId;
        return enrollment;
      });

  /// Kinukumpirma ang enrollment gamit ang code na ipinakita ng authenticator
  /// app. Bagong challenge bawat tawag, kaya awtomatikong nagre-recover ito
  /// kapag napaso ang naunang challenge.
  ///
  /// Ang `aal2` (at ang bagong tokens) ay galing lang sa TAGUMPAY na verify —
  /// hindi ito minamarkahan ng app.
  Future<void> confirmEnrollment(String code) => _run(() async {
        final factorId = _pendingFactorId;
        if (factorId == null) {
          throw const MfaFailure(MfaFailureKind.notEnrolled);
        }
        if (!isValidCode(code)) {
          throw const MfaFailure(MfaFailureKind.invalidCode);
        }
        final challengeId = await _gateway.challenge(factorId);
        await _gateway.verify(
          factorId: factorId,
          challengeId: challengeId,
          code: code.trim(),
        );
        _pendingFactorId = null;
        await _gateway.persistRotatedTokens();
      });

  /// Kinansela ang setup — inaalis ang HINDI pa na-verify na factor (safe, dahil
  /// hindi ito ang nag-iisang factor: kung may verified factor, hindi na
  /// umabot dito ang user sa [beginEnrollment]).
  Future<void> cancelEnrollment() async {
    final factorId = _pendingFactorId;
    _pendingFactorId = null;
    if (factorId == null) return;
    try {
      await _gateway.unenroll(factorId);
    } catch (_) {
      // Best-effort: ang natirang unverified factor ay nililinis sa susunod
      // na `beginEnrollment` (o maaaring itapon mula sa authenticator app).
    }
  }

  /// Nagpapatunay muna ng authenticator code (reauthentication), tapos inaalis
  /// ang factor.
  ///
  /// MAHALAGA: hindi ito tumatanggap ng "disable" nang walang code. Ang GoTrue
  /// mismo ang tumatanggi sa `unenroll` ng verified factor kapag `aal1` ang
  /// session, kaya hindi ito ma-bypass ng direktang tawag.
  Future<void> disable({required String code}) => _run(() async {
        final current = await _gateway.status();
        final factorId = current.factorId;
        if (factorId == null) {
          throw const MfaFailure(MfaFailureKind.notEnrolled);
        }
        if (!isValidCode(code)) {
          throw const MfaFailure(MfaFailureKind.invalidCode);
        }
        final challengeId = await _gateway.challenge(factorId);
        await _gateway.verify(
          factorId: factorId,
          challengeId: challengeId,
          code: code.trim(),
        );
        await _gateway.unenroll(factorId);
        await _gateway.persistRotatedTokens();
      });

  /// Ang MFA step ng LOGIN: challenge + verify gamit ang code ng authenticator.
  /// Kapag tagumpay, `aal2` na ang session — at ang tokens ay isinasauli sa
  /// SecureStorage ng app.
  Future<void> verifyLogin({
    required String factorId,
    required String code,
  }) =>
      _run(() async {
        if (!isValidCode(code)) {
          throw const MfaFailure(MfaFailureKind.invalidCode);
        }
        final challengeId = await _gateway.challenge(factorId);
        await _gateway.verify(
          factorId: factorId,
          challengeId: challengeId,
          code: code.trim(),
        );
        await _gateway.persistRotatedTokens();
      });

  Future<void> _cleanupUnverified(List<MfaFactor> unverified) async {
    for (final factor in unverified) {
      try {
        await _gateway.unenroll(factor.id);
      } catch (_) {
        // Ligtas ipagpalit: hindi ito ang factor na ginagamit sa login.
      }
    }
  }

  String _defaultFriendlyName() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'Authenticator ${now.year}-$month-$day';
  }
}

/// Ang tunay na gateway — gumagamit ng `Supabase.instance.client` at
/// nagpapanatili ng tokens sa pagitan ng app (SecureStorage) at ng Supabase
/// client.
class SupabaseMfaGateway implements MfaGateway {
  static const String issuer = 'Jireta Loans';

  SupabaseClient get _client => Supabase.instance.client;

  /// Inililipat ang session na hawak ng app (SecureStorage) patungo sa Supabase
  /// client bago ang alinmang MFA call. Kapag expired na ang access token,
  /// nagre-refresh ito (`setSession` → `/token`), at ang bagong tokens ay
  /// agad na ibinabalik sa SecureStorage (para hindi maiwang luma ang refresh
  /// token na ginagamit ng Dio).
  Future<void> _ensureSession() async {
    final access = await SecureStorage.getAccessToken();
    final refresh = await SecureStorage.getRefreshToken();
    if (access == null || access.isEmpty) {
      throw const MfaFailure(MfaFailureKind.notAuthenticated);
    }
    if (_client.auth.currentSession?.accessToken == access) return;
    try {
      await _client.auth.setSession(refresh ?? '', accessToken: access);
    } catch (e) {
      AppLogger.w('[MFA] session restore failed: $e');
      throw mfaFailureFrom(e);
    }
    await persistRotatedTokens();
  }

  @override
  Future<void> persistRotatedTokens() async {
    try {
      final session = _client.auth.currentSession;
      if (session == null) return;
      final stored = await SecureStorage.getAccessToken();
      if (stored == session.accessToken) return;
      await SecureStorage.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
      );
    } catch (e) {
      AppLogger.w('[MFA] token sync failed: $e');
    }
  }

  @override
  Future<MfaStatus> status() async {
    await _ensureSession();
    try {
      // `getUser()` (GET /user) ay nagbabalik ng `factors` nang WALANG
      // refreshSession — kaya hindi nito niro-rotate ang refresh token na
      // hawak ng app.
      final response = await _client.auth.getUser();
      final factors = response.user?.factors ?? const <Factor>[];
      final verified = <MfaFactor>[];
      final unverified = <MfaFactor>[];
      for (final factor in factors) {
        if (factor.factorType != FactorType.totp) continue;
        final mapped = MfaFactor(
          id: factor.id,
          friendlyName: factor.friendlyName ?? 'Authenticator app',
          state: factor.status == FactorStatus.verified
              ? MfaFactorState.verified
              : MfaFactorState.unverified,
          createdAt: factor.createdAt,
        );
        if (mapped.isVerified) {
          verified.add(mapped);
        } else {
          unverified.add(mapped);
        }
      }
      final level = _client.auth.mfa.getAuthenticatorAssuranceLevel();
      return MfaStatus(
        verifiedFactors: verified,
        unverifiedFactors: unverified,
        assurance: MfaAssurance(
          currentLevel: level.currentLevel?.name,
          nextLevel: level.nextLevel?.name,
        ),
      );
    } catch (e) {
      throw mfaFailureFrom(e);
    }
  }

  @override
  Future<MfaEnrollment> enrollTotp({String? friendlyName}) async {
    await _ensureSession();
    try {
      final response = await _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: issuer,
        friendlyName: friendlyName,
      );
      final totp = response.totp;
      return MfaEnrollment(
        factorId: response.id,
        manualKey: totp?.secret ?? '',
        qrSvg: mfaQrSvgFromDataUri(totp?.qrCode),
        otpauthUri: totp?.uri,
      );
    } catch (e) {
      throw mfaFailureFrom(e);
    }
  }

  @override
  Future<String> challenge(String factorId) async {
    try {
      final response = await _client.auth.mfa.challenge(factorId: factorId);
      return response.id;
    } catch (e) {
      throw mfaFailureFrom(e);
    }
  }

  @override
  Future<void> verify({
    required String factorId,
    required String challengeId,
    required String code,
  }) async {
    try {
      await _client.auth.mfa.verify(
        factorId: factorId,
        challengeId: challengeId,
        code: code,
      );
    } catch (e) {
      throw mfaFailureFrom(e);
    }
  }

  @override
  Future<void> unenroll(String factorId) async {
    try {
      await _client.auth.mfa.unenroll(factorId);
    } catch (e) {
      throw mfaFailureFrom(e);
    }
  }
}

/// Ang SVG markup ng QR code na galing sa GoTrue. Dalawang hugis ang
/// tinatanggap (inline `utf-8,` at `base64,`); `null` kapag hindi SVG ang
/// nilalaman — sa ganoong kaso ang manual setup key ang ipapakita.
String? mfaQrSvgFromDataUri(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final comma = raw.indexOf(',');
  if (comma < 0) return null;
  final meta = raw.substring(0, comma);
  final payload = raw.substring(comma + 1);
  String? svg;
  if (meta.contains('base64')) {
    try {
      svg = utf8.decode(base64Decode(payload));
    } catch (_) {
      svg = null;
    }
  } else {
    try {
      final decoded = Uri.decodeComponent(payload);
      svg = decoded.contains('<svg') ? decoded : payload;
    } catch (_) {
      svg = payload;
    }
  }
  if (svg == null || !svg.contains('<svg')) return null;
  return svg;
}

/// Isinasalin ang (mga) error ng Supabase Auth sa [MfaFailure].
///
/// Ang nilalaman ng [AuthException.message] ay HINDI kailanman ipinapasa sa UI
/// — fixed na mensahe lang ang nasa [MfaFailure] para walang hilaw na server
/// text (o anumang detalyeng galing sa enrollment) na makalabas sa screen,
/// logs, o snackbar.
MfaFailure mfaFailureFrom(Object error) {
  if (error is MfaFailure) return error;

  if (error is AuthException) {
    final code = error.code;
    final status = error.statusCode;
    switch (code) {
      case 'mfa_verification_failed':
      case 'mfa_verification_rejected':
        return const MfaFailure(MfaFailureKind.invalidCode);
      case 'mfa_challenge_expired':
        return const MfaFailure(MfaFailureKind.expiredChallenge);
      case 'mfa_factor_not_found':
        return const MfaFailure(MfaFailureKind.notEnrolled);
      case 'too_many_enrolled_mfa_factors':
        return const MfaFailure(MfaFailureKind.alreadyEnrolled);
      case 'insufficient_aal':
        return const MfaFailure(MfaFailureKind.insufficientAssurance);
      case 'mfa_totp_enroll_not_enabled':
      case 'mfa_totp_verify_not_enabled':
        return const MfaFailure(MfaFailureKind.unavailable);
      case 'session_missing':
      case 'session_expired':
      case 'bad_jwt':
        return const MfaFailure(MfaFailureKind.notAuthenticated);
      case 'over_request_rate_limit':
      case 'over_sms_send_rate_limit':
        return const MfaFailure(MfaFailureKind.tooManyAttempts);
      default:
        break;
    }
    if (status == '429') {
      return const MfaFailure(MfaFailureKind.tooManyAttempts);
    }
    if (status == '401' || status == '403') {
      return const MfaFailure(MfaFailureKind.notAuthenticated);
    }
    return const MfaFailure(MfaFailureKind.server);
  }

  if (error is AuthRetryableFetchException) {
    return const MfaFailure(MfaFailureKind.network);
  }

  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection') ||
      text.contains('timeout') ||
      text.contains('xmlhttprequest')) {
    return const MfaFailure(MfaFailureKind.network);
  }
  return const MfaFailure(MfaFailureKind.server);
}
