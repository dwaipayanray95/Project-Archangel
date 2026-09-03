import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'pairing_bundle.dart';
import 'ssh_transport.dart';

/// Configuration for one VPS bootstrap run. Defaults match
/// infra/scripts/wireguard_setup.sh and app/backend/deploy.sh so a wizard
/// run with defaults produces the exact same server state a human running
/// those scripts by hand would.
class VpsSetupConfig {
  /// First three octets of the WireGuard tunnel subnet - the server
  /// always takes .1.
  final String wgSubnet;
  final int wgPort;
  final int appPort;

  /// Name given to this device's WireGuard peer + archangeld token -
  /// shows up in `wg show` and the token store.
  final String deviceName;

  /// "owner/repo" on GitHub to fetch the archangeld release binary from -
  /// see .github/workflows/release-backend.yml.
  final String githubRepoSlug;

  const VpsSetupConfig({
    required this.deviceName,
    this.wgSubnet = '10.10.0',
    this.wgPort = 51820,
    this.appPort = 8443,
    this.githubRepoSlug = 'dwaipayanray95/Project-Archangel',
  });
}

/// One line of progress for the setup wizard's UI to render - a stage
/// name (for grouping into a step list) plus a message (either a
/// human-readable status line or raw remote command output).
class SetupProgress {
  final String stage;
  final String message;
  final bool stageComplete;

  const SetupProgress(this.stage, this.message, {this.stageComplete = false});
}

/// Thrown when a step fails outright (as opposed to being skipped for
/// idempotency reasons, which is not an error).
class VpsSetupException implements Exception {
  final String stage;
  final String message;
  const VpsSetupException(this.stage, this.message);
  @override
  String toString() => '[$stage] $message';
}

/// Bootstraps a fresh Ubuntu/Debian VPS into a fully working, paired
/// Archangel server over one SSH connection: replicates
/// infra/scripts/install-archangel.sh + app/backend/deploy.sh +
/// `archangeld pair`, in that order, ending with a parsed [PairingBundle]
/// ready to hand to [WireGuardController.pair] and
/// [ArchangeldConnection.pair].
///
/// Reuses the real shell scripts (bundled as Flutter assets under
/// assets/setup_scripts/ - see pubspec.yaml) rather than reimplementing
/// their logic in Dart, since those scripts already carry hard-won fixes
/// for real incidents (empty-keyed WireGuard configs, the
/// iptables-persistent/ufw conflict, etc. - see infra/README.md §10).
/// NOTE: these are copies, not a shared file path (Flutter can't bundle
/// assets from outside the package root) - if the scripts under
/// infra/scripts/ change, re-copy them here too.
///
/// Every step is safe to re-run against a server that's already
/// partially or fully set up: WireGuard setup is skipped if `wg0.conf`
/// already exists (re-running it would invalidate every already-paired
/// device), `config.yaml` is never overwritten if present, and every
/// other step (binary download, systemd install, firewall rules,
/// pairing) is naturally idempotent already.
class VpsSetupService {
  final SshTransport _ssh;

  VpsSetupService(this._ssh);

  static const _remoteScriptDir = '/tmp/archangel-setup';
  static const _assetNames = [
    'baseline_setup.sh',
    'wireguard_setup.sh',
    'allow_port_before_reject.sh',
    'ensure_boot_fw_fixup.sh',
    'archangel.service',
  ];

  PairingBundle? _result;

  /// The pairing bundle for this device, available once [run]'s stream
  /// has completed successfully.
  PairingBundle get result {
    final r = _result;
    if (r == null) throw StateError('VpsSetupService.run() has not completed successfully yet');
    return r;
  }

