import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Result of one remote command execution.
class SshExecResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const SshExecResult({required this.exitCode, required this.stdout, required this.stderr});

  bool get ok => exitCode == 0;
}

/// Thin seam between [VpsSetupService]'s step sequencing/idempotency logic
/// and the actual SSH transport. Exists so that logic can be unit-tested
/// with a fake instead of a real network connection - this sandbox (and
/// most CI) has no real VPS to SSH into.
abstract class SshTransport {
  Future<SshExecResult> exec(String command);

  /// Uploads [content] to [remotePath] via SFTP, then `chmod`s it via a
  /// plain exec rather than SFTP's own attribute-setting API - simpler and
  /// avoids needing to construct SFTP file-mode bitmasks correctly.
  Future<void> uploadFile(String remotePath, Uint8List content, {String? chmod});

  Future<void> close();
}

/// Real implementation, backed by package:dartssh2.
class Dartssh2Transport implements SshTransport {
  final SSHClient _client;

  Dartssh2Transport._(this._client);

  /// Connects and authenticates with a pasted PEM private key. Host key
  /// verification is intentionally left to dartssh2's default (accept any
  /// key) for now - this is a brand-new VPS the user is bootstrapping for
  /// the first time, so there is no known-hosts entry to check against yet;
  /// TOFU-pinning the key for future reconnects is a reasonable follow-up,
  /// not something to block first-run setup on.
  static Future<Dartssh2Transport> connect({
    required String host,
    required int port,
    required String username,
    required String privateKeyPem,
    String? passphrase,
  }) async {
    final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 15));
    final client = SSHClient(
      socket,
      username: username,
      identities: SSHKeyPair.fromPem(privateKeyPem, passphrase),
    );
    await client.authenticated;
    return Dartssh2Transport._(client);
  }

  @override
  Future<SshExecResult> exec(String command) async {
    final session = await _client.execute(command);
    final stdoutFuture = utf8.decoder.bind(session.stdout).join();
    final stderrFuture = utf8.decoder.bind(session.stderr).join();
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    final exitCode = await session.waitForExit(timeout: const Duration(minutes: 10)) ?? -1;
    return SshExecResult(exitCode: exitCode, stdout: stdout, stderr: stderr);
  }

  @override
  Future<void> uploadFile(String remotePath, Uint8List content, {String? chmod}) async {
    final sftp = await _client.sftp();
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    await file.writeBytes(content);
    await file.close();
    if (chmod != null) {
      final result = await exec('chmod $chmod ${_shellQuote(remotePath)}');
      if (!result.ok) {
        throw SshTransportException('chmod $chmod on $remotePath failed: ${result.stderr}');
      }
    }
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}

String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

class SshTransportException implements Exception {
  final String message;
  const SshTransportException(this.message);
  @override
  String toString() => message;
}
