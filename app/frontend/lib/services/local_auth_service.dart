import 'package:local_auth/local_auth.dart';

/// Gates access to something sensitive (here: reading back a remembered
/// SSH private key) behind an OS-level re-auth prompt - biometric,
/// falling back to the device PIN/password/pattern since not every
/// device has biometrics enrolled. Covers Android, macOS (Touch ID via
/// local_auth_darwin), and Windows (Windows Hello via
/// local_auth_windows). There's no official Linux backend and this
/// project has no iOS platform directory, so those aren't covered.
///
/// If the platform can't do this at all (no Linux backend, or a device
/// with nothing enrolled anywhere), [authenticate] returns true rather
/// than permanently locking the user out of their own saved data - this
/// is a best-available extra protection layered on top of
/// flutter_secure_storage, not a hard requirement, and today there is no
/// gate at all, so this can only add protection, never remove
/// functionality that already exists.
class LocalAuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> authenticate(String reason) async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported && !canCheck) return true;

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      // Any platform/plugin error (unsupported platform, no channel
      // implementation, etc.) - degrade to "allow" for the same reason
      // as the unsupported-platform case above.
      return true;
    }
  }
}