  Stream<SetupProgress> run(VpsSetupConfig config) async* {
    yield const SetupProgress('detect', 'Checking the server is a supported Ubuntu/Debian host...');
    final arch = await _detectArch();
    yield SetupProgress('detect', 'Detected architecture: $arch', stageComplete: true);

    yield const SetupProgress('upload', 'Uploading setup scripts...');
    await _uploadScripts();
    yield const SetupProgress('upload', 'Scripts uploaded.', stageComplete: true);

    yield const SetupProgress('baseline', 'Running baseline setup (packages, swap, firewall)...');
    await _runScript('baseline_setup.sh', stage: 'baseline');
    yield const SetupProgress('baseline', 'Baseline setup complete.', stageComplete: true);

    yield const SetupProgress('wireguard', 'Checking for an existing WireGuard setup...');
    final wgAlreadySetUp = (await _exec('test -f /etc/wireguard/wg0.conf')).ok;
    if (wgAlreadySetUp) {
      yield const SetupProgress(
        'wireguard',
        'WireGuard is already configured on this server - leaving it as-is (re-running it would invalidate every already-paired device).',
        stageComplete: true,
      );
    } else {
      yield const SetupProgress('wireguard', 'Setting up WireGuard...');
      await _runScript('wireguard_setup.sh', stage: 'wireguard');
      yield const SetupProgress('wireguard', 'WireGuard configured.', stageComplete: true);
    }

    yield const SetupProgress('binary', 'Downloading the latest archangeld release...');
    await _installBinary(arch, config);
    yield const SetupProgress('binary', 'archangeld installed.', stageComplete: true);

    yield const SetupProgress('config', 'Writing server configuration...');
    final publicIp = await _writeConfigIfAbsent(config);
    yield const SetupProgress('config', 'Configuration ready.', stageComplete: true);

    yield const SetupProgress('service', 'Installing and starting the archangel service...');
    await _installService();
    yield const SetupProgress('service', 'Service is running.', stageComplete: true);

    yield const SetupProgress('firewall', 'Opening the app port to the WireGuard interface...');
    await _openAppPort(config);
    yield const SetupProgress('firewall', 'Firewall configured.', stageComplete: true);

    yield SetupProgress('pair', 'Pairing this device (server public IP: $publicIp)...');
    final bundle = await _pair(config);
    _result = bundle;
    yield const SetupProgress('pair', 'Paired.', stageComplete: true);
  }

  Future<String> _detectArch() async {
    final unameResult = await _exec('uname -m');
    if (!unameResult.ok) {
      throw VpsSetupException('detect', 'Could not run `uname -m` on the server: ${unameResult.stderr}');
    }
    final arch = switch (unameResult.stdout.trim()) {
      'x86_64' => 'amd64',
      'aarch64' || 'arm64' => 'arm64',
      final other => throw VpsSetupException(
          'detect',
          'Unsupported server architecture "$other" - only x86_64/aarch64 servers are supported.',
        ),
    };

    final aptResult = await _exec('command -v apt-get');
    if (!aptResult.ok) {
      throw const VpsSetupException(
        'detect',
        'This wizard only supports Ubuntu/Debian servers (apt-get was not found on this host).',
      );
    }
    return arch;
  }

  Future<void> _uploadScripts() async {
    await _exec('mkdir -p $_remoteScriptDir');
    for (final name in _assetNames) {
      final data = await rootBundle.load('assets/setup_scripts/$name');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final remotePath = '$_remoteScriptDir/$name';
      final isScript = name.endsWith('.sh');
      await _ssh.uploadFile(remotePath, bytes, chmod: isScript ? '755' : '644');
    }
  }

  Future<void> _runScript(String name, {required String stage}) async {
    final result = await _exec('bash $_remoteScriptDir/$name');
    if (!result.ok) {
      throw VpsSetupException(stage, 'exit ${result.exitCode}: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}');
    }
  }

  Future<void> _installBinary(String arch, VpsSetupConfig config) async {
    final url = 'https://github.com/${config.githubRepoSlug}/releases/latest/download/archangeld-$arch';
    final script = '''
set -e
sudo id -u archangel >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin archangel
sudo mkdir -p /opt/archangel /etc/archangel
sudo chown root:archangel /etc/archangel
sudo chmod 750 /etc/archangel
sudo curl -fsSL "$url" -o /tmp/archangeld
sudo mv /tmp/archangeld /opt/archangel/archangeld
sudo chmod 755 /opt/archangel/archangeld
sudo chown root:root /opt/archangel/archangeld
''';
    final result = await _exec(script);
    if (!result.ok) {
      throw VpsSetupException(
        'binary',
        'Failed to install archangeld (checked $url) - exit ${result.exitCode}: ${result.stderr}',
      );
    }
  }

