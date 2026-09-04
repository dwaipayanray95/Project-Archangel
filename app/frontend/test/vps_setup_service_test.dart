import 'dart:convert';
import 'dart:typed_data';

import 'package:archangel/services/pairing_bundle.dart';
import 'package:archangel/services/ssh_transport.dart';
import 'package:archangel/services/vps_setup_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every command run against it and returns a canned response for
/// the first pattern that matches, or [defaultResult] otherwise - lets
/// tests drive VpsSetupService's step sequencing and idempotency branches
/// without a real SSH connection (there is no real VPS reachable from
/// this sandbox or most CI).
class FakeSshTransport implements SshTransport {
  FakeSshTransport({
    this.responses = const [],
    this.defaultResult = const SshExecResult(exitCode: 0, stdout: '', stderr: ''),
  });

  final List<(Pattern, SshExecResult)> responses;
  final SshExecResult defaultResult;
  final List<String> commands = [];
  final List<String> uploadedPaths = [];

  @override
  Future<SshExecResult> exec(String command) async {
    commands.add(command);
    for (final (pattern, result) in responses) {
      if (pattern.allMatches(command).isNotEmpty) return result;
    }
    return defaultResult;
  }

  @override
  Future<void> uploadFile(String remotePath, Uint8List content, {String? chmod}) async {
    uploadedPaths.add(remotePath);
  }

  @override
  Future<void> close() async {}
}

String _fakeBundle({String name = 'test-device'}) {
  final json = jsonEncode({
    'v': 1,
    'name': name,
    'host': '10.10.0.1:8443',
    'token': 'fake-token',
    'wg': {
      'private_key': 'GPLAdSTwb62KTxFDQ9RWqFquMDiYk86x2JCseVWim3g=',
      'address': '10.10.0.5/32',
      'server_public_key': 'GMKWMzRzH7n3dk22dO/+lhCmyC0dAkwfdWCuRXd6MQA=',
      'endpoint': '203.0.113.5:51820',
      'allowed_ips': ['10.10.0.1/32'],
    },
  });
  return base64.encode(utf8.encode(json));
}

