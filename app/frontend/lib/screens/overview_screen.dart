import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../data/mock_data.dart';
import '../models/system_metrics.dart';
import '../services/monitoring_service.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import '../widgets/sparkline.dart';

class _Tile {
  final String label;
  final String value;
  final String unit;
  final String sub;
  final String delta;
  final Color deltaColor;
  final Color color;
  final IconData icon;
  final List<double> spark;
  final AxSection go;
  const _Tile(this.label, this.value, this.unit, this.sub, this.delta, this.deltaColor, this.color, this.icon, this.spark, this.go);
}

final _mockTiles = <_Tile>[
  _Tile('CPU', '18', '%', '8 cores · 2.4GHz avg', '-2%', AxColors.accent, AxColors.accent, Icons.memory, const [.2, .3, .22, .4, .3, .5, .35, .18], AxSection.monitoring),
  _Tile('MEMORY', '9.6', 'GB', 'of 15.6 GB · 61%', '+4%', AxColors.warn, AxColors.info, Icons.developer_board, const [.4, .45, .5, .48, .55, .58, .6, .61], AxSection.monitoring),
  _Tile('DISK', '214', 'GB', 'of 512 GB · 45%', '+0.2%', AxColors.fg3, AxColors.fg, Icons.storage, const [.4, .41, .42, .42, .43, .44, .44, .45], AxSection.monitoring),
  _Tile('NETWORK', '4.2', 'MB/s', '1.4 up · 2.8 down', '', AxColors.fg3, AxColors.accent, Icons.swap_vert, const [.1, .3, .2, .6, .4, .3, .5, .3], AxSection.monitoring),
];

List<_Tile> _buildTiles(SystemMetrics? metrics) {
  if (metrics == null) return _mockTiles;

  final cpu = metrics.cpu;
  final mem = metrics.memory;
  final disk = metrics.disk;
  final net = metrics.network;

  final cpuSpark = cpu.history.isEmpty
      ? [cpu.usagePercent / 100.0]
      : cpu.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

  final memSpark = mem.history.isEmpty
      ? [mem.usagePercent / 100.0]
      : mem.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

  final diskSpark = disk.history.isEmpty
      ? [disk.totalMbPerSec > 0 ? (disk.totalMbPerSec / 100.0).clamp(0.0, 1.0) : 0.05]
      : disk.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

  final netSpark = net.history.isEmpty
      ? [net.totalMbPerSec > 0 ? (net.totalMbPerSec / 10.0).clamp(0.0, 1.0) : 0.05]
      : net.history.map((v) => (v / 10.0).clamp(0.0, 1.0)).toList();

  return [
    _Tile(
      'CPU',
      cpu.usagePercent.toStringAsFixed(0),
      '%',
      '${cpu.cores.length} cores active',
      '',
      AxColors.accent,
      AxColors.accent,
      Icons.memory,
      cpuSpark,
      AxSection.monitoring,
    ),
    _Tile(
      'MEMORY',
      mem.usedGb.toStringAsFixed(1),
      'GB',
      'of ${mem.totalGb.toStringAsFixed(1)} GB · ${mem.usagePercent.toStringAsFixed(0)}%',
      '',
      AxColors.warn,
      AxColors.info,
      Icons.developer_board,
      memSpark,
      AxSection.monitoring,
    ),
    _Tile(
      'DISK',
      disk.usedGb.toStringAsFixed(0),
      'GB',
      'of ${disk.totalGb.toStringAsFixed(0)} GB · ${disk.usagePercent.toStringAsFixed(0)}%',
      '',
      AxColors.fg3,
      AxColors.fg,
      Icons.storage,
      diskSpark,
      AxSection.monitoring,
    ),
    _Tile(
      'NETWORK',
      net.totalMbPerSec.toStringAsFixed(1),
      'MB/s',
      '${net.rxMbPerSec.toStringAsFixed(1)} in · ${net.txMbPerSec.toStringAsFixed(1)} out',
      '',
      AxColors.fg3,
      AxColors.accent,
      Icons.swap_vert,
      netSpark,
      AxSection.monitoring,
    ),
  ];
}

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final wide = MediaQuery.of(context).size.width >= 760;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overview', style: AxTextStyles.h1),
                    const SizedBox(height: 3),
                    Text('all systems nominal · polled 4s ago', style: AxTextStyles.mutedMono),
                  ],
                ),
              ),
              if (wide)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: AxColors.wash,
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    border: Border.all(color: AxColors.accent.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StatusDot(color: AxColors.accent, size: 6),
                      const SizedBox(width: 7),
                      Text('Healthy', style: AxTextStyles.sans.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: AxColors.accent)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 17),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
              final mon = context.watch<MonitoringService>();
              final tiles = _buildTiles(mon.metrics);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 11,
                crossAxisSpacing: 11,
                childAspectRatio: 1.9,
                children: [for (final t in tiles) _StatTile(t: t, onTap: () => app.go(t.go))],
              );
            },
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 860;
              final feed = _ActivityFeed();
              final side = _IdentityAndActions();
              if (narrow) {
                return Column(children: [feed, const SizedBox(height: 11), side]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: feed),
                  const SizedBox(width: 11),
                  Expanded(flex: 2, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final _Tile t;
  final VoidCallback onTap;
  const _StatTile({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AxCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(t.icon, size: 14, color: AxColors.fg3),
              const SizedBox(width: 7),
              Text(t.label, style: AxTextStyles.label),
              const Spacer(),
              if (t.delta.isNotEmpty) Text(t.delta, style: AxTextStyles.mono.copyWith(fontSize: 10, color: t.deltaColor)),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(t.value, style: AxTextStyles.mono.copyWith(fontSize: 26, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: t.color)),
              const SizedBox(width: 4),
              Text(t.unit, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3)),
            ],
          ),
          Text(t.sub, style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg2)),
          const SizedBox(height: 8),
          Expanded(child: Sparkline(values: t.spark, color: t.color)),
        ],
      ),
    );
  }
}

