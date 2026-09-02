import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import '../widgets/sparkline.dart';

enum _MonTab { cpu, memory, disk, network, processes }

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  _MonTab _tab = _MonTab.cpu;
  String _range = '1h';
  String _procQuery = '';

  static const _chartValues = [.2, .3, .22, .4, .3, .5, .35, .4, .3, .55, .42, .38, .48, .18];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monitoring', style: AxTextStyles.h1),
          const SizedBox(height: 3),
          Text('node_exporter · 15s scrape', style: AxTextStyles.mutedMono),
          const SizedBox(height: 15),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AxSegmented<_MonTab>(
                values: _MonTab.values,
                selected: _tab,
                label: (t) => switch (t) {
                  _MonTab.cpu => 'CPU',
                  _MonTab.memory => 'Memory',
                  _MonTab.disk => 'Disk',
                  _MonTab.network => 'Network',
                  _MonTab.processes => 'Processes',
                },
                onSelect: (t) => setState(() => _tab = t),
              ),
              if (_tab != _MonTab.processes)
                AxSegmented<String>(
                  values: const ['1h', '24h', '7d'],
                  selected: _range,
                  label: (r) => r,
                  onSelect: (r) => setState(() => _range = r),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_tab == _MonTab.processes) _ProcessTable(query: _procQuery, onQuery: (v) => setState(() => _procQuery = v)) else _ChartCard(tab: _tab, values: _chartValues),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final _MonTab tab;
  final List<double> values;
  const _ChartCard({required this.tab, required this.values});

  @override
  Widget build(BuildContext context) {
    final (title, now, unit) = switch (tab) {
      _MonTab.cpu => ('CPU utilization', '18.4', '%'),
      _MonTab.memory => ('Memory usage', '9.6', 'GB'),
      _MonTab.disk => ('Disk throughput', '42', 'MB/s'),
      _MonTab.network => ('Network throughput', '4.2', 'MB/s'),
      _MonTab.processes => ('', '', ''),
    };
    final stats = const [
      ['MIN', '4%'],
      ['AVG', '19%'],
      ['MAX', '61%'],
    ];
    final breakdown = const [
      ['core 0', 0.24, AxColors.accent],
      ['core 1', 0.31, AxColors.accent],
      ['core 2', 0.18, AxColors.info],
      ['core 3', 0.42, AxColors.warn],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AxCard(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AxTextStyles.sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(now, style: AxTextStyles.mono.copyWith(fontSize: 25, fontWeight: FontWeight.w500, color: AxColors.accent)),
                            const SizedBox(width: 6),
                            Text(unit, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  for (final s in stats)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(s[0], style: AxTextStyles.label),
                          const SizedBox(height: 2),
                          Text(s[1], style: AxTextStyles.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(height: 150, child: Sparkline(values: values, color: AxColors.accent)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (final l in ['-1h', '-45m', '-30m', '-15m', 'now']) Text(l, style: AxTextStyles.mono.copyWith(fontSize: 9.5, color: AxColors.fg3))],
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 700 ? 4 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 11,
              crossAxisSpacing: 11,
              childAspectRatio: 2.6,
              children: [
                for (final b in breakdown)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(color: AxColors.s1, borderRadius: BorderRadius.circular(13), border: Border.all(color: AxColors.line)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(b[0] as String, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2)),
                            Text('${((b[1] as double) * 100).round()}%', style: AxTextStyles.mono.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        AxMeter(value: b[1] as double, color: b[2] as Color),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ProcessTable extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQuery;
  const _ProcessTable({required this.query, required this.onQuery});

  @override
  Widget build(BuildContext context) {
    final filtered = query.isEmpty
        ? procs
        : procs.where((p) => p.name.toLowerCase().contains(query.toLowerCase()) || p.user.toLowerCase().contains(query.toLowerCase()) || p.pid.toString().contains(query)).toList();

    return Container(
      decoration: BoxDecoration(color: AxColors.s1, borderRadius: BorderRadius.circular(AxRadius.xl), border: Border.all(color: AxColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
                  decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.line)),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 12, color: AxColors.fg3),
                      const SizedBox(width: 7),
                      Expanded(
                        child: TextField(
                          onChanged: onQuery,
                          style: AxTextStyles.mono.copyWith(fontSize: 11.5),
                          decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: 'filter by name, pid or user'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text('${filtered.length} processes', style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3)),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: AxColors.s2,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    child: const Row(
                      children: [
                        SizedBox(width: 62, child: _ColHead('PID')),
                        Expanded(flex: 3, child: _ColHead('NAME')),
                        SizedBox(width: 78, child: _ColHead('USER')),
                        SizedBox(width: 74, child: _ColHead('CPU%', alignEnd: true)),
                        SizedBox(width: 74, child: _ColHead('MEM%', alignEnd: true)),
                        SizedBox(width: 96, child: _ColHead('', alignEnd: true)),
                      ],
                    ),
                  ),
                  for (final p in filtered)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
                      child: Row(
                        children: [
                          SizedBox(width: 62, child: Text('${p.pid}', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3))),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Container(width: 5, height: 5, decoration: BoxDecoration(color: p.state == 'R' ? AxColors.accent : AxColors.fg3, shape: BoxShape.circle)),
                                const SizedBox(width: 7),
                                Expanded(child: Text(p.name, style: AxTextStyles.mono.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                          SizedBox(width: 78, child: Text(p.user, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2))),
                          SizedBox(width: 74, child: Text('${p.cpu}%', textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: p.cpu > 5 ? AxColors.warn : AxColors.fg))),
                          SizedBox(width: 74, child: Text('${p.mem}%', textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg2))),
                          SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: const [
                                AxGhostButton(label: 'renice'),
                                SizedBox(width: 5),
                                AxGhostButton(label: 'kill', color: AxColors.bad, borderColor: Color(0x4CE5806B)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColHead extends StatelessWidget {
  final String text;
  final bool alignEnd;
  const _ColHead(this.text, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Text(text, textAlign: alignEnd ? TextAlign.right : TextAlign.left, style: AxTextStyles.label);
  }
}
