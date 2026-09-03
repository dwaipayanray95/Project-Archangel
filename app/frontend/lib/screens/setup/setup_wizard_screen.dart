import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../../services/archangeld_connection.dart';
import '../../services/pairing_bundle.dart';
import '../../services/ssh_transport.dart';
import '../../services/vps_setup_service.dart';
import '../../services/wireguard_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/ax_widgets.dart';

const _kSshHostKey = 'vps_setup_ssh_host';
const _kSshUsernameKey = 'vps_setup_ssh_username';
const _kSshPrivateKeyKey = 'vps_setup_ssh_private_key';
const _secureStorage = FlutterSecureStorage();

/// The in-app "zero-SSH-by-hand" first-run wizard: connect → progress →
/// done. See lib/services/vps_setup_service.dart for what actually runs
/// on the server - this screen is purely presentation plus wiring the
/// resulting PairingBundle into WireGuardController/ArchangeldConnection
/// exactly the same way the manual pairing dialog does.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

enum _WizardStep { connect, progress, done }

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  _WizardStep _step = _WizardStep.connect;

  final _hostController = TextEditingController();
  final _usernameController = TextEditingController(text: 'ubuntu');
  final _privateKeyController = TextEditingController();
  final _deviceNameController = TextEditingController(text: _defaultDeviceName());
  bool _rememberKey = false;
  bool _connecting = false;
  String? _connectError;

  bool _advancedOpen = false;
  final _wgSubnetController = TextEditingController(text: '10.10.0');
  final _wgPortController = TextEditingController(text: '51820');
  final _appPortController = TextEditingController(text: '8443');

  SshTransport? _transport;
  final List<SetupProgress> _log = [];
  Object? _runError;
  PairingBundle? _bundle;

  static String _defaultDeviceName() {
    if (Platform.isMacOS) return 'mac';
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux) return 'linux';
    return 'device';
  }

  @override
  void initState() {
    super.initState();
    _restoreSavedKey();
  }

  Future<void> _restoreSavedKey() async {
    final host = await _secureStorage.read(key: _kSshHostKey);
    final username = await _secureStorage.read(key: _kSshUsernameKey);
    final key = await _secureStorage.read(key: _kSshPrivateKeyKey);
    if (!mounted || key == null) return;
    setState(() {
      _hostController.text = host ?? '';
      _usernameController.text = username ?? 'ubuntu';
      _privateKeyController.text = key;
      _rememberKey = true;
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _privateKeyController.dispose();
    _deviceNameController.dispose();
    _wgSubnetController.dispose();
    _wgPortController.dispose();
    _appPortController.dispose();
    _transport?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final privateKey = _privateKeyController.text.trim();
    if (host.isEmpty || username.isEmpty || privateKey.isEmpty) {
      setState(() => _connectError = 'Host, SSH username, and private key are all required.');
      return;
    }

    setState(() {
      _connecting = true;
      _connectError = null;
    });

    try {
      final transport = await Dartssh2Transport.connect(
        host: host,
        port: 22,
        username: username,
        privateKeyPem: privateKey,
      );

      if (_rememberKey) {
        await _secureStorage.write(key: _kSshHostKey, value: host);
        await _secureStorage.write(key: _kSshUsernameKey, value: username);
        await _secureStorage.write(key: _kSshPrivateKeyKey, value: privateKey);
      } else {
        await _secureStorage.delete(key: _kSshHostKey);
        await _secureStorage.delete(key: _kSshUsernameKey);
        await _secureStorage.delete(key: _kSshPrivateKeyKey);
      }

      if (!mounted) return;
      _transport = transport;
      setState(() {
        _connecting = false;
        _step = _WizardStep.progress;
      });
      _runSetup();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = 'Could not connect: $e';
      });
    }
  }

  void _runSetup() {
    final config = VpsSetupConfig(
      deviceName: _deviceNameController.text.trim().isEmpty ? _defaultDeviceName() : _deviceNameController.text.trim(),
      wgSubnet: _wgSubnetController.text.trim().isEmpty ? '10.10.0' : _wgSubnetController.text.trim(),
      wgPort: int.tryParse(_wgPortController.text.trim()) ?? 51820,
      appPort: int.tryParse(_appPortController.text.trim()) ?? 8443,
    );
    final service = VpsSetupService(_transport!);
    service.run(config).listen(
      (event) => setState(() => _log.add(event)),
      onError: (Object e) => setState(() => _runError = e),
      onDone: () {
        if (_runError == null) {
          setState(() {
            _bundle = service.result;
            _step = _WizardStep.done;
          });
        }
      },
    );
  }

  Future<void> _enterArchangel() async {
    final bundle = _bundle;
    if (bundle == null) return;
    final wg = context.read<WireGuardController>();
    final backend = context.read<ArchangeldConnection>();
    await wg.pair(bundle.tunnel.toWgQuickConfig());
    await backend.pair(host: bundle.host, token: bundle.token);
    // The app's root router watches both of these and swaps to the main
    // shell automatically once isPaired becomes true - no manual
    // navigation needed here.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AxColors.bg,
      appBar: AppBar(
        backgroundColor: AxColors.bg,
        elevation: 0,
        title: Text('Set up a new server', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      body: switch (_step) {
        _WizardStep.connect => _buildConnectStep(),
        _WizardStep.progress => _buildProgressStep(),
        _WizardStep.done => _buildDoneStep(),
      },
    );
  }

  Widget _buildConnectStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AxCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AxColors.warn, size: 18),
                      const SizedBox(width: 8),
                      Text('Before you start', style: AxTextStyles.sans.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AxColors.warn)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure UDP 51820 (WireGuard) is open at your cloud provider\'s '
                    'network firewall level (e.g. an OCI VCN Security List or AWS Security '
                    'Group) - this is separate from the server\'s own firewall and this '
                    'wizard cannot open it for you.',
                    style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _label('Server public IP or hostname'),
            _textField(_hostController, hint: '203.0.113.5'),
            const SizedBox(height: 12),
            _label('SSH username'),
            _textField(_usernameController, hint: 'ubuntu'),
            const SizedBox(height: 12),
            _label('SSH private key'),
            _textField(_privateKeyController, hint: '-----BEGIN OPENSSH PRIVATE KEY-----', maxLines: 6, mono: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _rememberKey,
                  onChanged: (v) => setState(() => _rememberKey = v ?? false),
                ),
                Expanded(
                  child: Text(
                    'Remember this key for future server management from the app',
                    style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _label('Device name'),
            _textField(_deviceNameController, hint: 'mac'),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: _advancedOpen,
              onExpansionChanged: (v) => setState(() => _advancedOpen = v),
              title: Text('Advanced', style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2)),
              children: [
                _label('WireGuard subnet'),
                _textField(_wgSubnetController, hint: '10.10.0'),
                const SizedBox(height: 12),
                _label('WireGuard port'),
                _textField(_wgPortController, hint: '51820'),
                const SizedBox(height: 12),
                _label('archangeld port'),
                _textField(_appPortController, hint: '8443'),
              ],
            ),
            if (_connectError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_connectError!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
              ),
            const SizedBox(height: 20),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: _connecting ? null : _connect,
                child: _connecting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Connect and set up'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStep() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_runError != null)
            AxCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Setup failed', style: AxTextStyles.sans.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AxColors.bad)),
                  const SizedBox(height: 6),
                  Text('$_runError', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (context, i) {
                final entry = _log[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        entry.stageComplete ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 14,
                        color: entry.stageComplete ? AxColors.accent : AxColors.fg3,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(entry.message, style: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg2)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: AxColors.accent, size: 48),
              const SizedBox(height: 16),
              Text('Server ready', style: AxTextStyles.sans.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Paired as "${_bundle?.name ?? ''}" - your WireGuard tunnel and backend connection are configured.',
                textAlign: TextAlign.center,
                style: AxTextStyles.sans.copyWith(fontSize: 13, color: AxColors.fg2, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _enterArchangel,
                  child: const Text('Enter Archangel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
      );

  Widget _textField(TextEditingController controller, {required String hint, int maxLines = 1, bool mono = false}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: (mono ? AxTextStyles.mono : AxTextStyles.sans).copyWith(fontSize: 12.5),
      decoration: InputDecoration(
        filled: true,
        fillColor: AxColors.s1,
        hintText: hint,
        hintStyle: (mono ? AxTextStyles.mono : AxTextStyles.sans).copyWith(fontSize: 12, color: AxColors.fg3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}
