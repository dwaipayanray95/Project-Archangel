// A parsed wg-quick style config: the [Interface]/[Peer] file WireGuard
// itself uses. Archangel is a single-peer client (this device <-> the
// server), so we only ever hold one peer.
class TunnelConfig {
  final String interfacePrivateKey;
  final String interfaceAddress;
  final String? interfaceDns;
  final String peerPublicKey;
  final String peerEndpoint; // host:port
  final String peerAllowedIps;
  final int? peerPersistentKeepalive;

  const TunnelConfig({
    required this.interfacePrivateKey,
    required this.interfaceAddress,
    this.interfaceDns,
    required this.peerPublicKey,
    required this.peerEndpoint,
    required this.peerAllowedIps,
    this.peerPersistentKeepalive,
  });

  /// The host portion of [peerEndpoint], e.g. "1.2.3.4" from "1.2.3.4:51820"
  /// — wireguard_flutter's startVpn wants this split out separately from
  /// the wg-quick config text.
  String get serverAddress {
    final idx = peerEndpoint.lastIndexOf(':');
    return idx == -1 ? peerEndpoint : peerEndpoint.substring(0, idx);
  }

  /// Renders back to the standard wg-quick [Interface]/[Peer] text block
  /// that wireguard_flutter's startVpn expects as `wgQuickConfig`.
  String toWgQuickConfig() {
    final b = StringBuffer('[Interface]\n');
    b.writeln('PrivateKey = $interfacePrivateKey');
    b.writeln('Address = $interfaceAddress');
    if (interfaceDns != null && interfaceDns!.isNotEmpty) {
      b.writeln('DNS = $interfaceDns');
    }
    b.writeln();
    b.writeln('[Peer]');
    b.writeln('PublicKey = $peerPublicKey');
    b.writeln('Endpoint = $peerEndpoint');
    b.writeln('AllowedIPs = $peerAllowedIps');
    if (peerPersistentKeepalive != null) {
      b.writeln('PersistentKeepalive = $peerPersistentKeepalive');
    }
    return b.toString();
  }

  /// Parses a standard wg-quick .conf file (as produced by `wg genconfig`,
  /// the WireGuard app's QR export, or archangeld's own pairing flow).
  /// Throws [FormatException] with a human-readable message on anything
  /// that doesn't look like a valid single-peer config.
  factory TunnelConfig.parse(String text) {
    String? privateKey, address, dns, publicKey, endpoint, allowedIps;
    int? keepalive;
    String section = '';

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim().toLowerCase();
        continue;
      }
      final eq = line.indexOf('=');
      if (eq == -1) continue;
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();

      if (section == 'interface') {
        switch (key) {
          case 'privatekey':
            privateKey = value;
          case 'address':
            address = value;
          case 'dns':
            dns = value;
        }
      } else if (section == 'peer') {
        switch (key) {
          case 'publickey':
            publicKey = value;
          case 'endpoint':
            endpoint = value;
          case 'allowedips':
            allowedIps = value;
          case 'persistentkeepalive':
            keepalive = int.tryParse(value);
        }
      }
    }

    if (privateKey == null || privateKey.isEmpty) {
      throw const FormatException('Missing [Interface] PrivateKey');
    }
    if (address == null || address.isEmpty) {
      throw const FormatException('Missing [Interface] Address');
    }
    if (publicKey == null || publicKey.isEmpty) {
      throw const FormatException('Missing [Peer] PublicKey');
    }
    if (endpoint == null || endpoint.isEmpty) {
      throw const FormatException('Missing [Peer] Endpoint');
    }

    return TunnelConfig(
      interfacePrivateKey: privateKey,
      interfaceAddress: address,
      interfaceDns: dns,
      peerPublicKey: publicKey,
      peerEndpoint: endpoint,
      peerAllowedIps: (allowedIps == null || allowedIps.isEmpty) ? '0.0.0.0/0' : allowedIps,
      peerPersistentKeepalive: keepalive,
    );
  }
}
