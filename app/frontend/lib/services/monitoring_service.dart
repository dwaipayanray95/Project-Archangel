import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/system_metrics.dart';
import 'archangeld_connection.dart';

enum MonitoringStatus { disconnected, connecting, connected, error }

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
    if (_backend == null || !_backend!.isPaired) return;
    try {
      final res = await http.get(
        _backend!.metricsHttpUri(),
        headers: {'X-Archangel-Token': _backend!.token!},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _metrics = SystemMetrics.fromJson(data);
        if (_status != MonitoringStatus.connected) {
          _status = MonitoringStatus.connected;
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> fetchProcesses() async {
    if (_backend == null || !_backend!.isPaired) return;
    try {
      final res = await http.get(
        _backend!.processesHttpUri(),
        headers: {'X-Archangel-Token': _backend!.token!},
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
      }
    } catch (_) {}
  }

  Future<bool> killProcess(int pid, {bool force = false}) async {
    if (_backend == null || !_backend!.isPaired) return false;
    try {
      final res = await http.post(
        _backend!.processKillHttpUri(pid),
        headers: {
          'X-Archangel-Token': _backend!.token!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'force': force}),
      );
      if (res.statusCode == 200) {
        await fetchProcesses();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> reniceProcess(int pid, int priority) async {
    if (_backend == null || !_backend!.isPaired) return false;
    try {
      final res = await http.post(
        _backend!.processReniceHttpUri(pid),
        headers: {
          'X-Archangel-Token': _backend!.token!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'priority': priority}),
      );
      if (res.statusCode == 200) {
        await fetchProcesses();
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
