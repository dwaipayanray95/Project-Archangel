import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../theme/tokens.dart';
import 'ax_widgets.dart';

/// The persistent top status bar — present on every screen, showing tunnel
/// state and live system stats, functioning like a real OS's menu bar.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final bool wide;

  const TopBar({super.key, required this.wide});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final accent = app.accent;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF080908),
        border: Border(bottom: BorderSide(color: AxColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final statsWide = constraints.maxWidth >= 900;
          return Row(
            children: [
          Container(
            width: 21,
            height: 21,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(7)),
            child: const Icon(Icons.shield_outlined, size: 12, color: AxColors.bg),
          ),
          if (wide) ...[
            const SizedBox(width: 9),
            Text('Archangel', style: AxTextStyles.sans.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AxColors.wash,
              borderRadius: BorderRadius.circular(AxRadius.pill),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusDot(color: accent, size: 6, pulse: true),
                const SizedBox(width: 7),
                Text('wg0', style: AxTextStyles.mono.copyWith(fontSize: 10.5, fontWeight: FontWeight.w500, color: accent)),
                if (wide) ...[
                  const SizedBox(width: 6),
                  Text('10.8.0.1', style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3)),
                ],
              ],
            ),
          ),
          const Spacer(),
          if (statsWide) ...[
            _BarStat(label: 'CPU', value: '18%', color: accent),
            _BarStat(label: 'MEM', value: '61%', color: AxColors.info),
            _BarStat(label: 'UP', value: '42d', color: AxColors.fg2, last: true),
          ],
          const SizedBox(width: 8),
              _SearchButton(wide: wide),
              const SizedBox(width: 5),
              _NotifButton(),
            ],
          );
        },
      ),
    );
  }
}

class _BarStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool last;
  const _BarStat({required this.label, required this.value, required this.color, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(right: last ? BorderSide.none : const BorderSide(color: AxColors.line)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AxTextStyles.mono.copyWith(fontSize: 9, letterSpacing: 1.1, color: AxColors.fg3)),
          const SizedBox(width: 6),
          Text(value, style: AxTextStyles.mono.copyWith(fontSize: 11.5, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  final bool wide;
  const _SearchButton({required this.wide});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return GestureDetector(
      onTap: app.openPalette,
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 7),
        decoration: BoxDecoration(
          color: AxColors.s2,
          borderRadius: BorderRadius.circular(AxRadius.pill),
          border: Border.all(color: AxColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 14, color: AxColors.fg2),
            if (wide) ...[
              const SizedBox(width: 7),
              Text('Search', style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AxColors.bg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AxColors.line),
                ),
                child: Text('⌘K', style: AxTextStyles.mono.copyWith(fontSize: 9.5, color: AxColors.fg3)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotifButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return GestureDetector(
      onTap: app.toggleNotif,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: app.notifOpen ? AxColors.s3 : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_outlined, size: 14, color: AxColors.fg2),
            Positioned(
              top: 3,
              right: 3,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: app.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AxColors.s1, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
