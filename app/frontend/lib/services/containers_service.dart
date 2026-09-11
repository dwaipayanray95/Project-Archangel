import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
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
      _overview = const DockerOverviewModel(
        dockerAvailable: false,
        engineVersion: 'disconnected',
        runningCount: 0,
        stoppedCount: 0,
        totalImagesSize: '0 B',
        containers: [],
        stacks: [],
        stackMeta: {},
      );
      _loading = false;
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
        _error = 'Failed to fetch containers (HTTP ${res.statusCode})';
      }
    } catch (e) {
      debugPrint('Error fetching docker containers: $e');
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> triggerAction(String containerId, String action) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return false;
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
    if (backend == null || !backend.isPaired || backend.token == null) {
      _liveLogs.add(DockerLogEntry(
        ts: DateTime.now().toIso8601String().substring(11, 19),
        level: 'INFO',
        source: 'archangeld',
        text: 'Waiting for backend connection to stream container logs...',
      ));
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
