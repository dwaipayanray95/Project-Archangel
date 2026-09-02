import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';

import 'tunnel_config.dart';

/// Our own status enum, decoupled from wireguard_flutter's [VpnStage] so
/// the UI (top bar pill, Settings) never depends on the plugin directly.
enum TunnelStatus { disconnected, connecting, connected, disconnecting, error, unsupported }

const _kInterfaceName = 'archangel';
const _kStorageKey = 'wg_tunnel_config';

/// Same bundle identifier the macOS/iOS Packet Tunnel Provider extension
/// must be registered under in Xcode (Signing & Capabilities ->
/// App Groups / Network Extension). Unused on Android/Windows/Linux, but
/// the plugin's API requires a value regardless of platform.
const _kProviderBundleId = 'dev.archangel.archangel.tunnel';

const _secureStorage = FlutterSecureStorage();

/// Wraps wireguard_flutter behind a small app-specific API: load/save the
/// paired config, connect/disconnect, and a status stream the UI observes.
///
/// Platform support as of the underlying plugin (wireguard_flutter 0.1.3):
///  - Android: real VpnService backend - works out of the box.
///  - Windows: bundles the official WireGuardNT tunnel.dll/wireguard.dll
///    and creates a Windows service to run the tunnel - this requires the
///    app to be running elevated (see windows/runner's app manifest).
///  - Linux: shells out to wg-quick directly - requires `wireguard-tools`
///    installed and passwordless (or interactive) root for `wg-quick up`.
///  - macOS: uses Apple's NetworkExtension/NETunnelProviderManager, which
///    requires a separate Packet Tunnel Provider extension target added
///    in Xcode, an Apple Developer Program membership, and the Network
///    Extension entitlement - this is a manual one-time Xcode setup step,
///    not something achievable purely from Dart. Until that target exists,
///    connect() will fail on macOS with a clear error rather than crash.
class WireGuardController extends ChangeNotifier {
  final _wg = WireGuardFlutter.instance;
  StreamSubscription<VpnStage>? _sub;

  TunnelStatus _status = TunnelStatus.disconnected;
  TunnelStatus get status => _status;

  TunnelConfig? _config;
  TunnelConfig? get config => _config;
  bool get isPaired => _config != null;

  String? _lastError;
  String? get lastError => _lastError;

  bool _initialized = false;

  Future<void> bootstrap() async {
    if (_initialized) return;
    _initialized = true;

    await _loadSavedConfig();

    try {
      await _wg.initialize(interfaceName: _kInterfaceName);
      _sub = _wg.vpnStageSnapshot.listen(_onStageChanged, onError: (_) {});
      unawaited(_wg.refreshStage());
    } catch (e) {
      // Most commonly hit on macOS before the Network Extension target
      // exists, or on Linux without wireguard-tools installed.
      _status = TunnelStatus.unsupported;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void _onStageChanged(VpnStage stage) {
    _status = switch (stage) {
      VpnStage.connected => TunnelStatus.connected,
      VpnStage.connecting || VpnStage.preparing || VpnStage.authenticating || VpnStage.waitingConnection || VpnStage.reconnect =>
        TunnelStatus.connecting,
      VpnStage.disconnecting || VpnStage.exiting => TunnelStatus.disconnecting,
      VpnStage.disconnected || VpnStage.noConnection => TunnelStatus.disconnected,
      VpnStage.denied => TunnelStatus.error,
    };
    if (stage == VpnStage.denied) {
      _lastError = Platform.isWindows
          ? 'Permission denied creating the tunnel service - Archangel needs to run as Administrator on Windows.'
          : 'Permission denied starting the VPN tunnel.';
    }
    notifyListeners();
  }

  Future<void> _loadSavedConfig() async {
    try {
      final raw = await _secureStorage.read(key: _kStorageKey);
      if (raw != null) _config = TunnelConfig.parse(raw);
    } catch (e) {
      _lastError = 'Saved tunnel config could not be read: $e';
    }
  }

  /// Parses, persists (encrypted via the OS keychain/keystore), and stores
  /// [wgQuickText] as the paired config. Does not connect automatically.
  Future<void> pair(String wgQuickText) async {
    final parsed = TunnelConfig.parse(wgQuickText); // throws FormatException on bad input
    await _secureStorage.write(key: _kStorageKey, value: wgQuickText);
    _config = parsed;
    notifyListeners();
  }

  Future<void> unpair() async {
    if (_status == TunnelStatus.connected || _status == TunnelStatus.connecting) {
      await disconnect();
    }
    await _secureStorage.delete(key: _kStorageKey);
    _config = null;
    notifyListeners();
  }

  Future<void> connect() async {
    final cfg = _config;
    if (cfg == null) {
      _lastError = 'No paired tunnel config - pair a device first.';
      notifyListeners();
      return;
    }
    _lastError = null;
    try {
      await _wg.startVpn(
        serverAddress: cfg.serverAddress,
        wgQuickConfig: cfg.toWgQuickConfig(),
        providerBundleIdentifier: _kProviderBundleId,
      );
    } catch (e) {
      _status = TunnelStatus.error;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      await _wg.stopVpn();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
