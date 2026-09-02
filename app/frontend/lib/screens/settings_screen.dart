import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tunnelRows = const [
      ['Interface', 'wg0'],
      ['Address', '10.8.0.1/24'],
      ['Endpoint', '84.22.19.7:51820'],
      ['Latest handshake', '41 seconds ago'],
      ['Transfer', '1.42 GiB / 8.19 GiB'],
    ];
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
                  AxCard(
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
                              decoration: BoxDecoration(color: AxColors.wash, borderRadius: BorderRadius.circular(AxRadius.pill)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const StatusDot(color: AxColors.accent, size: 5, pulse: true),
                                  const SizedBox(width: 6),
                                  Text('wg0 up', style: AxTextStyles.mono.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: AxColors.accent)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        for (final r in tunnelRows) _KvRow(r[0], r[1]),
                        const SizedBox(height: 12),
                        Row(
                          children: const [
                            _FilledPill(label: 'Reconnect'),
                            SizedBox(width: 7),
                            AxGhostButton(label: 'View config'),
                          ],
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
  const _FilledPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(color: AxColors.wash, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.accent.withValues(alpha: 0.22))),
      child: Text(label, style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.accent)),
    );
  }
}
