import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
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

  void _openSession(ArchangeldConnection backend, {String? initialDir, String? initialCommand, String? label, bool isShared = false}) {
    final sessionLabel = isShared ? 'live tmux' : (label ?? 'shell $_nextId');
    if (!isShared) _nextId++;
    final session = TerminalSession(label: sessionLabel);
    session.connect(backend);
    if (isShared) {
      // Connects or attaches to a shared persistent tmux session that survives disconnections
      Future.delayed(const Duration(milliseconds: 600), () {
        session.sendInput('tmux new-session -A -s archangel-live\n');
      });
    } else if (initialDir != null && initialDir.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 600), () {
        session.sendInput('cd "$initialDir"\n');
      });
    } else if (initialCommand != null && initialCommand.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 600), () {
        session.sendInput('$initialCommand\n');
      });
    }
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
    final app = context.watch<AppState>();

    final pendingDir = app.consumePendingTerminalDir();
    final pendingCmd = app.consumePendingTerminalCommand();

    if (pendingDir != null && backend.isPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sessions.isNotEmpty) {
          _sessions[_tab].sendInput('cd "$pendingDir"\n');
        } else {
          _openSession(backend, initialDir: pendingDir);
        }
      });
    } else if (pendingCmd != null && backend.isPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openSession(backend, initialCommand: pendingCmd, label: 'exec');
      });
    }

    if (!backend.isPaired) {
      return _UnpairedPrompt(onPaired: () => setState(() {}));
    }

    if (_sessions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sessions.isEmpty) _openSession(backend, initialDir: pendingDir);
      });
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AxColors.accent),
      );
    }

    final currentSession = _sessions[_tab];

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
              PopupMenuButton<String>(
                tooltip: 'New session',
                icon: const Icon(Icons.add_rounded, size: 16, color: AxColors.fg3),
                color: AxColors.s2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AxColors.line)),
                onSelected: (val) {
                  if (val == 'shell') {
                    _openSession(backend);
                  } else if (val == 'tmux') {
                    _openSession(backend, isShared: true);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'shell',
                    child: Row(
                      children: [
                        const Icon(Icons.terminal_rounded, size: 14, color: AxColors.accent),
                        const SizedBox(width: 8),
                        Text('Standard Shell', style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'tmux',
                    child: Row(
                      children: [
                        const Icon(Icons.hub_rounded, size: 14, color: AxColors.warn),
                        const SizedBox(width: 8),
                        Text('Persistent Tmux (Alive)', style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg)),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Quick action buttons: Copy output, clear screen
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 13, color: AxColors.fg3),
                tooltip: 'Copy buffer',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: currentSession.output));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Terminal output copied to clipboard'), duration: Duration(seconds: 1)),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.cleaning_services_rounded, size: 13, color: AxColors.fg3),
                tooltip: 'Clear screen',
                onPressed: () {
                  currentSession.clearOutput();
                  currentSession.sendInput('\x0c'); // Form feed / clear
                },
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2, right: 4, left: 4),
                child: Text(backend.host ?? '', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
              ),
            ],
          ),
        ),
        Expanded(child: _LivePane(key: ValueKey(currentSession), session: currentSession)),
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
        final isTmux = session.label.contains('tmux');
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
                if (isTmux) ...[
                  const Icon(Icons.hub_rounded, size: 11, color: AxColors.warn),
                  const SizedBox(width: 4),
                ],
                Text(session.label, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: selected ? AxColors.fg : AxColors.fg3)),
                const SizedBox(width: 7),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close_rounded, size: 12, color: AxColors.fg3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Renders one session's output, captures keystrokes, and presents
/// a mobile accessory bar for terminal controls (Ctrl, Esc, Tab, Arrows).
class _LivePane extends StatefulWidget {
  final TerminalSession session;
  const _LivePane({super.key, required this.session});

  @override
  State<_LivePane> createState() => _LivePaneState();
}

