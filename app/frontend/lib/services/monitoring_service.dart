import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/system_metrics.dart';
import 'archangeld_connection.dart';

enum MonitoringStatus { disconnected, connecting, connected, error }

class ProcessActionResult {
  final bool success;
  final String message;

  const ProcessActionResult({required this.success, required this.message});
}

/// Service responsible for real-time and snapshot metrics, plus process listings.
class MonitoringService extends ChangeNotifier {
  MonitoringStatus _status = MonitoringStatus.disconnected;
  MonitoringStatus get status => _status;

  SystemMetrics? _metrics;
  SystemMetrics? get metrics => _metrics;

  List<LiveProcessInfo> _processes = [];
  List<LiveProcessInfo> get processes => _processes;

  int _totalProcesses = 0;
  int get totalProcesses => _totalProcesses;

  String? _error;
  String? get error => _error;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  Timer? _procTimer;
  ArchangeldConnection? _backend;

  bool get isConnected => _status == MonitoringStatus.connected;

  void start(ArchangeldConnection backend) {
    if (_backend == backend && _status == MonitoringStatus.connected) {
      return;
    }
    _backend = backend;
    _connect();
  }

  void stop() {
    _wsSub?.cancel();
    _wsSub = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
    _procTimer?.cancel();
    _procTimer = null;
    _status = MonitoringStatus.disconnected;
    notifyListeners();
  }

  void _connect() {
    if (_backend == null || !_backend!.isPaired) {
      _status = MonitoringStatus.disconnected;
      notifyListeners();
      return;
    }

    _status = MonitoringStatus.connecting;
    _error = null;
    notifyListeners();

    // 1. Initial snapshot fetch via REST
    fetchSnapshot();
    fetchProcesses();

    // 2. Open live WebSocket stream
    try {
      final uri = _backend!.statsWsUri();
      _wsChannel = WebSocketChannel.connect(uri);
      _wsSub = _wsChannel!.stream.listen(
        _onWsMessage,
        onDone: () {
          if (_status == MonitoringStatus.connected) {
            _status = MonitoringStatus.disconnected;
            notifyListeners();
            _scheduleReconnect();
          }
        },
        onError: (err) {
          _status = MonitoringStatus.error;
          _error = err.toString();
          notifyListeners();
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _status = MonitoringStatus.error;
      _error = e.toString();
      notifyListeners();
      _scheduleReconnect();
    }

    // 3. Periodic process list refresh every 5 seconds
    _procTimer?.cancel();
    _procTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      fetchProcesses();
    });
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 4), () {
      if (_status != MonitoringStatus.connected && _backend != null && _backend!.isPaired) {
        _connect();
      }
    });
  }

  void _onWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      _metrics = SystemMetrics.fromJson(data);
      _status = MonitoringStatus.connected;
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error parsing ws stats: $e');
    }
  }

  Future<void> fetchSnapshot() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) return;
    final token = backend.token;
    if (token == null || token.isEmpty) return;

    try {
      final res = await http.get(
        backend.metricsHttpUri(),
        headers: {'X-Archangel-Token': token},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _metrics = SystemMetrics.fromJson(data);
        if (_status != MonitoringStatus.connected) {
          _status = MonitoringStatus.connected;
        }
        notifyListeners();
      } else {
        debugPrint('fetchSnapshot failed: HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchSnapshot error: $e');
    }
  }

  Future<void> fetchProcesses() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) return;
    final token = backend.token;
    if (token == null || token.isEmpty) return;

    try {
      final res = await http.get(
        backend.processesHttpUri(),
        headers: {'X-Archangel-Token': token},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['processes'] as List<dynamic>?)
                ?.map((e) => LiveProcessInfo.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _processes = list;
        _totalProcesses = (data['total_count'] as num?)?.toInt() ?? list.length;
        notifyListeners();
      } else {
        debugPrint('fetchProcesses failed: HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchProcesses error: $e');
    }
  }

  Future<ProcessActionResult> killProcess(int pid, {bool force = false}) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) {
      return const ProcessActionResult(success: false, message: 'Backend is not paired');
    }
    final token = backend.token;
    if (token == null || token.isEmpty) {
      return const ProcessActionResult(success: false, message: 'Missing authentication token');
    }

    try {
      final res = await http.post(
        backend.processKillHttpUri(pid),
        headers: {
          'X-Archangel-Token': token,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'force': force}),
      );
      if (res.statusCode == 200) {
        await fetchProcesses();
        return const ProcessActionResult(success: true, message: 'Process terminated');
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        return const ProcessActionResult(success: false, message: 'Unauthorized (invalid or expired token)');
      } else {
        final errText = res.body.isNotEmpty ? res.body.trim() : 'HTTP ${res.statusCode}';
        return ProcessActionResult(success: false, message: 'Server error: $errText');
      }
    } catch (e) {
      return ProcessActionResult(success: false, message: 'Connection failed: $e');
    }
  }

  Future<ProcessActionResult> reniceProcess(int pid, int priority) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) {
      return const ProcessActionResult(success: false, message: 'Backend is not paired');
    }
    final token = backend.token;
    if (token == null || token.isEmpty) {
      return const ProcessActionResult(success: false, message: 'Missing authentication token');
    }

    try {
      final res = await http.post(
        backend.processReniceHttpUri(pid),
        headers: {
          'X-Archangel-Token': token,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'priority': priority}),
      );
      if (res.statusCode == 200) {
        await fetchProcesses();
        return ProcessActionResult(success: true, message: 'Priority updated to $priority');
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        return const ProcessActionResult(success: false, message: 'Unauthorized (invalid or expired token)');
      } else {
        final errText = res.body.isNotEmpty ? res.body.trim() : 'HTTP ${res.statusCode}';
        return ProcessActionResult(success: false, message: 'Server error: $errText');
      }
    } catch (e) {
      return ProcessActionResult(success: false, message: 'Connection failed: $e');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
