// test/mpin_persist_test.dart
//
// Tests para sa MPIN lock ng rider / lender — ACCOUNT-level na ngayon:
//   * nasa SERVER (account) ang MPIN, kaya hindi ito nawawala kapag natapos
//     ang session (logout / expired / na-clear ang lahat ng session key),
//   * hindi na kailangang i-setup muli ang MPIN sa bagong device,
//   * ang natandaang numero + role ay dapat manatili, para ang "Enter MPIN"
//     screen (na may switch number) pa rin ang lumabas — hindi ang OTP form.
//
// Ang server ay pinalitan ng in-memory na `_FakeMpinServer`; naka-mock ang
// `FlutterSecureStorage` at `SharedPreferences` (`setMockInitialValues`).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/security/mpin_login_gate.dart';
import 'package:jireta_loans/core/security/mpin_service.dart';
import 'package:jireta_loans/core/security/secure_storage.dart';
import 'package:jireta_loans/data/datasources/remote/mpin_remote_datasource.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory na kapalit ng server (`auth-mpin` edge function). Sapat ito para
/// sa mga test na ito: isang PIN lang ang kailangan (`status` / `set` /
/// `reset`), at may `offline` switch para gayahin ang walang internet.
class _FakeMpinServer implements MpinRemoteDataSource {
  String? pin;
  bool offline = false;

  Never _noConnection() => throw StateError('offline (simulated)');

  @override
  Future<MpinStatusReply> status() async {
    if (offline) _noConnection();
    return MpinStatusReply(hasMpin: pin != null);
  }

  @override
  Future<MpinVerifyReply> verify(String mpin) async {
    if (offline) _noConnection();
    if (pin == null) return const MpinVerifyReply(MpinVerifyOutcome.notSet);
    return mpin == pin
        ? const MpinVerifyReply(MpinVerifyOutcome.success)
        : const MpinVerifyReply(MpinVerifyOutcome.wrong, attemptsLeft: 2);
  }

  @override
  Future<MpinSetReply> setMpin({
    required String mpin,
    String? currentMpin,
  }) async {
    if (offline) _noConnection();
    pin = mpin;
    return const MpinSetReply(saved: true);
  }

  @override
  Future<void> reset() async {
    if (offline) _noConnection();
    pin = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeMpinServer server;

  setUp(() {
    // Simula sa malinis na device.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    server = _FakeMpinServer();
  });

  MpinService service() => MpinService(ds: server);

  test('hindi nawawala ang MPIN pagkatapos ng logout / expired session',
      () async {
    // 1) OTP login bilang lender → naitala ang numero at ang owner.
    await SecureStorage.saveUserInfo(userId: 'u-1', role: 'lender');
    await SecureStorage.saveLoginPhone('09171234567');
    await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'lender');

    // 2) Nag-set ng MPIN — nasa ACCOUNT ito ngayon (server).
    await service().setMpin('1234');
    expect(await service().isSet(), isTrue);

    // 3) Natapos ang session: binura ang lahat ng session key (walang userId,
    //    walang role, walang tokens) — ito ang nangyayari sa logout at sa
    //    expired/revoked session.
    await SecureStorage.clearAll();
    expect(await SecureStorage.getUserId(), isNull);
    expect(await SecureStorage.getUserRole(), isNull);

    // 4) Ang MPIN screen ay nakasalalay sa tatlong bagay na ito:
    //    (a) natandaang numero — para sa switch number sa screen;
    //    (b) owner role — para malaman na rider/lender pa rin ito;
    //    (c) ang MPIN ng ACCOUNT (server).
    expect(await SecureStorage.getLoginPhone(), '09171234567',
        reason: 'Dapat hindi binubura ng clearAll ang natandaang numero');
    expect(await SecureStorage.getLoginOwnerRole(), 'lender',
        reason: 'Dapat hindi binubura ng clearAll ang owner role');
    expect(await service().isSet(), isTrue,
        reason: 'Nasa account (server) ang MPIN — hindi ito nawawala');
    expect((await service().verify('1234')).status, MpinStatus.success,
        reason: 'Dapat pa ring gumana ang MPIN pagkatapos mag-expire');
  });

