// test/mpin_persist_test.dart
//
// Debug tests para sa MPIN lock ng rider / lender:
//   * dapat HINDI mawala ang MPIN kapag natapos ang session (logout / expired /
//     na-clear ang lahat ng session key), at
//   * ang natandaang numero + role ay dapat manatili, para ang "Enter MPIN"
//     screen (na may switch number) pa rin ang lumabas — hindi ang OTP form.
//
// Gumagamit ng in-memory na platform storage (`setMockInitialValues`), kaya
// pareho ang storage na nakikita ng `SecureStorage` at ng `MpinService`.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/security/mpin_login_gate.dart';
import 'package:jireta_loans/core/security/mpin_service.dart';
import 'package:jireta_loans/core/security/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Simula sa malinis na device.
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('hindi nawawala ang MPIN pagkatapos ng logout / expired session',
      () async {
    // 1) OTP login bilang lender → naitala ang numero at ang owner.
    await SecureStorage.saveUserInfo(userId: 'u-1', role: 'lender');
    await SecureStorage.saveLoginPhone('09171234567');
    await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'lender');

    // 2) Nag-set ng MPIN.
    final service = MpinService();
    await service.setMpin('1234');
    expect(await service.isSet(), isTrue);

    // 3) Natapos ang session: binura ang lahat ng session key (walang userId,
    //    walang role, walang tokens) — ito ang nangyayari sa logout at sa
    //    expired/revoked session.
    await SecureStorage.clearAll();
    expect(await SecureStorage.getUserId(), isNull);
    expect(await SecureStorage.getUserRole(), isNull);

    // 4) Ang MPIN screen ay nakasalalay sa tatlong bagay na ito:
    //    (a) natandaang numero — para sa switch number sa screen;
    //    (b) owner role — para malaman na rider/lender pa rin ito;
    //    (c) ang MPIN mismo.
    expect(await SecureStorage.getLoginPhone(), '09171234567',
        reason: 'Dapat hindi binubura ng clearAll ang natandaang numero');
    expect(await SecureStorage.getLoginOwnerRole(), 'lender',
        reason: 'Dapat hindi binubura ng clearAll ang owner role');
    expect(await service.isSet(), isTrue,
        reason: 'Dapat mahanap pa rin ang MPIN kahit wala nang session keys');
    expect((await service.verify('1234')).status, MpinStatus.success,
        reason: 'Dapat pa ring gumana ang MPIN pagkatapos mag-expire');
  });

  test('mahanap pa rin ang MPIN kahit wala pang owner record (lumang install)',
      () async {
    // Lumang install: may MPIN na (scope = user id) at may natandaang numero,
    // pero walang owner record dahil wala pa ito noong panahon na iyon.
    await SecureStorage.saveUserInfo(userId: 'u-9', role: 'rider');
    await SecureStorage.saveLoginPhone('09181234567');
    final service = MpinService();
    await service.setMpin('4321');

    // Nawala ang session keys pero HINDI ang MPIN keys.
    await SecureStorage.clearAll();
    // Wala na rin ang owner (simulahin ang pinaka-lumang install).
    await SecureStorage.clearLoginOwner();

    expect(await service.isSet(), isTrue,
        reason: 'Dapat mahanap ang MPIN sa storage kahit walang userId/owner');
    expect((await service.verify('4321')).status, MpinStatus.success);
  });

  test('nabubura lang ang naka-lock na numero kapag pinili ang ibang numero',
      () async {
    await SecureStorage.saveUserInfo(userId: 'u-2', role: 'rider');
    await SecureStorage.saveLoginPhone('09171234567');
    await SecureStorage.saveLoginOwner(userId: 'u-2', role: 'rider');
    final service = MpinService();
    await service.setMpin('1234');

    // Ito ang ginagawa ng \"Use another number\" sa MPIN screen.
    await SecureStorage.clearLoginPhone();
    await SecureStorage.clearLoginOwner();

    expect(await SecureStorage.getLoginPhone(), isNull);
    expect(await SecureStorage.getLoginOwnerRole(), isNull);
    // Nananatili pa rin ang MPIN ng account (makikita ulit kapag nag-OTP muli).
    expect(await service.isSet(), isTrue);
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
      await MpinService().setMpin('1234');

      // ...tapos nag-logout: LOCK lang (nananatili ang tokens; natanggal lang
      // ang authenticated state). Ito ang takbo ng bagong logout.

      final choice = await MpinLoginGate().resolve();
      expect(choice.showMpin, isTrue,
          reason: 'Dapat MPIN screen, hindi ang Send OTP form');
      expect(choice.phone, '09171234567',
          reason: 'Dapat may numero para sa switch number sa MPIN screen');
    });

    test('OTP form kapag wala nang session (tunay na natapos/na-revoke)',
        () async {
      // May MPIN at numero pa — pero WALA nang tokens na maibabalik ng MPIN.
      // Sa ganoon, hindi dapat ipangako ng app ang MPIN na tiyak na bibigo.
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'lender');
      await MpinService().setMpin('1234');
      await SecureStorage.clearAll();
      await SecureStorage.clearLoginOwner();

      final choice = await MpinLoginGate().resolve();
      expect(choice.showMpin, isFalse);
    });

    test('MPIN screen kahit wala pang owner record (lumang install)', () async {
      await SecureStorage.saveUserInfo(userId: 'u-8', role: 'rider');
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await SecureStorage.saveLoginPhone('09181234567');
      await MpinService().setMpin('4321');
      // Nawala ang userId/role records pero nandiyan pa ang MPIN at tokens.
      await SecureStorage.clearAll();
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await SecureStorage.clearLoginOwner();

      final choice = await MpinLoginGate().resolve();
      expect(choice.showMpin, isTrue);
      expect(choice.phone, '09181234567');
    });

    test('OTP form kapag wala pang naka-set na MPIN', () async {
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'rider');

      final choice = await MpinLoginGate().resolve();
      expect(choice.showMpin, isFalse);
    });

    test('OTP form kapag walang natandaang numero', () async {
      await SecureStorage.saveUserInfo(userId: 'u-1', role: 'rider');
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await MpinService().setMpin('1234');

      final choice = await MpinLoginGate().resolve();
      expect(choice.showMpin, isFalse);
    });

    test('OTP form kapag staff ang naka-record', () async {
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'rider');
      await MpinService().setMpin('1234');
      // Naka-log in na ngayon ang isang staff sa parehong device.
      await SecureStorage.saveUserInfo(userId: 'u-9', role: 'head_manager');

      final choice = await MpinLoginGate().resolve();
      expect(choice.showMpin, isFalse);
    });

    test('OTP form pagkatapos ng "Use another number"', () async {
      await SecureStorage.saveTokens(
          accessToken: 'a-token', refreshToken: 'r-token');
      await SecureStorage.saveLoginPhone('09171234567');
      await SecureStorage.saveLoginOwner(userId: 'u-1', role: 'rider');
      await MpinService().setMpin('1234');

      await SecureStorage.clearLoginPhone();
      await SecureStorage.clearLoginOwner();

      final choice = await MpinLoginGate().resolve();
      expect(choice.showMpin, isFalse);
    });
  });

  test('clear() ay nag-aalis ng MPIN at ng last-scope pointer', () async {
    await SecureStorage.saveUserInfo(userId: 'u-3', role: 'rider');
    final service = MpinService();
    await service.setMpin('1234');
    expect(await service.isSet(), isTrue);

    await service.clear();
    expect(await service.isSet(), isFalse);

    // Kahit walang userId, hindi na rin dapat makahanap ng MPIN pagkatapos ng
    // clear — wala na kasing natitirang hash.
    await SecureStorage.clearAll();
    expect(await service.isSet(), isFalse);
  });
}
