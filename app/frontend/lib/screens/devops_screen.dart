import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../models/devops_model.dart';
import '../services/archangeld_connection.dart';
import '../services/devops_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backend = context.read<ArchangeldConnection>();
      context.read<DevopsService>().init(backend);
    });
  }

  void _handleAction(BuildContext context, DevRowModel row, String action) async {
    final svc = context.read<DevopsService>();
    final app = context.read<AppState>();

    if (action == 'Logs') {
      // Deep-link to Terminal with journalctl command
      app.openTerminalWithCommand('journalctl -u ${row.name} -n 50 --no-pager');
      return;
    }

    if (action == 'Test') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Testing reachability for ${row.name}...')),
      );
      final res = await svc.testProxy(row.name);
      if (context.mounted && res != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${row.name}: $res')),
        );
      }
      return;
    }

    if (_tab == _DevTab.services) {
      final ok = await svc.triggerServiceAction(row.name, action);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Service ${row.name} $action triggered.' : 'Failed to $action ${row.name}.')),
        );
      }
    } else if (_tab == _DevTab.scheduled) {
      final ok = await svc.triggerScheduled(row.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Timer ${row.name} triggered.' : 'Failed to trigger ${row.name}.')),
        );
      }
    } else if (_tab == _DevTab.deployments) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Executing ${row.name}...')),
      );
      final res = await svc.runDeployment(row.name);
      if (context.mounted && res != null) {
        final msg = res['message'] ?? '';
        final out = res['output'] ?? '';
        if (out.isNotEmpty) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AxColors.s1,
              title: Text('Deployment: ${row.name}', style: AxTextStyles.h2),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(msg, style: AxTextStyles.sans.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070807),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AxColors.line),
                      ),
                      child: SelectableText(out, style: AxTextStyles.mono.copyWith(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${row.name}: $msg')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 620;
    final backend = context.watch<ArchangeldConnection>();
    final svc = context.watch<DevopsService>();

    final rows = switch (_tab) {
      _DevTab.services => svc.services,
      _DevTab.scheduled => svc.scheduled,
      _DevTab.proxy => svc.proxy,
      _DevTab.deployments => svc.deployments,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('DevOps', style: AxTextStyles.h1),
                      if (svc.loading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AxColors.accent),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('systemd · cron · caddy · deploy hooks', style: AxTextStyles.mutedMono),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(AxRadius.pill),
                onTap: () => svc.fetchAll(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                  decoration: BoxDecoration(
                    color: AxColors.wash,
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    border: Border.all(color: AxColors.accent.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded, size: 12, color: AxColors.accent),
                      const SizedBox(width: 6),
                      Text('Refresh', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AxColors.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
          if (backend.isPaired && svc.error != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AxColors.bad.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AxRadius.md),
                border: Border.all(color: AxColors.bad.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 14, color: AxColors.bad),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(svc.error!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!backend.isPaired)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AxColors.s1,
                borderRadius: BorderRadius.circular(AxRadius.xl),
                border: Border.all(color: AxColors.line),
              ),
              child: Column(
                children: [
                  const Icon(Icons.link_off_rounded, size: 32, color: AxColors.fg3),
                  const SizedBox(height: 12),
                  Text('Host Not Paired', style: AxTextStyles.mono.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Pair with archangeld to inspect systemd services, cron, and Caddy.', style: AxTextStyles.mutedMono, textAlign: TextAlign.center),
                ],
              ),
            )
          else if (rows.isEmpty && !svc.loading)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AxColors.s1,
                borderRadius: BorderRadius.circular(AxRadius.xl),
                border: Border.all(color: AxColors.line),
              ),
              child: Column(
                children: [
                  const Icon(Icons.inbox_rounded, size: 28, color: AxColors.fg3),
                  const SizedBox(height: 10),
                  Text('No items found in ${_tab.name}', style: AxTextStyles.mono.copyWith(fontSize: 13, color: AxColors.fg2)),
                  const SizedBox(height: 4),
                  Text('Host does not have configured entries for this section.', style: AxTextStyles.mutedMono),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AxColors.s1,
                borderRadius: BorderRadius.circular(AxRadius.xl),
                border: Border.all(color: AxColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in rows)
                    _DevRowTile(
                      row: r,
                      wide: wide,
                      onAction: (act) => _handleAction(context, r, act),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DevRowTile extends StatelessWidget {
  final DevRowModel row;
  final bool wide;
  final ValueChanged<String> onAction;

  const _DevRowTile({
    required this.row,
    required this.wide,
    required this.onAction,
  });

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
            Row(
              children: [
                for (final a in row.actions)
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: AxGhostButton(
                      label: a,
                      onTap: () => onAction(a),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
