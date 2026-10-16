// test/mfa_service_test.dart
//
// Tests para sa Google Authenticator (TOTP) 2FA service.
//
// Ang `MfaGateway` (ang tanging bahagi na humahawak ng network / Supabase Auth)
// ay pinapalitan ng in-memory na `_FakeMfaGateway`, kaya nasusubukan dito ang
// buong logic nang walang network:
//
//   * enrollment → verify → 2FA ON; kansela → nalilinis ang unverified factor;
//   * maling / expired na code → tamang [MfaFailureKind] (walang pag-verify);
//   * disable → KAILANGAN muna ng tamang code (reauthentication) bago ang
//     `unenroll`;
//   * ang `aal` claim ng token ang patunay — walang local na boolean.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:jireta_loans/core/security/mfa_service.dart';

/// In-memory na kapalit ng Supabase Auth MFA API.
class _FakeMfaGateway implements MfaGateway {
  _FakeMfaGateway({
    this.currentLevel = 'aal1',
    List<String> verified = const [],
    List<String> unverified = const [],
  })  : verifiedIds = [...verified],
        unverifiedIds = [...unverified];

  String currentLevel;
  List<String> verifiedIds;
  List<String> unverifiedIds;

  /// Naka-enroll na factor na hindi pa na-verify (galing sa `enrollTotp`).
  String? pendingFactorId;

  /// Ang inaasahang code. Ang lahat ng iba ay `invalidCode`.
  String expectedCode = '123456';

  /// Itatapon ng `verify` — para gayahin ang expired challenge / rate limit.
  Object? verifyError;

  int verifyCalls = 0;
  int challengeCalls = 0;
  int enrollCalls = 0;
  final List<String> unenrolled = [];
  int tokenSyncs = 0;

  @override
  Future<MfaStatus> status() async {
    return MfaStatus(
      verifiedFactors: [
        for (final id in verifiedIds)
          MfaFactor(
            id: id,
            friendlyName: 'Authenticator $id',
            state: MfaFactorState.verified,
          ),
      ],
      unverifiedFactors: [
        for (final id in unverifiedIds)
          MfaFactor(
            id: id,
            friendlyName: 'Authenticator $id',
            state: MfaFactorState.unverified,
          ),
      ],
      assurance: MfaAssurance(currentLevel: currentLevel, nextLevel: 'aal2'),
    );
  }

  @override
  Future<MfaEnrollment> enrollTotp({String? friendlyName}) async {
    enrollCalls++;
    pendingFactorId = 'factor-new';
    unverifiedIds.add('factor-new');
    return const MfaEnrollment(
      factorId: 'factor-new',
      manualKey: 'JBSWY3DPEHPK3PXP',
      qrSvg: '<svg></svg>',
      otpauthUri: 'otpauth://totp/Jireta?secret=JBSWY3DPEHPK3PXP',
    );
  }

  @override
  Future<String> challenge(String factorId) async {
    challengeCalls++;
    return 'challenge-1';
  }

  @override
  Future<void> verify({
    required String factorId,
    required String challengeId,
    required String code,
  }) async {
    verifyCalls++;
    if (verifyError != null) throw verifyError!;
    if (code != expectedCode) {
      throw const AuthException(
        'invalid code',
        statusCode: '422',
        code: 'mfa_verification_failed',
      );
    }
    unverifiedIds.remove(factorId);
    if (!verifiedIds.contains(factorId)) verifiedIds.add(factorId);
    // Ang matagumpay na verify ang nagpapataas ng session sa aal2.
    currentLevel = 'aal2';
  }

  @override
  Future<void> unenroll(String factorId) async {
    unenrolled.add(factorId);
    unverifiedIds.remove(factorId);
    verifiedIds.remove(factorId);
  }

  @override
  Future<void> persistRotatedTokens() async {
    tokenSyncs++;
  }
}