  test(
      'ACCOUNT-level: bagong device → hindi na kailangang i-setup muli ang MPIN',
      () async {
    // Bagong phone (wala pang local na kahit ano) na may parehong account:
    // nag-OTP login, kaya nalaman ang numero.
    await SecureStorage.saveLoginPhone('09171234567');
    await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'lender');
    server.pin = '1234'; // naka-set na ito sa account mula sa lumang device

    // Walang lokal na MPIN hash — hindi iyon kailangan ngayon.
    expect(await service().isSet(), isTrue);
    expect((await service().verify('1234')).isSuccess, isTrue);

    // At ang login page ay MPIN pa rin ang ipapakita.
    final choice = await MpinLoginGate(mpin: service()).resolve();
    expect(choice.showMpin, isTrue);
  });

  test('nabubura lang ang naka-lock na numero kapag pinili ang ibang numero',
      () async {
    await SecureStorage.saveUserInfo(userId: 'u-2', role: 'rider');
    await SecureStorage.saveLoginPhone('09171234567');
    await SecureStorage.saveLoginOwner(userId: 'u-2', role: 'rider');
    await service().setMpin('1234');

    // Ito ang ginagawa ng "Use another number" sa MPIN screen.
    await SecureStorage.clearLoginPhone();
    await SecureStorage.clearLoginOwner();

    expect(await SecureStorage.getLoginPhone(), isNull);
    expect(await SecureStorage.getLoginOwnerRole(), isNull);
    // Nananatili pa rin ang MPIN ng account (makikita ulit kapag nag-OTP muli).
    expect(await service().isSet(), isTrue);
  });

  group('MpinLoginGate (alin ang lalabas sa login page)', () {
    test('MPIN screen pagkatapos LOCK ("logout") — bukas pa ang session',
        () async {
      // Nag-log in gamit ang OTP, nag-set ng MPIN...
      await SecureStorage.saveUserInfo(userId: 'u-1', role: 'lender');
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'lender');
      await service().setMpin('1234');

      // ...tapos nag-logout: LOCK lang (nananatili ang tokens; natanggal lang
      // ang authenticated state). Ito ang takbo ng bagong logout.

      final choice = await MpinLoginGate(mpin: service()).resolve();
      expect(choice.showMpin, isTrue,
          reason: 'Dapat MPIN screen, hindi ang Send OTP form');
      expect(choice.phone, '09171234567',
          reason: 'Dapat may numero para sa switch number sa MPIN screen');
    });

    test('MPIN screen pa rin kahit wala nang session (na-expire / na-revoke)',
        () async {
      // May MPIN ang account at may natandaang numero — wala nang tokens na
      // maibabalik ng MPIN. Sa panuntunan, "Enter MPIN" pa rin ang unang
      // lalabas (hindi ang Send OTP form): ang MPIN screen mismo ang magsasabi
      // kapag hindi na ma-restore ang session.
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'lender');
      await service().setMpin('1234');
      await SecureStorage.clearAll();
      await SecureStorage.clearLoginOwner();

      final choice = await MpinLoginGate(mpin: service()).resolve();
      expect(choice.showMpin, isTrue,
          reason: 'Laging Enter MPIN basta may MPIN ang account');
      expect(choice.phone, '09171234567',
          reason: 'Kasama pa rin ang numero para sa switch number');
    });

    test('MPIN screen kahit OFFLINE, basta naka-cache na "may MPIN"', () async {
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'lender');
      await service().setMpin('1234'); // naka-cache ang hint
      server.offline = true;

      final choice = await MpinLoginGate(mpin: service()).resolve();
      expect(choice.showMpin, isTrue,
          reason: 'Ang local na hint (boolean lang) ang gabay kapag offline');
    });

    test('OTP form kapag wala pang MPIN ang account', () async {
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'rider');

      final choice = await MpinLoginGate(mpin: service()).resolve();
      expect(choice.showMpin, isFalse);
    });

    test('OTP form kapag OFFLINE at hindi pa alam kung may MPIN', () async {
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'rider');
      server.offline = true;

      final choice = await MpinLoginGate(mpin: service()).resolve();
      expect(choice.showMpin, isFalse,
          reason: 'Walang cache at walang server — huwag mag-imbento ng MPIN '
              'screen');
    });

    test('OTP form kapag walang natandaang numero', () async {
      await SecureStorage.saveUserInfo(userId: 'u-1', role: 'rider');
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await service().setMpin('1234');

      final choice = await MpinLoginGate(mpin: service()).resolve();
      expect(choice.showMpin, isFalse);
    });

    test('OTP form kapag staff ang naka-record', () async {
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'rider');
      await service().setMpin('1234');
      // Naka-log in na ngayon ang isang staff sa parehong device.
      await SecureStorage.saveUserInfo(userId: 'u-9', role: 'head_manager');

      final choice = await MpinLoginGate(mpin: service()).resolve();
      expect(choice.showMpin, isFalse);
    });

    test('OTP form pagkatapos ng "Use another number"', () async {
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'rider');
      await service().setMpin('1234');

      await SecureStorage.clearLoginPhone();
      await SecureStorage.clearLoginOwner();

      final choice = await MpinLoginGate(mpin: service()).resolve();
      expect(choice.showMpin, isFalse);
    });
  });

  test('clear() ay nag-aalis ng MPIN ng account', () async {
    await SecureStorage.saveUserInfo(userId: 'u-3', role: 'rider');
    await service().setMpin('1234');
    expect(await service().isSet(), isTrue);

    await service().clear();
    expect(await service().isSet(), isFalse);

    // Kahit walang userId, wala na ring MPIN na makikita.
    await SecureStorage.clearAll();
    expect(await service().isSet(), isFalse);
  });
}
