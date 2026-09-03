import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/archangeld_connection.dart';
import '../services/terminal_session.dart';
import '../theme/tokens.dart';
import '../widgets/ax_widgets.dart';
import '../widgets/pairing_dialog.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final List<TerminalSession> _sessions = [];
  int _tab = 0;
  int _nextId = 1;

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  void _openSession(ArchangeldConnection backend) {
    final session = TerminalSession(label: 'shell $_nextId');
    _nextId++;
    session.connect(backend);
    setState(() {
      _sessions.add(session);
      _tab = _sessions.length - 1;
    });
  }

  void _closeSession(int index) {
    final session = _sessions[index];
    session.close();
    session.dispose();
    setState(() {
      _sessions.removeAt(index);
      if (_tab >= _sessions.length) _tab = _sessions.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<ArchangeldConnection>();

    if (!backend.isPaired) {
      return _UnpairedPrompt(onPaired: () => setState(() {}));
    }

    if (_sessions.isEmpty) {
      // Auto-open the first tab as soon as we're paired, so Terminal
      // "just works" the way the mockup implies rather than requiring an
      // extra click.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sessions.isEmpty) _openSession(backend);
      });
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AxColors.accent),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
          decoration: const BoxDecoration(color: AxColors.s1, border: Border(bottom: BorderSide(color: AxColors.line))),
          child: Row(
            children: [
              for (var i = 0; i < _sessions.length; i++)
                _TermTab(
                  session: _sessions[i],
                  selected: i == _tab,
                  onTap: () => setState(() => _tab = i),
                  onClose: () => _closeSession(i),
                ),
              const SizedBox(width: 5),
              GestureDetector(
                onTap: () => _openSession(backend),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Icon(Icons.add_rounded, size: 16, color: AxColors.fg3),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 7, right: 4),
                child: Text(backend.host ?? '', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
              ),
            ],
          ),
        ),
        Expanded(child: _LivePane(key: ValueKey(_sessions[_tab]), session: _sessions[_tab])),
      ],
    );
  }
}

class _TermTab extends StatelessWidget {
  final TerminalSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _TermTab({required this.session, required this.selected, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final dot = switch (session.status) {
          SessionStatus.connected => AxColors.accent,
          SessionStatus.connecting => AxColors.warn,
          SessionStatus.error => AxColors.bad,
          SessionStatus.closed => AxColors.fg3,
        };
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AxMotion.base,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF070807) : Colors.transparent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 5, height: 5, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Text(session.label, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: selected ? AxColors.fg : AxColors.fg3)),
                const SizedBox(width: 7),
                GestureDetector(
                  onTap: onClose,
                  child: Icon(Icons.close_rounded, size: 12, color: AxColors.fg3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Renders one session's raw output and captures keystrokes to send as
/// stdin. Output is unprocessed text (no ANSI/cursor-movement handling) -
/// see TerminalSession's doc comment for why that's the deliberate scope
/// here.
class _LivePane extends StatefulWidget {
  final TerminalSession session;
  const _LivePane({super.key, required this.session});

  @override
  State<_LivePane> createState() => _LivePaneState();
}

class _LivePaneState extends State<_LivePane> {
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    String? toSend;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      toSend = '\r';
    } else if (key == LogicalKeyboardKey.backspace) {
      toSend = '\x7f';
    } else if (key == LogicalKeyboardKey.tab) {
      toSend = '\t';
    } else if (key == LogicalKeyboardKey.escape) {
      toSend = '\x1b';
    } else if (key == LogicalKeyboardKey.arrowUp) {
      toSend = '\x1b[A';
    } else if (key == LogicalKeyboardKey.arrowDown) {
      toSend = '\x1b[B';
    } else if (key == LogicalKeyboardKey.arrowRight) {
      toSend = '\x1b[C';
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      toSend = '\x1b[D';
    } else if (key == LogicalKeyboardKey.keyC && HardwareKeyboard.instance.isControlPressed) {
      toSend = '\x03'; // Ctrl+C
    } else if (key == LogicalKeyboardKey.keyD && HardwareKeyboard.instance.isControlPressed) {
      toSend = '\x04'; // Ctrl+D
    } else if (event.character != null && event.character!.isNotEmpty) {
      toSend = event.character;
    }

    if (toSend != null) {
      widget.session.sendInput(toSend);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        _scrollToBottom();
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            onTap: () => _focus.requestFocus(),
            child: Container(
              width: double.infinity,
              color: const Color(0xFF070807),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.session.status == SessionStatus.error)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        widget.session.error ?? 'Connection error',
                        style: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.bad),
                      ),
                    ),
                  if (widget.session.status == SessionStatus.connecting)
                    Text('connecting…', style: AxTextStyles.mono.copyWith(fontSize: 12, color: AxColors.fg3)),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: SelectableText(
                        widget.session.output,
                        style: AxTextStyles.mono.copyWith(fontSize: 12, height: 1.5, color: AxColors.fg),
                      ),
                    ),
                  ),
                  if (widget.session.status == SessionStatus.closed)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'session ended${widget.session.exitCode != null ? " (exit ${widget.session.exitCode})" : ""}',
                        style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UnpairedPrompt extends StatelessWidget {
  final VoidCallback onPaired;
  const _UnpairedPrompt({required this.onPaired});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AxCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No backend paired', style: AxTextStyles.sans.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Terminal needs a paired backend to open a real shell session. Run `archangeld pair <name>` on the server and paste (or scan) the code it prints.',
                style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2, height: 1.5),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => _showPairDialog(context, onPaired),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: AxColors.wash,
                      borderRadius: BorderRadius.circular(AxRadius.pill),
                      border: Border.all(color: AxColors.accent.withValues(alpha: 0.22)),
                    ),
                    child: Text('Pair backend', style: AxTextStyles.sans.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AxColors.accent)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPairDialog(BuildContext context, VoidCallback onPaired) {
    // ArchangeldConnection.pair() notifies listeners itself, and
    // TerminalScreen.build watches it - onPaired is just a belt-and-braces
    // rebuild trigger, the actual pairing happens in the shared dialog.
    showPairingDialog(context).then((_) => onPaired());
  }
}