  /// Returns the server's detected public IP (queried either way, since
  /// it's needed for the pairing bundle's WireGuard endpoint even when
  /// config.yaml already exists and is left untouched).
  Future<String> _writeConfigIfAbsent(VpsSetupConfig config) async {
    final ipResult = await _exec("curl -s -4 ifconfig.me || curl -s -4 icanhazip.com");
    final publicIp = ipResult.stdout.trim();
    if (publicIp.isEmpty) {
      throw const VpsSetupException('config', 'Could not detect the server\'s public IP address.');
    }

    final alreadyExists = (await _exec('test -f /etc/archangel/config.yaml')).ok;
    if (alreadyExists) {
      return publicIp;
    }

    final wgServerIp = '${config.wgSubnet}.1';
    final configYaml = '''
bind_addr: "$wgServerIp"
port: ${config.appPort}
public_endpoint: "$publicIp:${config.wgPort}"
files_root: ""
''';

    // Uploaded via SFTP (raw bytes, no shell parsing of the content at
    // all) rather than spliced into a heredoc - config.yaml's content
    // includes config.wgSubnet, a free-text field from the wizard's
    // "Advanced" section. A value containing a line that reads exactly
    // the heredoc's own delimiter would terminate it early and run
    // whatever followed as arbitrary shell as root - the same class of
    // bug the setup scripts themselves already avoid by being uploaded,
    // not inlined. Move the uploaded file into place with a second,
    // fixed (non-interpolated) command.
    final tmpPath = '$_remoteScriptDir/config.yaml';
    await _ssh.uploadFile(tmpPath, Uint8List.fromList(utf8.encode(configYaml)));

    final script = '''
set -e
sudo mv $tmpPath /etc/archangel/config.yaml
sudo chown root:archangel /etc/archangel/config.yaml
sudo chmod 640 /etc/archangel/config.yaml
''';
    final result = await _exec(script);
    if (!result.ok) {
      throw VpsSetupException('config', 'Failed to write config.yaml: ${result.stderr}');
    }
    return publicIp;
  }

  Future<void> _installService() async {
    final script = '''
set -e
sudo mv $_remoteScriptDir/archangel.service /etc/systemd/system/archangel.service
sudo systemctl daemon-reload
sudo systemctl enable --now archangel
sudo systemctl restart archangel
sleep 1
sudo systemctl is-active --quiet archangel
''';
    final result = await _exec(script);
    if (!result.ok) {
      throw VpsSetupException(
        'service',
        'archangel service failed to start - exit ${result.exitCode}: ${result.stderr}\n'
            'Check `sudo systemctl status archangel` and `sudo journalctl -u archangel -n 50` on the server.',
      );
    }
  }

  Future<void> _openAppPort(VpsSetupConfig config) async {
    final script = '''
set -e
sudo ufw allow in on wg0 to any port ${config.appPort} proto tcp || true
bash $_remoteScriptDir/allow_port_before_reject.sh ${config.appPort} tcp
bash $_remoteScriptDir/ensure_boot_fw_fixup.sh ${config.appPort} tcp
''';
    final result = await _exec(script);
    if (!result.ok) {
      throw VpsSetupException('firewall', 'Failed to open the app port: ${result.stderr}');
    }
  }

  Future<PairingBundle> _pair(VpsSetupConfig config) async {
    final result = await _exec('sudo /opt/archangel/archangeld pair ${_shellQuote(config.deviceName)} --raw');
    if (!result.ok) {
      throw VpsSetupException('pair', 'archangeld pair failed - exit ${result.exitCode}: ${result.stderr}');
    }
    try {
      return PairingBundle.parse(result.stdout.trim());
    } on FormatException catch (e) {
      throw VpsSetupException('pair', 'Got a pairing bundle back but could not parse it: ${e.message}');
    }
  }

  Future<SshExecResult> _exec(String command) => _ssh.exec(command);
}

String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";