void main() {
  group('MfaService — code validation', () {
    test('6 na digit lang ang tinatanggap', () {
      expect(MfaService.isValidCode('123456'), isTrue);
      expect(MfaService.isValidCode('000000'), isTrue);
      expect(MfaService.isValidCode(' 654321 '), isTrue, reason: 'trim');
      expect(MfaService.isValidCode('12345'), isFalse);
      expect(MfaService.isValidCode('1234567'), isFalse);
      expect(MfaService.isValidCode('12345a'), isFalse);
      expect(MfaService.isValidCode(''), isFalse);
      expect(MfaService.isValidCode(null), isFalse);
    });
  });

  group('mfaChallengeRequired (purong pasya)', () {
    test('aal1 + may verified factor → kailangan ang challenge', () {
      expect(
        mfaChallengeRequired(currentLevel: 'aal1', verifiedFactorCount: 1),
        isTrue,
      );
    });

    test('aal2 → tapos na', () {
      expect(
        mfaChallengeRequired(currentLevel: 'aal2', verifiedFactorCount: 1),
        isFalse,
      );
    });

    test('walang verified factor → walang MFA (kahit aal1)', () {
      expect(
        mfaChallengeRequired(currentLevel: 'aal1', verifiedFactorCount: 0),
        isFalse,
      );
      expect(
        mfaChallengeRequired(currentLevel: null, verifiedFactorCount: 0),
        isFalse,
      );
    });

    test('walang aal claim (null) na may factor → kailangan pa rin', () {
      expect(
        mfaChallengeRequired(currentLevel: null, verifiedFactorCount: 1),
        isTrue,
      );
    });
  });

  group('MfaStatus', () {
    test('requiresChallenge kapag enrolled at aal1 pa', () async {
      final gateway = _FakeMfaGateway(verified: ['f1']);
      final status = await gateway.status();
      expect(status.enrolled, isTrue);
      expect(status.factorId, 'f1');
      expect(status.requiresChallenge, isTrue);
    });

    test('hindi na kailangan kapag aal2 na ang session', () async {
      final gateway = _FakeMfaGateway(verified: ['f1'], currentLevel: 'aal2');
      final status = await gateway.status();
      expect(status.requiresChallenge, isFalse);
    });
  });

  group('MfaService — enrollment', () {
    test('enroll → verify → 2FA ON at na-sync ang tokens', () async {
      final gateway = _FakeMfaGateway();
      final service = MfaService(gateway: gateway);

      final enrollment = await service.beginEnrollment();
      expect(enrollment.factorId, 'factor-new');
      expect(enrollment.manualKey, 'JBSWY3DPEHPK3PXP');
      expect(service.pendingFactorId, 'factor-new');

      await service.confirmEnrollment('123456');

      expect(gateway.verifyCalls, 1);
      expect(gateway.tokenSyncs, 1, reason: 'aal2 tokens ay isinasauli');
      expect(service.pendingFactorId, isNull);
      final after = await service.status();
      expect(after.enrolled, isTrue, reason: 'ON lang pagkatapos ng verify');
    });

    test('maling code → invalidCode, HINDI naka-enroll (pending pa rin)', () async {
      final gateway = _FakeMfaGateway();
      final service = MfaService(gateway: gateway);
      await service.beginEnrollment();

      await expectLater(
        service.confirmEnrollment('999999'),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaFailureKind.invalidCode)),
      );

      expect(service.pendingFactorId, 'factor-new');
      final status = await service.status();
      expect(status.enrolled, isFalse,
          reason: 'Hindi nagiging ON kahit may factor — hindi pa verified');
      expect(gateway.tokenSyncs, 0);
    });

    test('expired challenge → expiredChallenge (hindi fake na tagumpay)',
        () async {
      final gateway = _FakeMfaGateway()
        ..verifyError = const AuthException(
          'challenge expired',
          statusCode: '422',
          code: 'mfa_challenge_expired',
        );
      final service = MfaService(gateway: gateway);
      await service.beginEnrollment();

      await expectLater(
        service.confirmEnrollment('123456'),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaFailureKind.expiredChallenge)),
      );
    });

    test('invalid na hugis ng code → hindi tumatawag sa server', () async {
      final gateway = _FakeMfaGateway();
      final service = MfaService(gateway: gateway);
      await service.beginEnrollment();

      await expectLater(
        service.confirmEnrollment('12ab56'),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaFailureKind.invalidCode)),
      );
      expect(gateway.verifyCalls, 0);
    });

    test('kansela → inaalis ang hindi pa na-verify na factor', () async {
      final gateway = _FakeMfaGateway();
      final service = MfaService(gateway: gateway);
      await service.beginEnrollment();

      await service.cancelEnrollment();

      expect(gateway.unenrolled, ['factor-new']);
      expect(service.pendingFactorId, isNull);
      expect(gateway.verifyCalls, 0);
    });

    test('nililinis ang naiwang unverified factor bago mag-enroll', () async {
      final gateway = _FakeMfaGateway(unverified: ['leftover']);
      final service = MfaService(gateway: gateway);

      await service.beginEnrollment();

      expect(gateway.unenrolled, contains('leftover'));
      expect(gateway.enrollCalls, 1);
    });

    test('hindi na nag-e-enroll kung ON na ang 2FA', () async {
      final gateway = _FakeMfaGateway(verified: ['f1']);
      final service = MfaService(gateway: gateway);

      await expectLater(
        service.beginEnrollment(),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaFailureKind.alreadyEnrolled)),
      );
      expect(gateway.enrollCalls, 0);
    });
  });

  group('MfaService — login challenge', () {
    test('verifyLogin → challenge + verify + token sync', () async {
      final gateway = _FakeMfaGateway(verified: ['f1']);
      final service = MfaService(gateway: gateway);

      await service.verifyLogin(factorId: 'f1', code: '123456');

      expect(gateway.challengeCalls, 1);
      expect(gateway.verifyCalls, 1);
      expect(gateway.tokenSyncs, 1);
      expect(gateway.currentLevel, 'aal2');
    });

    test('maling code sa login → invalidCode (hindi pumapasa)', () async {
      final gateway = _FakeMfaGateway(verified: ['f1']);
      final service = MfaService(gateway: gateway);

      await expectLater(
        service.verifyLogin(factorId: 'f1', code: '111111'),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaFailureKind.invalidCode)),
      );
      expect(gateway.tokenSyncs, 0);
    });
  });

  group('MfaService — disable (reauthentication)', () {
    test('disable → verify muna (aal2) bago unenroll', () async {
      final gateway = _FakeMfaGateway(verified: ['f1']);
      final service = MfaService(gateway: gateway);

      await service.disable(code: '123456');

      expect(gateway.verifyCalls, 1, reason: 'kailangan ang code');
      expect(gateway.unenrolled, ['f1']);
      final after = await service.status();
      expect(after.enrolled, isFalse);
    });

    test('maling code → HINDI inaalis ang factor', () async {
      final gateway = _FakeMfaGateway(verified: ['f1']);
      final service = MfaService(gateway: gateway);

      await expectLater(
        service.disable(code: '000000'),
        throwsA(isA<MfaFailure>()),
      );
      expect(gateway.unenrolled, isEmpty,
          reason: 'Protektado ang factor laban sa basta-bastang pag-disable');
    });

    test('walang factor → notEnrolled (walang ipagbabawal)', () async {
      final gateway = _FakeMfaGateway(verified: ['f1']);
      final service = MfaService(gateway: gateway);
      await service.disable(code: '123456');

      await expectLater(
        service.disable(code: '123456'),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaFailureKind.notEnrolled)),
      );
    });

    test('rate limited (429) → tooManyAttempts na may mensahe', () async {
      final gateway = _FakeMfaGateway(verified: ['f1'])
        ..verifyError = const AuthException(
          'over request rate limit',
          statusCode: '429',
          code: 'over_request_rate_limit',
        );
      final service = MfaService(gateway: gateway);

      await expectLater(
        service.disable(code: '123456'),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaFailureKind.tooManyAttempts)
            .having((e) => e.message.toLowerCase(),
                'message mentions waiting', contains('wait'))),
      );
    });
  });

  group('mfaFailureFrom (error mapping)', () {
    test('mga GoTrue code → tamang uri', () {
      expect(
        mfaFailureFrom(const AuthException('x',
                statusCode: '422', code: 'mfa_verification_failed'))
            .kind,
        MfaFailureKind.invalidCode,
      );
      expect(
        mfaFailureFrom(const AuthException('x',
                statusCode: '422', code: 'mfa_challenge_expired'))
            .kind,
        MfaFailureKind.expiredChallenge,
      );
      expect(
        mfaFailureFrom(const AuthException('x',
                statusCode: '404', code: 'mfa_factor_not_found'))
            .kind,
        MfaFailureKind.notEnrolled,
      );
      expect(
        mfaFailureFrom(const AuthException('x',
                statusCode: '403', code: 'insufficient_aal'))
            .kind,
        MfaFailureKind.insufficientAssurance,
      );
      expect(
        mfaFailureFrom(const AuthException('x',
                statusCode: '403', code: 'mfa_totp_enroll_not_enabled'))
            .kind,
        MfaFailureKind.unavailable,
      );
      expect(
        mfaFailureFrom(const AuthException('x', statusCode: '401'))
            .kind,
        MfaFailureKind.notAuthenticated,
      );
      expect(
        mfaFailureFrom(Exception('SocketException: failed host lookup')).kind,
        MfaFailureKind.network,
      );
    });

    test('ang mensahe ay HINDI naglalaman ng hilaw na server text', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final failure = mfaFailureFrom(
        const AuthException(
          'payload leak $secret',
          statusCode: '500',
          code: 'unexpected_failure',
        ),
      );
      expect(failure.message.contains(secret), isFalse);
      expect(failure.message.toLowerCase().contains('auth'), isFalse);
      expect(failure.message, 'Something went wrong while verifying. Please '
          'try again.');
    });

    test('idempotent sa MfaFailure', () {
      const failure = MfaFailure(MfaFailureKind.invalidCode);
      expect(identical(mfaFailureFrom(failure), failure), isTrue);
    });
  });

  group('mfaQrSvgFromDataUri', () {
    test('utf-8 na data URI', () {
      final svg = mfaQrSvgFromDataUri(
        'data:image/svg+xml;utf-8,<svg xmlns="x"></svg>',
      );
      expect(svg, '<svg xmlns="x"></svg>');
    });

    test('base64 na data URI', () {
      final svg = mfaQrSvgFromDataUri(
        'data:image/svg+xml;base64,PHN2ZyB4bWxucz0ieCI+PC9zdmc+',
      );
      expect(svg, '<svg xmlns="x"></svg>');
    });

    test('hindi SVG → null (manual key ang fallback)', () {
      expect(mfaQrSvgFromDataUri('blah'), isNull);
      expect(mfaQrSvgFromDataUri(''), isNull);
      expect(mfaQrSvgFromDataUri(null), isNull);
      expect(mfaQrSvgFromDataUri('data:text/plain,hello'), isNull);
    });
  });

  group('LoginMfaInfo (server login response)', () {
    test('binabasa ang enabled + factors', () {
      final info = LoginMfaInfo.fromLoginResponse({
        'enabled': true,
        'factors': [
          {'id': 'f1', 'friendly_name': 'Authenticator 2026-10-16'},
        ],
      });
      expect(info.enabled, isTrue);
      expect(info.serverSaysRequired, isTrue);
      expect(info.factorId, 'f1');
      expect(info.friendlyName, 'Authenticator 2026-10-16');
    });

    test('enabled=false (walang 2FA) → hindi ipinipilit', () {
      final info = LoginMfaInfo.fromLoginResponse({
        'enabled': false,
        'factors': const [],
      });
      expect(info.enabled, isFalse);
      expect(info.serverSaysRequired, isFalse);
    });

    test('enabled=null (hindi matukoy) → fallback ang app', () {
      final info = LoginMfaInfo.fromLoginResponse({'enabled': null});
      expect(info.enabled, isNull);
      expect(info.serverSaysRequired, isFalse);
      expect(const LoginMfaInfo.unknown().enabled, isNull);
    });

    test('hindi valid na hugis → unknown (hindi naghuhulog)', () {
      expect(LoginMfaInfo.fromLoginResponse(null).enabled, isNull);
      expect(LoginMfaInfo.fromLoginResponse('nope').enabled, isNull);
      expect(LoginMfaInfo.fromLoginResponse({}).enabled, isNull);
    });
  });
}