class _ActivityFeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AxColors.s1,
        borderRadius: BorderRadius.circular(AxRadius.xl),
        border: Border.all(color: AxColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
            child: Row(
              children: [
                Text('Activity', style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const Spacer(),
                const StatusDot(color: AxColors.accent, size: 5, pulse: true),
                const SizedBox(width: 5),
                Text('live', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: feedPool.length,
              itemBuilder: (context, i) {
                final f = feedPool[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: f.color, shape: BoxShape.circle)),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: AxTextStyles.sans.copyWith(fontSize: 12.5, height: 1.4),
                                children: [
                                  TextSpan(text: '${f.actor} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  TextSpan(text: f.text, style: const TextStyle(color: AxColors.fg2)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(f.detail, style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                          ],
                        ),
                      ),
                      Text(f.ago, style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
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
}

class _IdentityAndActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final identity = const [
      ['Host', 'Archangel-MK1'],
      ['Region', 'fra1'],
      ['OS', 'Ubuntu 24.04.4 LTS'],
      ['Kernel', '6.8.0-45-generic'],
      ['Tunnel', 'wg0 · 10.8.0.1'],
      ['Uptime', '42d 6h 18m'],
    ];
    final actions = const [
      ['Reboot', Icons.restart_alt_rounded, AxColors.warn],
      ['Terminal', Icons.chevron_right_rounded, AxColors.fg],
      ['Backup', Icons.save_alt_rounded, AxColors.fg],
      ['Lock', Icons.lock_outline_rounded, AxColors.bad],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AxCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 11),
                margin: const EdgeInsets.only(bottom: 3),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: AxColors.wash, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.dns_outlined, size: 15, color: AxColors.accent),
                    ),
                    const SizedBox(width: 9),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Archangel-MK1', style: AxTextStyles.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text('bare-metal VPS · fra1', style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
                      ],
                    ),
                  ],
                ),
              ),
              for (final row in identity)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0AE8F0E6)))),
                  child: Row(
                    children: [
                      SizedBox(width: 78, child: Text(row[0], style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3))),
                      Expanded(child: Text(row[1], style: AxTextStyles.mono.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        AxCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('QUICK ACTIONS', style: AxTextStyles.sans.copyWith(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AxColors.fg3)),
              const SizedBox(height: 9),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
                childAspectRatio: 2.6,
                children: [
                  for (final a in actions)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(11), border: Border.all(color: AxColors.line)),
                      child: Row(
                        children: [
                          Icon(a[1] as IconData, size: 14, color: a[2] as Color),
                          const SizedBox(width: 8),
                          Text(a[0] as String, style: AxTextStyles.sans.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: a[2] as Color)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
