import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../data/mock_data.dart';
import '../models/container_model.dart';
import 'archangeld_connection.dart';

class ContainersService extends ChangeNotifier {
  DockerOverviewModel? _overview;
  DockerOverviewModel? get overview => _overview;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Timer? _pollTimer;
  ArchangeldConnection? _backend;

  // Real-time log streaming state
  String? _activeLogContainerId;
  String? get activeLogContainerId => _activeLogContainerId;

  final List<DockerLogEntry> _liveLogs = [];
  List<DockerLogEntry> get liveLogs => _liveLogs;

  WebSocketChannel? _logWs;
  StreamSubscription? _logSub;

  void init(ArchangeldConnection backend) {
    _backend = backend;
    fetchContainers();

    // Poll periodically (every 4s)
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      fetchContainers();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _closeLogsStream();
    super.dispose();
  }

  Future<void> fetchContainers() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _loadMockOverview();
      notifyListeners();
      return;
    }

    try {
      final res = await http.get(
        backend.dockerContainersHttpUri(),
        headers: {'X-Archangel-Token': backend.token!},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _overview = DockerOverviewModel.fromJson(data);
        _error = null;
      } else {
        _loadMockOverview();
      }
    } catch (e) {
      debugPrint('Error fetching docker containers: $e');
      if (_overview == null) {
        _loadMockOverview();
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _loadMockOverview() {
    final mockItems = containers.map((c) => DockerContainerItem(
      id: c.cid,
      name: c.name,
      image: c.image,
      stack: c.stack,
      state: c.state,
      status: c.uptime,
      uptime: c.uptime,
      cpu: c.cpu,
      memMb: c.memMb,
      memLabel: c.memLabel,
      ports: c.ports,
      cid: c.cid,
      running: c.running,
    )).toList();

    _overview = DockerOverviewModel(
      dockerAvailable: false,
      engineVersion: '27.1.1 (offline demo)',
      runningCount: mockItems.where((c) => c.running).length,
      stoppedCount: mockItems.where((c) => !c.running).length,
      totalImagesSize: '6.4 GB',
      containers: mockItems,
      stacks: stackOrder,
      stackMeta: stackMeta,
    );
    _loading = false;
  }

  Future<bool> triggerAction(String containerId, String action) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      // Demo simulated action
      await Future.delayed(const Duration(milliseconds: 400));
      fetchContainers();
      return true;
    }

    try {
      final res = await http.post(
        backend.dockerContainerActionHttpUri(containerId, action),
        headers: {'X-Archangel-Token': backend.token!},
      );

      fetchContainers();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error triggering container action: $e');
      return false;
    }
  }

  void startLogStream(String containerId) {
    _closeLogsStream();
    _activeLogContainerId = containerId;
    _liveLogs.clear();
    notifyListeners();

    final backend = _backend;
    if (backend == null || !backend.isPaired) {
      // Fallback to mock logs
      final mock = containerLogs[containerId] ?? containerLogs['caddy'] ?? const [];
      for (final l in mock) {
        _liveLogs.add(DockerLogEntry(ts: l.ts, level: l.level, source: l.source, text: l.text));
      }
      notifyListeners();
      return;
    }

    try {
      final uri = backend.dockerContainerLogsWsUri(containerId);
      _logWs = WebSocketChannel.connect(uri);
      _logSub = _logWs!.stream.listen((event) {
        try {
          final data = jsonDecode(event.toString()) as Map<String, dynamic>;
          final entry = DockerLogEntry.fromJson(data);
          _liveLogs.add(entry);
          if (_liveLogs.length > 500) {
            _liveLogs.removeAt(0);
          }
          notifyListeners();
        } catch (_) {}
      }, onError: (err) {
        debugPrint('Log WS error: $err');
      });
    } catch (e) {
      debugPrint('Log connect error: $e');
    }
  }

  void stopLogStream() {
    _closeLogsStream();
    notifyListeners();
  }

  void _closeLogsStream() {
    _logSub?.cancel();
    _logSub = null;
    _logWs?.sink.close();
    _logWs = null;
    _activeLogContainerId = null;
  }
}
