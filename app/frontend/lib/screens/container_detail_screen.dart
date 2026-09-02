import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';

/// Container detail — hosts the reusable stdout/stderr log widget also used
/// (in shape) by the dedicated Terminal section and "open in terminal" from
/// Files, per the design brief's "build once" note.
class ContainerDetailScreen extends StatelessWidget {
  final ContainerInfo container;
  const ContainerDetailScreen({super.key, required this.container});

  @override
  Widget build(BuildContext context) {
    final c = container;
    final dot = c.running ? AxColors.accent : AxColors.fg3;
    final logs = containerLogs[c.name] ?? const [];
    final stats = [
      ['CPU', '${c.cpu}%'],
      ['MEM', c.memLabel],
      ['PORTS', c.ports],
      ['ID', c.cid],
    ];

    return Scaffold(
      backgroundColor: AxColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            decoration: const BoxDecoration(color: AxColors.s1, border: Border(bottom: BorderSide(color: AxColors.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chevron_left_rounded, size: 16, color: AxColors.fg3),
                      Text('Containers', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: AxColors.fg3)),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 11,
                  runSpacing: 6,
                  children: [
                    StatusDot(color: dot, size: 8, pulse: c.running),
                    Text(c.name, style: AxTextStyles.mono.copyWith(fontSize: 17, fontWeight: FontWeight.w500)),
                    AxPill(text: c.running ? 'running' : 'stopped', color: dot),
                    Text(c.image, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3)),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        _DetailAction(label: 'Restart', icon: Icons.restart_alt_rounded),
                        SizedBox(width: 6),
                        _DetailAction(label: 'Stop', icon: Icons.stop_rounded),
                        SizedBox(width: 6),
                        _DetailAction(label: 'Shell', icon: Icons.chevron_right_rounded),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                LayoutBuilder(
                  builder: (context, cst) {
                    final cols = cst.maxWidth >= 500 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 9,
                      crossAxisSpacing: 9,
                      childAspectRatio: 3.2,
                      children: [
                        for (final s in stats)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                            decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(11), border: Border.all(color: AxColors.line)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(s[0], style: AxTextStyles.label),
                                const SizedBox(height: 2),
                                Text(s[1], style: AxTextStyles.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: LogPane(logs: logs))),
        ],
      ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  final String label;
  final IconData icon;
  const _DetailAction({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.line)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AxColors.fg2),
          const SizedBox(width: 6),
          Text(label, style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: AxColors.fg2)),
        ],
      ),
    );
  }
}

/// The shared stdout/stderr streamed-log widget (reused by container detail,
/// and shaped for reuse by Terminal / "open in terminal" from Files).
class LogPane extends StatelessWidget {
  final List<LogLine> logs;
  const LogPane({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF070807), borderRadius: BorderRadius.circular(14), border: Border.all(color: AxColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(color: AxColors.s1, border: Border(bottom: BorderSide(color: AxColors.line))),
            child: Row(
              children: [
                Text('STDOUT · STDERR', style: AxTextStyles.mono.copyWith(fontSize: 10.5, letterSpacing: 0.6, color: AxColors.fg3)),
                const Spacer(),
                const StatusDot(color: AxColors.accent, size: 5, pulse: true),
                const SizedBox(width: 5),
                Text('follow tail', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.accent)),
                const SizedBox(width: 10),
                const AxGhostButton(label: 'Wrap'),
                const SizedBox(width: 6),
                const AxGhostButton(label: 'Clear'),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 14),
              children: [
                for (final l in logs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.ts, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3.withValues(alpha: 0.6))),
                        SizedBox(
                          width: 42,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 11),
                            child: Text(l.level, style: AxTextStyles.mono.copyWith(fontSize: 11.5, fontWeight: FontWeight.w500, color: _lvlColor(l.level))),
                          ),
                        ),
                        Expanded(child: Text('${l.source}  ${l.text}', style: AxTextStyles.mono.copyWith(fontSize: 11.5))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _lvlColor(String level) => switch (level) {
        'WARN' => AxColors.warn,
        'ERROR' => AxColors.bad,
        _ => AxColors.fg2,
      };
}
