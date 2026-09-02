import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../services/archangeld_connection.dart';
import '../services/tunnel_config.dart';
import '../services/wireguard_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final aboutRows = const [
      ['Agent', 'archangeld 0.9.4'],
      ['Host', 'Archangel-MK1'],
      ['Paired devices', '1'],
      ['License', 'personal use'],
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: AxTextStyles.h1),
          const SizedBox(height: 3),
          Text('archangeld 0.9.4 · paired 1 device', style: AxTextStyles.mutedMono),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 700;
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _TunnelCard(),
                  const SizedBox(height: 11),
                  const _BackendCard(),
                  const SizedBox(height: 11),
                  AxCard(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Auth', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Device tokens rotate every 30 days.', style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg2)),
                        const SizedBox(height: 11),
                        _TokenRow(name: 'macbook-air', meta: 'issued Aug 14 · expires Sep 13'),
                        _TokenRow(name: 'pixel-9', meta: 'issued Aug 30 · expires Sep 29'),
                      ],
                    ),
                  ),
                ],
              );
              final right = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AxCard(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Appearance', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 11),
                        Text('Accent', style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final c in AxColors.accentOptions)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => app.accent = c,
                                  child: AnimatedContainer(
                                    duration: AxMotion.base,
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: app.accent == c ? AxColors.fg : Colors.transparent, width: 2),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Divider(color: AxColors.line, height: 1),
                        const SizedBox(height: 12),
                        Text('Density', style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.line)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(color: app.accent, borderRadius: BorderRadius.circular(AxRadius.pill)),
                                child: Text('Comfortable', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.bg)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Text('Compact', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: AxColors.fg3)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  AxCard(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('About', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        for (final r in aboutRows) _KvRow(r[0], r[1], divider: false),
                      ],
                    ),
                  ),
                ],
              );

              if (narrow) return Column(children: [left, const SizedBox(height: 11), right]);
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: left), const SizedBox(width: 11), Expanded(child: right)],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  final String k;
  final String v;
  final bool divider;
  const _KvRow(this.k, this.v, {this.divider = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: divider ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0AE8F0E6)))) : null,
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(k, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3))),
          Expanded(child: Text(v, style: AxTextStyles.mono.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  final String name;
  final String meta;
  const _TokenRow({required this.name, required this.meta});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(11), border: Border.all(color: AxColors.line)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AxTextStyles.sans.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(meta, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3)),
              ],
            ),
          ),
          const AxGhostButton(label: 'Rotate'),
        ],
      ),
    );
  }
}

class _FilledPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _FilledPill({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(color: AxColors.wash, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.accent.withValues(alpha: 0.22))),
      child: Text(label, style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.accent)),
    );
    return onTap == null ? pill : GestureDetector(onTap: onTap, child: pill);
  }
}

/// The Tunnel card on Settings: real WireGuard state (via
/// [WireGuardController]), pair/unpair, connect/disconnect, view config.
/// Real archangeld host/token pairing (host:port + auth token, stored via
/// flutter_secure_storage) — same connection the Terminal screen uses.
class _BackendCard extends StatelessWidget {
  const _BackendCard();

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();
    return AxCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Backend', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: (backend.isPaired ? AxColors.accent : AxColors.fg3).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AxRadius.pill),
                ),
                child: Text(
                  backend.isPaired ? 'paired' : 'not paired',
                  style: AxTextStyles.mono.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: backend.isPaired ? AxColors.accent : AxColors.fg3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (backend.isPaired) ...[
            _KvRow('Host', backend.host!),
            const SizedBox(height: 12),
            AxGhostButton(label: 'Unpair', color: AxColors.bad, onTap: backend.unpair),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Pair from the Terminal screen, or paste host + token there once archangeld prints them.',
                style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg2),
              ),
            ),
        ],
      ),
    );
  }
}

class _TunnelCard extends StatelessWidget {
  const _TunnelCard();

  @override
  Widget build(BuildContext context) {
    final wg = context.watch<WireGuardController>();
    final statusColor = switch (wg.status) {
      TunnelStatus.connected => AxColors.accent,
      TunnelStatus.connecting || TunnelStatus.disconnecting => AxColors.warn,
      TunnelStatus.error || TunnelStatus.unsupported => AxColors.bad,
      TunnelStatus.disconnected => AxColors.fg3,
    };
    final statusLabel = switch (wg.status) {
      TunnelStatus.connected => 'wg0 up',
      TunnelStatus.connecting => 'connecting…',
      TunnelStatus.disconnecting => 'disconnecting…',
      TunnelStatus.error => 'error',
      TunnelStatus.unsupported => 'unsupported here',
      TunnelStatus.disconnected => 'wg0 down',
    };

    final cfg = wg.config;
    final rows = cfg == null
        ? const <List<String>>[]
        : [
            ['Interface', cfg.interfaceAddress],
            ['Endpoint', cfg.peerEndpoint],
            ['Allowed IPs', cfg.peerAllowedIps],
            if (cfg.interfaceDns != null) ['DNS', cfg.interfaceDns!],
          ];

    return AxCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Tunnel', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AxRadius.pill)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(color: statusColor, size: 5, pulse: wg.status == TunnelStatus.connected),
                    const SizedBox(width: 6),
                    Text(statusLabel, style: AxTextStyles.mono.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: statusColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (cfg == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No device paired yet.', style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.fg2)),
            )
          else
            for (final r in rows) _KvRow(r[0], r[1]),
          if (wg.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(wg.lastError!, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.bad)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (cfg == null)
                _FilledPill(label: 'Pair device', onTap: () => _showPairDialog(context, wg))
              else ...[
                _FilledPill(
                  label: wg.status == TunnelStatus.connected ? 'Disconnect' : 'Reconnect',
                  onTap: wg.status == TunnelStatus.connected ? wg.disconnect : wg.connect,
                ),
                const SizedBox(width: 7),
                AxGhostButton(label: 'View config', onTap: () => _showConfigDialog(context, cfg)),
                const SizedBox(width: 7),
                AxGhostButton(label: 'Unpair', color: AxColors.bad, onTap: () => wg.unpair()),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showConfigDialog(BuildContext context, TunnelConfig cfg) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AxColors.s2,
        title: Text('Tunnel config', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
        content: SelectableText(
          cfg.toWgQuickConfig().replaceFirst(cfg.interfacePrivateKey, '••••••••••••••••••••••••••••••••••••••••••'),
          style: AxTextStyles.mono.copyWith(fontSize: 12, height: 1.6),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  void _showPairDialog(BuildContext context, WireGuardController wg) {
    final controller = TextEditingController();
    String? error;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AxColors.s2,
          title: Text('Pair device', style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste the wg-quick config archangeld generated for this device.',
                  style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  maxLines: 10,
                  style: AxTextStyles.mono.copyWith(fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AxColors.s1,
                    hintText: '[Interface]\nPrivateKey = ...\nAddress = ...\n\n[Peer]\nPublicKey = ...\nEndpoint = ...',
                    hintStyle: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.bad)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                try {
                  await wg.pair(controller.text);
                  if (context.mounted) Navigator.of(context).pop();
                } on FormatException catch (e) {
                  setState(() => error = e.message);
                }
              },
              child: const Text('Pair'),
            ),
          ],
        ),
      ),
    );
  }
}
