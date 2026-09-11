import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/container_model.dart';
import '../services/archangeld_connection.dart';
import '../services/containers_service.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import 'container_detail_screen.dart';

enum _View { cards, table }

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  _View _view = _View.cards;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backend = context.read<ArchangeldConnection>();
      context.read<ContainersService>().init(backend);
    });
  }

  void _openDetail(DockerContainerItem c) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContainerDetailScreen(container: c)));
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ContainersService>();
    final overview = svc.overview;

    final containers = overview?.containers ?? [];
    final running = overview?.runningCount ?? containers.where((c) => c.running).length;
    final stopped = overview?.stoppedCount ?? (containers.length - running);
    final version = overview?.engineVersion ?? 'docker';
    final imagesSize = overview?.totalImagesSize ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Containers', style: AxTextStyles.h1),
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
                  Text(
                    'docker $version · $running running · $stopped stopped · $imagesSize images',
                    style: AxTextStyles.mutedMono,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AxSegmented<_View>(
                    values: _View.values,
                    selected: _view,
                    label: (v) => v == _View.cards ? 'Cards' : 'Table',
                    onSelect: (v) => setState(() => _view = v),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(AxRadius.pill),
                    onTap: () => svc.fetchContainers(),
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
            ],
          ),
          const SizedBox(height: 15),
          if (_view == _View.cards)
            _CardsView(
              containers: containers,
              stacks: overview?.stacks ?? [],
              stackMeta: overview?.stackMeta ?? {},
              onOpen: _openDetail,
            )
          else
            _TableView(
              containers: containers,
              onOpen: _openDetail,
              onAction: (c, action) async {
                final success = await svc.triggerAction(c.id, action);
                if (context.mounted && !success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to $action container ${c.name}')),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _CardsView extends StatelessWidget {
  final List<DockerContainerItem> containers;
  final List<String> stacks;
  final Map<String, String> stackMeta;
  final ValueChanged<DockerContainerItem> onOpen;

  const _CardsView({
    required this.containers,
    required this.stacks,
    required this.stackMeta,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStacks = stacks.isNotEmpty
        ? stacks
        : containers.map((c) => c.stack).toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stack in effectiveStacks)
          if (containers.any((c) => c.stack == stack))
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(stack.toUpperCase(), style: AxTextStyles.mono.copyWith(fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: 0.8, color: AxColors.fg2)),
                      const SizedBox(width: 9),
                      Text(stackMeta[stack] ?? '', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                      const SizedBox(width: 9),
                      const Expanded(child: Divider(color: AxColors.line, height: 1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
                      final items = containers.where((item) => item.stack == stack).toList();
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.2,
                        children: [for (final ct in items) _ContainerCard(c: ct, onTap: () => onOpen(ct))],
                      );
                    },
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _ContainerCard extends StatelessWidget {
  final DockerContainerItem c;
  final VoidCallback onTap;
  const _ContainerCard({required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dot = c.running ? AxColors.accent : AxColors.fg3;
    return AxCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              StatusDot(color: dot, size: 7, pulse: c.running),
              const SizedBox(width: 8),
              Expanded(child: Text(c.name, style: AxTextStyles.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              AxPill(text: c.running ? c.uptime : (c.uptime.isNotEmpty ? c.uptime : 'stopped'), color: dot),
            ],
          ),
          const SizedBox(height: 3),
          Text(c.image, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _MiniMeter(label: 'CPU', value: '${c.cpu}%', frac: (c.cpu / 10).clamp(0, 1), color: AxColors.accent)),
              const SizedBox(width: 14),
              Expanded(child: _MiniMeter(label: 'MEM', value: c.memLabel, frac: (c.memMb / 1600).clamp(0, 1), color: AxColors.info)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMeter extends StatelessWidget {
  final String label;
  final String value;
  final double frac;
  final Color color;
  const _MiniMeter({required this.label, required this.value, required this.frac, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AxTextStyles.mono.copyWith(fontSize: 9.5, color: AxColors.fg3)),
            Text(value, style: AxTextStyles.mono.copyWith(fontSize: 9.5, color: AxColors.fg)),
          ],
        ),
        const SizedBox(height: 4),
        AxMeter(value: frac, color: color),
      ],
    );
  }
}

class _TableView extends StatelessWidget {
  final List<DockerContainerItem> containers;
  final ValueChanged<DockerContainerItem> onOpen;
  final void Function(DockerContainerItem, String) onAction;

  const _TableView({
    required this.containers,
    required this.onOpen,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AxColors.s1, borderRadius: BorderRadius.circular(AxRadius.xl), border: Border.all(color: AxColors.line)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 680,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AxColors.s2,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    Expanded(flex: 13, child: Text('NAME', style: AxTextStyles.label)),
                    Expanded(flex: 17, child: Text('IMAGE', style: AxTextStyles.label)),
                    Expanded(flex: 9, child: Text('UPTIME', style: AxTextStyles.label)),
                    Expanded(flex: 7, child: Text('CPU', style: AxTextStyles.label, textAlign: TextAlign.right)),
                    Expanded(flex: 8, child: Text('MEM', style: AxTextStyles.label, textAlign: TextAlign.right)),
                    const Expanded(flex: 9, child: SizedBox()),
                  ],
                ),
              ),
              for (final c in containers)
                GestureDetector(
                  onTap: () => onOpen(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x0BE8F0E6)))),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 13,
                          child: Row(
                            children: [
                              StatusDot(color: c.running ? AxColors.accent : AxColors.fg3, size: 6, pulse: c.running),
                              const SizedBox(width: 8),
                              Expanded(child: Text(c.name, style: AxTextStyles.mono.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                        Expanded(flex: 17, child: Text(c.image, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3), overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 9, child: Text(c.uptime, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: c.running ? AxColors.accent : AxColors.fg3))),
                        Expanded(flex: 7, child: Text('${c.cpu}%', textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11))),
                        Expanded(flex: 8, child: Text(c.memLabel, textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2))),
                        Expanded(
                          flex: 9,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _IconBtn(
                                icon: c.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                onTap: () => onAction(c, c.running ? 'stop' : 'start'),
                              ),
                              const SizedBox(width: 4),
                              _IconBtn(
                                icon: Icons.restart_alt_rounded,
                                onTap: () => onAction(c, 'restart'),
                              ),
                              const SizedBox(width: 4),
                              _IconBtn(
                                icon: Icons.chevron_right_rounded,
                                onTap: () => onOpen(c),
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
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AxColors.line)),
        child: Icon(icon, size: 13, color: AxColors.fg2),
      ),
    );
  }
}
