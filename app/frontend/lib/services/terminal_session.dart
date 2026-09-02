import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'archangeld_connection.dart';

enum SessionStatus { connecting, connected, closed, error }

/// One real PTY session over archangeld's /ws/terminal, speaking its exact
/// wire protocol (see backend/internal/wsproto/wsproto.go): JSON frames
/// with a `type`, base64 `data` for stdin/stdout, `cols`/`rows` for resize.
///
/// This deliberately renders raw output (stripped of nothing) rather than
/// interpreting ANSI/VT100 escape sequences - it proves the pipe works
/// end-to-end (real bytes, both directions, over the real endpoint) rather
/// than being a full terminal emulator. A real emulator (cursor movement,
/// color, screen redraws) is separate scope - the `xterm` package is the
/// natural fit on top of this if/when that's wanted.
class TerminalSession extends ChangeNotifier {
  final String label;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  SessionStatus _status = SessionStatus.connecting;
  SessionStatus get status => _status;

  final StringBuffer _output = StringBuffer();
  String get output => _output.toString();

  String? _error;
  String? get error => _error;

  int? _exitCode;
  int? get exitCode => _exitCode;

  TerminalSession({required this.label});

  void connect(ArchangeldConnection backend, {int cols = 120, int rows = 32}) {
    final Uri uri;
    try {
      uri = backend.terminalWsUri();
    } on StateError catch (e) {
      _status = SessionStatus.error;
      _error = e.message;
      notifyListeners();
      return;
    }

    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (e) {
      _status = SessionStatus.error;
      _error = 'Could not open connection: $e';
      notifyListeners();
      return;
    }

    _sub = _channel!.stream.listen(
      _onMessage,
      onDone: () {
        if (_status != SessionStatus.error) {
          _status = SessionStatus.closed;
          notifyListeners();
        }
      },
      onError: (e) {
        _status = SessionStatus.error;
        _error = e.toString();
        notifyListeners();
      },
      cancelOnError: true,
    );

    // Real dimensions first, matching the backend's own comment that it
    // defaults to 24x80 and expects a resize frame right after connecting.
    // Waits for `ready` first: web_socket_channel's own docs say sink
    // writes aren't guaranteed to be delivered until the connection is
    // actually established, so sending immediately risked losing this
    // frame and leaving the PTY at the backend's 80x24 default.
    _channel!.ready.then((_) {
      resize(cols, rows);
    }).catchError((Object e) {
      // Already surfaced via the stream's onError above in the normal
      // case; this only fires if `ready` fails before the stream does.
      if (_status != SessionStatus.error) {
        _status = SessionStatus.error;
        _error = 'Could not open connection: $e';
        notifyListeners();
      }
    });
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (frame['type']) {
      case 'stdout':
        final data = frame['data'] as String?;
        if (data == null) return;
        try {
          _output.write(utf8.decode(base64.decode(data), allowMalformed: true));
        } catch (_) {
          return;
        }
        if (_status != SessionStatus.connected) _status = SessionStatus.connected;
        notifyListeners();
      case 'exit':
        _exitCode = frame['code'] as int?;
        _status = SessionStatus.closed;
        notifyListeners();
      case 'error':
        _error = frame['message'] as String?;
        _status = SessionStatus.error;
        notifyListeners();
      // 'pong' needs no handling; we don't currently send 'ping'.
    }
  }

  void sendInput(String text) {
    if (_channel == null || text.isEmpty) return;
    _channel!.sink.add(jsonEncode({
      'type': 'stdin',
      'data': base64.encode(utf8.encode(text)),
    }));
  }

  void resize(int cols, int rows) {
    _channel?.sink.add(jsonEncode({'type': 'resize', 'cols': cols, 'rows': rows}));
  }

  void close() {
    _sub?.cancel();
    _channel?.sink.close();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
