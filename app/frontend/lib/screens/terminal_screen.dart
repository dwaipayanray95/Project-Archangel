import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../theme/tokens.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> with SingleTickerProviderStateMixin {
  int _tab = 0;
  late final AnimationController _cursor = AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..repeat();

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = termSessions[_tab];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
          decoration: const BoxDecoration(color: AxColors.s1, border: Border(bottom: BorderSide(color: AxColors.line))),
          child: Row(
            children: [
              for (var i = 0; i < termSessions.length; i++) _TermTab(session: termSessions[i], selected: i == _tab, onTap: () => setState(() => _tab = i)),
              const SizedBox(width: 5),
              Icon(Icons.add_rounded, size: 16, color: AxColors.fg3),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(session.meta, style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: const Color(0xFF070807),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in session.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      child: Text(
                        l[0],
                        style: AxTextStyles.mono.copyWith(
                          fontSize: 12,
                          height: 1.66,
                          fontWeight: l[1] == 'p' ? FontWeight.w500 : FontWeight.w400,
                          color: l[1] == 'p' ? AxColors.accent : (l[1] == 'h' ? AxColors.fg2 : AxColors.fg),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Text(session.prompt, style: AxTextStyles.mono.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AxColors.accent)),
                      FadeTransition(
                        opacity: _cursor.drive(TweenSequence([
                          TweenSequenceItem(tween: ConstantTween(1.0), weight: 49),
                          TweenSequenceItem(tween: ConstantTween(0.0), weight: 51),
                        ])),
                        child: Container(width: 7.4, height: 15, margin: const EdgeInsets.only(left: 2), color: AxColors.accent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TermTab extends StatelessWidget {
  final TermSession session;
  final bool selected;
  final VoidCallback onTap;
  const _TermTab({required this.session, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AxMotion.base,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF070807) : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 5, height: 5, decoration: BoxDecoration(color: session.dot, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(session.label, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: selected ? AxColors.fg : AxColors.fg3)),
          ],
        ),
      ),
    );
  }
}
