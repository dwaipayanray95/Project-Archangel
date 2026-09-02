import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';

enum _DevTab { services, scheduled, proxy, deployments }

class DevopsScreen extends StatefulWidget {
  const DevopsScreen({super.key});

  @override
  State<DevopsScreen> createState() => _DevopsScreenState();
}

class _DevopsScreenState extends State<DevopsScreen> {
  _DevTab _tab = _DevTab.services;

  List<DevRow> get _rows => switch (_tab) {
        _DevTab.services => devServices,
        _DevTab.scheduled => devScheduled,
        _DevTab.proxy => devProxy,
        _DevTab.deployments => devDeployments,
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 620;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DevOps', style: AxTextStyles.h1),
          const SizedBox(height: 3),
          Text('systemd · cron · caddy · deploy hooks', style: AxTextStyles.mutedMono),
          const SizedBox(height: 15),
          AxSegmented<_DevTab>(
            values: _DevTab.values,
            selected: _tab,
            label: (t) => switch (t) {
              _DevTab.services => 'Services',
              _DevTab.scheduled => 'Scheduled',
              _DevTab.proxy => 'Reverse proxy',
              _DevTab.deployments => 'Deployments',
            },
            onSelect: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: AxColors.s1, borderRadius: BorderRadius.circular(AxRadius.xl), border: Border.all(color: AxColors.line)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final r in _rows) _DevRowTile(row: r, wide: wide)],
            ),
          ),
        ],
      ),
    );
  }
}

class _DevRowTile extends StatelessWidget {
  final DevRow row;
  final bool wide;
  const _DevRowTile({required this.row, required this.wide});

  @override
  Widget build(BuildContext context) {
    final dot = row.ok ? AxColors.accent : AxColors.fg3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: AxTextStyles.mono.copyWith(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(row.meta, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AxPill(text: row.status, color: dot),
          if (wide) ...[
            const SizedBox(width: 8),
            Row(children: [for (final a in row.actions) Padding(padding: const EdgeInsets.only(left: 5), child: AxGhostButton(label: a))]),
          ],
        ],
      ),
    );
  }
}