class _LivePaneState extends State<_LivePane> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _inputController = TextEditingController();
  bool _ctrlActive = false;

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _sendCtrlKey(String keyChar) {
    if (keyChar.isEmpty) return;
    final code = keyChar.toUpperCase().codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      final ctrlCode = code - 64; // 'A' (65) -> 1, 'C' (67) -> 3
      widget.session.sendInput(String.fromCharCode(ctrlCode));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    String? toSend;

    final isCtrl = HardwareKeyboard.instance.isControlPressed || _ctrlActive;

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
    } else if (isCtrl && key == LogicalKeyboardKey.keyC) {
      toSend = '\x03'; // Ctrl+C
    } else if (isCtrl && key == LogicalKeyboardKey.keyD) {
      toSend = '\x04'; // Ctrl+D
    } else if (isCtrl && key == LogicalKeyboardKey.keyZ) {
      toSend = '\x1a'; // Ctrl+Z
    } else if (isCtrl && key == LogicalKeyboardKey.keyL) {
      toSend = '\x0c'; // Ctrl+L
    } else if (event.character != null && event.character!.isNotEmpty) {
      if (_ctrlActive) {
        _sendCtrlKey(event.character!);
        setState(() => _ctrlActive = false);
        return KeyEventResult.handled;
      }
      toSend = event.character;
    }

    if (_ctrlActive && toSend != null) {
      setState(() => _ctrlActive = false);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Error or Reconnect Header
                  if (widget.session.status == SessionStatus.error || widget.session.status == SessionStatus.closed)
                    Container(
                      color: widget.session.status == SessionStatus.error ? AxColors.bad.withValues(alpha: 0.15) : AxColors.s2,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            widget.session.status == SessionStatus.error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                            size: 14,
                            color: widget.session.status == SessionStatus.error ? AxColors.bad : AxColors.fg2,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.session.status == SessionStatus.error
                                  ? (widget.session.error ?? 'Connection error')
                                  : 'Session closed (exit ${widget.session.exitCode ?? 0})',
                              style: AxTextStyles.mono.copyWith(
                                fontSize: 11.5,
                                color: widget.session.status == SessionStatus.error ? AxColors.bad : AxColors.fg2,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: AxColors.wash,
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 12, color: AxColors.accent),
                            label: Text('Reconnect', style: AxTextStyles.sans.copyWith(fontSize: 11.5, color: AxColors.accent, fontWeight: FontWeight.bold)),
                            onPressed: () => widget.session.reconnect(),
                          ),
                        ],
                      ),
                    ),

                  if (widget.session.status == SessionStatus.connecting)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: AxColors.warn)),
                          const SizedBox(width: 8),
                          Text('connecting to shell…', style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.fg3)),
                        ],
                      ),
                    ),

                  // Main Terminal Scroll Output
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: SelectableText(
                          widget.session.output.isEmpty && widget.session.status == SessionStatus.connected
                              ? 'Waiting for prompt…'
                              : widget.session.output,
                          style: AxTextStyles.mono.copyWith(fontSize: 12, height: 1.45, color: AxColors.fg),
                        ),
                      ),
                    ),
                  ),

                  // Mobile Virtual Keyboard Accessory Bar
                  _buildAccessoryBar(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccessoryBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AxColors.s1,
        border: Border(top: BorderSide(color: AxColors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _AccessoryKey(label: 'ESC', onTap: () => widget.session.sendInput('\x1b')),
            _AccessoryKey(label: 'TAB', onTap: () => widget.session.sendInput('\t')),
            _AccessoryKey(
              label: 'CTRL',
              isActive: _ctrlActive,
              onTap: () => setState(() => _ctrlActive = !_ctrlActive),
            ),
            _AccessoryKey(label: 'CTRL+C', onTap: () => widget.session.sendInput('\x03'), isAccent: true),
            _AccessoryKey(label: 'CTRL+D', onTap: () => widget.session.sendInput('\x04')),
            _AccessoryKey(label: '▲', onTap: () => widget.session.sendInput('\x1b[A')),
            _AccessoryKey(label: '▼', onTap: () => widget.session.sendInput('\x1b[B')),
            _AccessoryKey(label: 'CLEAR', onTap: () {
              widget.session.clearOutput();
              widget.session.sendInput('\x0c');
            }),
            _AccessoryKey(label: 'PASTE', onTap: () async {
              final data = await Clipboard.getData('text/plain');
              if (data?.text != null && data!.text!.isNotEmpty) {
                widget.session.sendInput(data.text!);
              }
            }),
          ],
        ),
      ),
    );
  }
}

class _AccessoryKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isAccent;

  const _AccessoryKey({
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = AxColors.s2;
    Color fg = AxColors.fg2;
    Border? border = Border.all(color: AxColors.line);

    if (isActive) {
      bg = AxColors.accent.withValues(alpha: 0.2);
      fg = AxColors.accent;
      border = Border.all(color: AxColors.accent);
    } else if (isAccent) {
      fg = AxColors.warn;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            border: border,
          ),
          child: Text(
            label,
            style: AxTextStyles.mono.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
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
