import 'package:flutter/services.dart';

/// Talks to macos/Runner/WireGuardMacOS.swift - the bundled-wireguard-go
/// backend used on macOS instead of wireguard_flutter's NetworkExtension
/// path (which needs a Packet Tunnel Provider Xcode target + paid Apple
/// Developer Program membership). See WIREGUARD.md for the full rationale
/// and its "unverified, needs a real-hardware debugging pass" status.
class MacosWireGuardChannel {
  static const _channel = MethodChannel('archangel/wireguard_macos');

  Future<void> connect(String wgQuickConfig) async {
    await _channel.invokeMethod<void>('connect', {'config': wgQuickConfig});
  }

  Future<void> disconnect() async {
    await _channel.invokeMethod<void>('disconnect');
  }

  Future<String> status() async {
    final s = await _channel.invokeMethod<String>('status');
    return s ?? 'disconnected';
  }
}
