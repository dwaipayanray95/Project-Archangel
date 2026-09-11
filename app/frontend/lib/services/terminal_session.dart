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

  ArchangeldConnection? _backend;
  int _cols = 120;
  int _rows = 32;
  Timer? _pingTimer;

  TerminalSession({required this.label});

  void connect(ArchangeldConnection backend, {int cols = 120, int rows = 32}) {
    _backend = backend;
    _cols = cols;
    _rows = rows;
    _startConnection();
  }

  void _startConnection() {
    if (_backend == null) return;
    _sub?.cancel();
    _channel?.sink.close();
    _pingTimer?.cancel();

    _status = SessionStatus.connecting;
    _error = null;
    notifyListeners();

    final Uri uri;
    try {
      uri = _backend!.terminalWsUri();
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
        _pingTimer?.cancel();
        if (_status != SessionStatus.error) {
          _status = SessionStatus.closed;
          notifyListeners();
        }
      },
      onError: (e) {
        _pingTimer?.cancel();
        _status = SessionStatus.error;
        _error = e.toString();
        notifyListeners();
      },
      cancelOnError: true,
    );

    _channel!.ready.then((_) {
      resize(_cols, _rows);
      // Periodic ping every 45s to avoid backend 10m idle timeout during quiet sessions
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (_status == SessionStatus.connected) {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        }
      });
    }).catchError((Object e) {
      if (_status != SessionStatus.error) {
        _status = SessionStatus.error;
        _error = 'Could not open connection: $e';
        notifyListeners();
      }
    });
  }

  void reconnect() {
    _startConnection();
  }

  void clearOutput() {
    _output.clear();
    notifyListeners();
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
          final decoded = utf8.decode(base64.decode(data), allowMalformed: true);
          _output.write(_cleanAnsi(decoded));
        } catch (_) {
          return;
        }
        if (_status != SessionStatus.connected) _status = SessionStatus.connected;
        notifyListeners();
      case 'exit':
        _exitCode = frame['code'] as int?;
        _status = SessionStatus.closed;
        _pingTimer?.cancel();
        notifyListeners();
      case 'error':
        _error = frame['message'] as String?;
        _status = SessionStatus.error;
        _pingTimer?.cancel();
        notifyListeners();
      case 'pong':
        // Keep-alive acknowledged
        break;
    }
  }

  /// Cleans ANSI escape sequences for smooth legible display in standard text views
  /// while preserving spacing and structure.
  static final RegExp _ansiRegex = RegExp(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])');
  static String _cleanAnsi(String input) {
    // Strip standard ANSI CSI / OSC sequences
    return input.replaceAll(_ansiRegex, '');
  }

  void sendInput(String text) {
    if (_channel == null || text.isEmpty) return;
    _channel!.sink.add(jsonEncode({
      'type': 'stdin',
      'data': base64.encode(utf8.encode(text)),
    }));
  }

  void resize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
    _channel?.sink.add(jsonEncode({'type': 'resize', 'cols': cols, 'rows': rows}));
  }

  void close() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
