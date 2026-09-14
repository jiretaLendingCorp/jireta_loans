// lib/core/security/device_auth_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/error_codes.dart' as local_auth_error;
import 'package:local_auth/local_auth.dart';

import '../utils/logger.dart';

/// Resulta ng device credential authentication.
///
/// Ang app ay tumatanggap LANG ng success/failure mula sa OS — hindi nito
/// kailanman binabasa, iniimbak, o ipinapadala ang device PIN/password o ang
/// biometric data ng lender.
enum DeviceAuthOutcome {
  /// Na-verify ng OS (biometric, o device PIN/password fallback).
  success,

  /// Kinansela ng user, hindi tumugma, o naka-lock out — hindi natuloy.
  failed,

  /// Walang naka-set up na biometric / device credential sa device.
  unavailable,

  /// Hindi sinusuportahan ng platform (halimbawa: web build).
  unsupported,
}

/// Wrapper sa paligid ng `local_auth` para sa device credential
/// authentication (fingerprint / Face ID, at device PIN/password bilang
/// fallback).
class DeviceAuthService {
  DeviceAuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True kapag may device credential (biometric o PIN/password) na pwedeng
  /// gamitin sa device na ito.
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      final deviceSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return deviceSupported || canCheck;
    } catch (e) {
      AppLogger.w('[DeviceAuth] isAvailable failed: $e');
      return false;
    }
  }

  /// Humihingi ng device credential authentication (fingerprint / Face ID, o
  /// device PIN/password) bago ang isang submission.
  ///
  /// Ang `biometricOnly: false` sa [_authenticate] ang dahilan kung bakit
  /// pinapayagan ang device PIN/password bilang fallback. Kapag WALANG
  /// naka-set na credential sa phone, [DeviceAuthOutcome.unavailable] ang
  /// isinasagot — doon pumapasok ang app-level MPIN (tingnan ang
  /// `SubmissionGuard`).
  Future<DeviceAuthOutcome> authenticate({required String reason}) =>
      _authenticate(reason: reason);

  Future<DeviceAuthOutcome> _authenticate({required String reason}) async {
    if (kIsWeb) return DeviceAuthOutcome.unsupported;
    try {
      final deviceSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!deviceSupported && !canCheck) {
        return DeviceAuthOutcome.unavailable;
      }
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // PIN/password fallback: huwag ipilit ang biometric-only.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      return ok ? DeviceAuthOutcome.success : DeviceAuthOutcome.failed;
    } on PlatformException catch (e) {
      AppLogger.w('[DeviceAuth] PlatformException ${e.code}: ${e.message}');
      switch (e.code) {
        case local_auth_error.notAvailable:
        case local_auth_error.notEnrolled:
        case local_auth_error.passcodeNotSet:
          return DeviceAuthOutcome.unavailable;
        default:
          return DeviceAuthOutcome.failed;
      }
    } catch (e, st) {
      AppLogger.e('[DeviceAuth] authentication failed', e, st);
      return DeviceAuthOutcome.failed;
    }
  }
}

/// Mensaheng ipinapakita kapag hindi natuloy ang authentication dahil hindi
/// ito available sa device (hindi kasalanan ng user).
const String kDeviceAuthUnavailableMessage =
    'Hindi available ang device verification sa phone na ito. Mag-set up ng '
    'fingerprint, Face ID, o device PIN sa Settings at subukan ulit.';

/// Mensaheng ipinapakita kapag kinansela / hindi tumugma ang verification.
const String kDeviceAuthFailedMessage =
    'Hindi na-verify ang iyong pagkakakilanlan. Hindi natuloy ang aksyon.';

final deviceAuthServiceProvider = Provider<DeviceAuthService>(
  (ref) => DeviceAuthService(),
);