const _config = VpsSetupConfig(deviceName: 'test-device');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VpsSetupService.run', () {
    test('skips WireGuard setup when wg0.conf already exists', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
        (RegExp(r'test -f /etc/wireguard/wg0.conf'), const SshExecResult(exitCode: 0, stdout: '', stderr: '')),
        (RegExp(r'ifconfig.me'), const SshExecResult(exitCode: 0, stdout: '203.0.113.5', stderr: '')),
        (RegExp(r'archangeld pair'), SshExecResult(exitCode: 0, stdout: _fakeBundle(), stderr: '')),
      ]);
      final service = VpsSetupService(ssh);

      await service.run(_config).toList();

      expect(ssh.commands.any((c) => c.contains('wireguard_setup.sh')), isFalse);
      expect(service.result.name, 'test-device');
    });

    test('runs WireGuard setup when wg0.conf is missing', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'aarch64', stderr: '')),
        (RegExp(r'test -f /etc/wireguard/wg0.conf'), const SshExecResult(exitCode: 1, stdout: '', stderr: '')),
        (RegExp(r'ifconfig.me'), const SshExecResult(exitCode: 0, stdout: '203.0.113.5', stderr: '')),
        (RegExp(r'archangeld pair'), SshExecResult(exitCode: 0, stdout: _fakeBundle(), stderr: '')),
      ]);
      final service = VpsSetupService(ssh);

      await service.run(_config).toList();

      expect(ssh.commands.any((c) => c.contains('wireguard_setup.sh')), isTrue);
    });

    test('does not overwrite an existing config.yaml', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
        (RegExp(r'test -f /etc/wireguard/wg0.conf'), const SshExecResult(exitCode: 0, stdout: '', stderr: '')),
        (RegExp(r'ifconfig.me'), const SshExecResult(exitCode: 0, stdout: '203.0.113.5', stderr: '')),
        (RegExp(r'test -f /etc/archangel/config.yaml'), const SshExecResult(exitCode: 0, stdout: '', stderr: '')),
        (RegExp(r'archangeld pair'), SshExecResult(exitCode: 0, stdout: _fakeBundle(), stderr: '')),
      ]);
      final service = VpsSetupService(ssh);

      await service.run(_config).toList();

      expect(ssh.uploadedPaths.any((p) => p.endsWith('config.yaml')), isFalse);
      expect(ssh.commands.any((c) => c.contains('mv') && c.contains('/etc/archangel/config.yaml')), isFalse);
    });

    test('never lets a malicious wgSubnet value execute as a second command', () async {
      // Regression test for a real bug: config.yaml's content used to be
      // spliced into a quoted heredoc sent as one shell command. A
      // wgSubnet value containing a line that read exactly the heredoc's
      // delimiter would terminate it early and run whatever followed as
      // a second, arbitrary command - as root, since every command here
      // runs via sudo. config.yaml is now written via SFTP (uploadFile)
      // instead, which can't be broken out of this way; the wizard's own
      // UI also validates wgSubnet before it ever reaches this service,
      // but this test proves the service itself is safe even if that
      // validation were bypassed.
      const marker = 'pwned-marker-file';
      final maliciousConfig = VpsSetupConfig(
        deviceName: 'test-device',
        wgSubnet: "10.10.0\nCONF\ntouch /tmp/$marker\n#",
      );
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
        (RegExp(r'test -f /etc/wireguard/wg0.conf'), const SshExecResult(exitCode: 0, stdout: '', stderr: '')),
        (RegExp(r'ifconfig.me'), const SshExecResult(exitCode: 0, stdout: '203.0.113.5', stderr: '')),
        (RegExp(r'test -f /etc/archangel/config.yaml'), const SshExecResult(exitCode: 1, stdout: '', stderr: '')),
        (RegExp(r'archangeld pair'), SshExecResult(exitCode: 0, stdout: _fakeBundle(), stderr: '')),
      ]);
      final service = VpsSetupService(ssh);

      await service.run(maliciousConfig).toList();

      expect(
        ssh.commands.any((c) => c.contains(marker)),
        isFalse,
        reason: 'the malicious wgSubnet value must never be executed as a shell command',
      );
    });

    test('rejects an unsupported server architecture', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'sparc64', stderr: '')),
      ]);
      final service = VpsSetupService(ssh);

      await expectLater(
        service.run(_config),
        emitsThrough(emitsError(isA<VpsSetupException>())),
      );
    });

    test('rejects a non-Debian/Ubuntu server', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
        (RegExp(r'command -v apt-get'), const SshExecResult(exitCode: 1, stdout: '', stderr: '')),
      ]);
      final service = VpsSetupService(ssh);

      await expectLater(
        service.run(_config),
        emitsThrough(emitsError(isA<VpsSetupException>())),
      );
    });

    test('surfaces a failed pair call as an exception', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
        (RegExp(r'test -f /etc/wireguard/wg0.conf'), const SshExecResult(exitCode: 0, stdout: '', stderr: '')),
        (RegExp(r'ifconfig.me'), const SshExecResult(exitCode: 0, stdout: '203.0.113.5', stderr: '')),
        (RegExp(r'archangeld pair'), const SshExecResult(exitCode: 1, stdout: '', stderr: 'boom')),
      ]);
      final service = VpsSetupService(ssh);

      await expectLater(
        service.run(_config),
        emitsThrough(emitsError(isA<VpsSetupException>())),
      );
    });

    test('parses the pairing bundle and exposes it as result', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
        (RegExp(r'test -f /etc/wireguard/wg0.conf'), const SshExecResult(exitCode: 0, stdout: '', stderr: '')),
        (RegExp(r'ifconfig.me'), const SshExecResult(exitCode: 0, stdout: '203.0.113.5', stderr: '')),
        (RegExp(r'archangeld pair'), SshExecResult(exitCode: 0, stdout: _fakeBundle(name: 'my-mac'), stderr: '')),
      ]);
      final service = VpsSetupService(ssh);

      await service.run(_config).toList();

      final bundle = service.result;
      expect(bundle, isA<PairingBundle>());
      expect(bundle.name, 'my-mac');
      expect(bundle.host, '10.10.0.1:8443');
      expect(bundle.tunnel.peerEndpoint, '203.0.113.5:51820');
    });
  });

  group('VpsSetupService.updateBackend', () {
    test('backs up, downloads, restarts, and confirms via the health poll', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
      ]);
      final service = VpsSetupService(ssh);
      var polls = 0;

      final events = await service
          .updateBackend(
            targetVersion: '0.3.0',
            releaseTag: 'v0.3.0-b',
            githubRepoSlug: 'owner/repo',
            fetchLiveVersion: () async {
              polls++;
              return '0.3.0'; // "comes up correctly" on the first poll
            },
            pollInterval: Duration.zero,
          )
          .toList();

      expect(ssh.commands.any((c) => c.contains('cp -f /opt/archangel/archangeld /opt/archangel/archangeld.bak')), isTrue);
      expect(ssh.commands.any((c) => c.contains('releases/download/v0.3.0-b/archangeld-amd64')), isTrue);
      expect(ssh.commands.any((c) => c == 'sudo systemctl restart archangel'), isTrue);
      expect(polls, greaterThanOrEqualTo(1));
      expect(events.last.stage, 'restart');
      expect(events.last.stageComplete, isTrue);
    });

    test('rolls back automatically if the new version never comes up', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
      ]);
      final service = VpsSetupService(ssh);

      await expectLater(
        service.updateBackend(
          targetVersion: '0.3.0',
          releaseTag: 'v0.3.0-b',
          githubRepoSlug: 'owner/repo',
          // Health poll never reports the new version - simulates a
          // crash-looping or otherwise broken new binary.
          fetchLiveVersion: () async => '0.2.2',
          pollInterval: Duration.zero,
        ),
        emitsThrough(emitsError(isA<VpsSetupException>())),
      );

      expect(
        ssh.commands.any((c) => c.contains('mv -f /opt/archangel/archangeld.bak /opt/archangel/archangeld')),
        isTrue,
        reason: 'a failed post-update health check must restore the backup binary',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('fails without touching the live binary if the download does not report the expected version', () async {
      final ssh = FakeSshTransport(responses: [
        (RegExp(r'uname -m'), const SshExecResult(exitCode: 0, stdout: 'x86_64', stderr: '')),
        // Simulates the remote version-check failing inside the download
        // script (exit 1 before the `mv` that would install it).
        (RegExp(r'curl -fsSL'), const SshExecResult(exitCode: 1, stdout: '', stderr: "downloaded binary reports version '0.2.2', expected 0.3.0")),
      ]);
      final service = VpsSetupService(ssh);

      await expectLater(
        service.updateBackend(
          targetVersion: '0.3.0',
          releaseTag: 'v0.3.0-b',
          githubRepoSlug: 'owner/repo',
          fetchLiveVersion: () async => null,
        ),
        emitsThrough(emitsError(isA<VpsSetupException>())),
      );

      expect(ssh.commands.any((c) => c.contains('sudo systemctl restart archangel')), isFalse);
    });
  });
}
