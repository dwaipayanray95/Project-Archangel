import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../theme/tokens.dart';

class NotifPanel extends StatelessWidget {
  const NotifPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final items = feedPool.take(4).toList();
    return Positioned(
      top: 55,
      right: 10,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AxMotion.pop,
        curve: AxMotion.easeOutSoft,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * -12), child: child),
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 292,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AxColors.s2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AxColors.line2),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 50, offset: Offset(0, 20))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
                  child: Row(
                    children: [
                      Text('NOTIFICATIONS', style: AxTextStyles.sans.copyWith(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AxColors.fg3)),
                      const Spacer(),
                      Text('${items.length} new', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                    ],
                  ),
                ),
                for (final n in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(width: 6, height: 6, decoration: BoxDecoration(color: n.color, shape: BoxShape.circle)),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    style: AxTextStyles.sans.copyWith(fontSize: 12.5, height: 1.35),
                                    children: [
                                      TextSpan(text: '${n.actor} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      TextSpan(text: n.text, style: const TextStyle(color: AxColors.fg2)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(n.detail, style: AxTextStyles.mono.copyWith(fontSize: 10.5, color: AxColors.fg3)),
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
      ),
    );
  }
}
