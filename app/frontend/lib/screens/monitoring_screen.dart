import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/mock_data.dart';
import '../models/system_metrics.dart';
import '../services/archangeld_connection.dart';
import '../services/monitoring_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backend = context.read<ArchangeldConnection>();
      context.read<MonitoringService>().start(backend);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mon = context.watch<MonitoringService>();
    final metrics = mon.metrics;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Monitoring', style: AxTextStyles.h1),
              const Spacer(),
              if (mon.isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AxColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    border: Border.all(color: AxColors.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StatusDot(color: AxColors.accent, size: 5),
                      const SizedBox(width: 6),
                      Text('LIVE 2s', style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.accent)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            mon.isConnected
                ? 'archangeld · streaming live over WireGuard'
                : (mon.status == MonitoringStatus.connecting ? 'connecting to archangeld...' : 'node_exporter · offline / mock data'),
            style: AxTextStyles.mutedMono,
          ),
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
          if (_tab == _MonTab.processes)
            _ProcessTable(
              query: _procQuery,
              onQuery: (v) => setState(() => _procQuery = v),
              liveProcs: mon.processes,
              totalCount: mon.totalProcesses,
            )
          else
            _ChartCard(
              tab: _tab,
              metrics: metrics,
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final _MonTab tab;
  final SystemMetrics? metrics;
  const _ChartCard({required this.tab, this.metrics});

  @override
  Widget build(BuildContext context) {
    final (title, now, unit, values, stats, breakdown) = switch (tab) {
      _MonTab.cpu => _buildCpuData(metrics?.cpu),
      _MonTab.memory => _buildMemoryData(metrics?.memory),
      _MonTab.disk => _buildDiskData(metrics?.disk),
      _MonTab.network => _buildNetworkData(metrics?.network),
      _MonTab.processes => ('', '', '', <double>[], <List<String>>[], <List<dynamic>>[]),
    };

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
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(color: AxColors.s1, borderRadius: BorderRadius.circular(13), border: Border.all(color: AxColors.line)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(b[0] as String, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2)),
                            if (b.length > 3 && (b[3] as String).isNotEmpty)
                              Text(b[3] as String, style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                            Text('${((b[1] as double) * 100).round()}%', style: AxTextStyles.mono.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        AxMeter(value: (b[1] as double).clamp(0.0, 1.0), color: b[2] as Color),
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

  (String, String, String, List<double>, List<List<String>>, List<List<dynamic>>) _buildCpuData(CPUMetrics? cpu) {
    if (cpu == null) {
      return (
        'CPU utilization', '18.4', '%',
        const [.2, .3, .22, .4, .3, .5, .35, .4, .3, .55, .42, .38, .48, .18],
        const [['MIN', '4%'], ['AVG', '19%'], ['MAX', '61%']],
        const [
          ['core 0', 0.24, AxColors.accent],
          ['core 1', 0.31, AxColors.accent],
          ['core 2', 0.18, AxColors.info],
          ['core 3', 0.42, AxColors.warn],
        ],
      );
    }

    final hist = cpu.history.isEmpty
        ? [cpu.usagePercent / 100.0]
        : cpu.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

    final minVal = (cpu.history.isEmpty ? cpu.usagePercent : cpu.history.reduce((a, b) => a < b ? a : b)).round();
    final maxVal = (cpu.history.isEmpty ? cpu.usagePercent : cpu.history.reduce((a, b) => a > b ? a : b)).round();
    final avgVal = cpu.history.isEmpty ? cpu.usagePercent.round() : (cpu.history.reduce((a, b) => a + b) / cpu.history.length).round();

    final breakdown = cpu.cores.map((c) {
      final ratio = (c.usagePercent / 100.0).clamp(0.0, 1.0);
      final col = ratio > 0.8 ? AxColors.bad : (ratio > 0.4 ? AxColors.warn : AxColors.accent);
      return ['core ${c.id}', ratio, col, c.speedLabel];
    }).toList();

    return (
      'CPU utilization',
      cpu.usagePercent.toStringAsFixed(1),
      '%',
      hist,
      [['MIN', '$minVal%'], ['AVG', '$avgVal%'], ['MAX', '$maxVal%']],
      breakdown,
    );
  }

  (String, String, String, List<double>, List<List<String>>, List<List<dynamic>>) _buildMemoryData(MemoryMetrics? mem) {
    if (mem == null) {
      return (
        'Memory usage', '9.6', 'GB',
        const [.4, .45, .5, .48, .55, .58, .6, .61],
        const [['MIN', '38%'], ['AVG', '52%'], ['MAX', '61%']],
        const [
          ['used', 0.61, AxColors.accent, '9.6 GB'],
          ['available', 0.39, AxColors.info, '6.0 GB'],
        ],
      );
    }

    final hist = mem.history.isEmpty
        ? [mem.usagePercent / 100.0]
        : mem.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

    final minVal = (mem.history.isEmpty ? mem.usagePercent : mem.history.reduce((a, b) => a < b ? a : b)).round();
    final maxVal = (mem.history.isEmpty ? mem.usagePercent : mem.history.reduce((a, b) => a > b ? a : b)).round();
    final avgVal = mem.history.isEmpty ? mem.usagePercent.round() : (mem.history.reduce((a, b) => a + b) / mem.history.length).round();

    final breakdown = [
      ['used', (mem.usagePercent / 100.0).clamp(0.0, 1.0), AxColors.accent, '${mem.usedGb.toStringAsFixed(1)} GB'],
      ['available', (1.0 - mem.usagePercent / 100.0).clamp(0.0, 1.0), AxColors.info, '${mem.availableGb.toStringAsFixed(1)} GB'],
    ];

    return (
      'Memory usage',
      mem.usedGb.toStringAsFixed(1),
      'GB',
      hist,
      [['MIN', '$minVal%'], ['AVG', '$avgVal%'], ['MAX', '$maxVal%']],
      breakdown,
    );
  }

  (String, String, String, List<double>, List<List<String>>, List<List<dynamic>>) _buildDiskData(DiskMetrics? disk) {
    if (disk == null) {
      return (
        'Disk throughput', '42', 'MB/s',
        const [.1, .2, .15, .3, .25, .42],
        const [['MIN', '2 MB/s'], ['AVG', '18 MB/s'], ['MAX', '42 MB/s']],
        const [
          ['/', 0.45, AxColors.accent, '298 GB free'],
        ],
      );
    }

    final hist = disk.history.isEmpty
        ? [disk.totalMbPerSec > 0 ? (disk.totalMbPerSec / 100.0).clamp(0.0, 1.0) : 0.05]
        : disk.history.map((v) => (v / 100.0).clamp(0.0, 1.0)).toList();

    final breakdown = disk.mounts.map((m) {
      final r = (m.usagePercent / 100.0).clamp(0.0, 1.0);
      return [
        m.mountPoint,
        r,
        r > 0.85 ? AxColors.bad : AxColors.accent,
        '${m.freeGb.toStringAsFixed(0)} GB free · ${m.usedGb.toStringAsFixed(0)} GB used',
      ];
    }).toList();

    return (
      'Disk throughput',
      disk.totalMbPerSec.toStringAsFixed(1),
      'MB/s',
      hist,
      [
        ['USED', '${disk.usedGb.toStringAsFixed(0)} GB (${disk.usagePercent.round()}%)'],
        ['FREE', '${disk.freeGb.toStringAsFixed(0)} GB'],
        ['READ', '${disk.readMbPerSec.toStringAsFixed(1)} M/s'],
        ['WRITE', '${disk.writeMbPerSec.toStringAsFixed(1)} M/s'],
      ],
      breakdown.isEmpty ? [['/', 0.42, AxColors.accent, '298 GB free']] : breakdown,
    );
  }

  (String, String, String, List<double>, List<List<String>>, List<List<dynamic>>) _buildNetworkData(NetworkMetrics? net) {
    if (net == null) {
      return (
        'Network throughput', '4.2', 'MB/s',
        const [.1, .3, .2, .6, .4, .3, .5, .3],
        const [['MIN', '0.5 M/s'], ['AVG', '2.8 M/s'], ['MAX', '4.2 M/s']],
        const [
          ['eth0', 0.65, AxColors.accent],
          ['wg0', 0.35, AxColors.info],
        ],
      );
    }

    final hist = net.history.isEmpty
        ? [net.totalMbPerSec > 0 ? (net.totalMbPerSec / 10.0).clamp(0.0, 1.0) : 0.05]
        : net.history.map((v) => (v / 10.0).clamp(0.0, 1.0)).toList();

    final breakdown = net.interfaces.map((i) {
      final totalMb = i.rxMbPerSec + i.txMbPerSec;
      final ratio = (totalMb / (net.totalMbPerSec > 0 ? net.totalMbPerSec : 1.0)).clamp(0.0, 1.0);
      return [i.name, ratio, AxColors.accent];
    }).toList();

    return (
      'Network throughput',
      net.totalMbPerSec.toStringAsFixed(1),
      'MB/s',
      hist,
      [['RX', '${net.rxMbPerSec.toStringAsFixed(1)} M/s'], ['TX', '${net.txMbPerSec.toStringAsFixed(1)} M/s'], ['TOTAL', '${net.totalMbPerSec.toStringAsFixed(1)} M/s']],
      breakdown.isEmpty ? [['eth0', 0.5, AxColors.accent]] : breakdown,
    );
  }
}

class _ProcessTable extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQuery;
  final List<LiveProcessInfo> liveProcs;
  final int totalCount;

  const _ProcessTable({
    required this.query,
    required this.onQuery,
    this.liveProcs = const [],
    this.totalCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final procsSource = liveProcs.isNotEmpty
        ? liveProcs.map((p) => ProcInfo(
              pid: p.pid,
              name: p.name,
              user: p.user,
              cpu: p.cpu,
              mem: p.mem,
              state: p.state,
            )).toList()
        : procs;

    final filtered = query.isEmpty
        ? procsSource
        : procsSource.where((p) => p.name.toLowerCase().contains(query.toLowerCase()) || p.user.toLowerCase().contains(query.toLowerCase()) || p.pid.toString().contains(query)).toList();

    final displayCount = totalCount > 0 ? totalCount : filtered.length;

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
                Text('$displayCount processes', style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3)),
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
                              children: [
                                AxGhostButton(
                                  label: 'renice',
                                  onTap: () => _showReniceDialog(context, p),
                                ),
                                const SizedBox(width: 5),
                                AxGhostButton(
                                  label: 'kill',
                                  color: AxColors.bad,
                                  borderColor: const Color(0x4CE5806B),
                                  onTap: () => _showKillDialog(context, p),
                                ),
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

  void _showKillDialog(BuildContext context, ProcInfo proc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AxColors.s1,
        title: Text('Kill Process', style: AxTextStyles.h2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to terminate this process?', style: AxTextStyles.sans),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AxColors.s2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AxColors.line),
              ),
              child: Row(
                children: [
                  Text('PID ${proc.pid}', style: AxTextStyles.mono.copyWith(color: AxColors.accent, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(proc.name, style: AxTextStyles.mono, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AxColors.bad),
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await context.read<MonitoringService>().killProcess(proc.pid);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res.message),
                    backgroundColor: res.success ? AxColors.s2 : AxColors.bad,
                  ),
                );
              }
            },
            child: const Text('Kill Process', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showReniceDialog(BuildContext context, ProcInfo proc) {
    int selectedPrio = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AxColors.s1,
          title: Text('Renice Process', style: AxTextStyles.h2),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Adjust scheduling priority for PID ${proc.pid} (${proc.name}):', style: AxTextStyles.sans),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Priority (niceness):', style: AxTextStyles.label),
                  Text('$selectedPrio', style: AxTextStyles.mono.copyWith(fontSize: 16, color: AxColors.accent, fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: selectedPrio.toDouble(),
                min: -20,
                max: 19,
                divisions: 39,
                activeColor: AxColors.accent,
                onChanged: (val) => setDlgState(() => selectedPrio = val.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('-20 (Highest)', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.warn)),
                  Text('0 (Normal)', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                  Text('+19 (Lowest)', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.accent)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: AxTextStyles.sans.copyWith(color: AxColors.fg3)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AxColors.accent),
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await context.read<MonitoringService>().reniceProcess(proc.pid, selectedPrio);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res.message),
                      backgroundColor: res.success ? AxColors.s2 : AxColors.bad,
                    ),
                  );
                }
              },
              child: const Text('Apply', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
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

