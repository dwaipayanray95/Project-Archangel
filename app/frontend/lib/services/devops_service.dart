import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/devops_model.dart';
import 'archangeld_connection.dart';

class DevopsService extends ChangeNotifier {
  List<DevRowModel> _services = [];
  List<DevRowModel> get services => _services;

  List<DevRowModel> _scheduled = [];
  List<DevRowModel> get scheduled => _scheduled;

  List<DevRowModel> _proxy = [];
  List<DevRowModel> get proxy => _proxy;

  List<DevRowModel> _deployments = [];
  List<DevRowModel> get deployments => _deployments;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Timer? _pollTimer;
  ArchangeldConnection? _backend;

  void init(ArchangeldConnection backend) {
    _backend = backend;
    fetchAll();

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      fetchAll();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchAll() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _services = [];
      _scheduled = [];
      _proxy = [];
      _deployments = [];
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      final headers = {'X-Archangel-Token': backend.token!};

      // Fetch all 4 sections in parallel for optimal responsiveness
      final results = await Future.wait([
        http.get(backend.devopsServicesHttpUri(), headers: headers).catchError((_) => http.Response('[]', 500)),
        http.get(backend.devopsScheduledHttpUri(), headers: headers).catchError((_) => http.Response('[]', 500)),
        http.get(backend.devopsProxyHttpUri(), headers: headers).catchError((_) => http.Response('[]', 500)),
        http.get(backend.devopsDeploymentsHttpUri(), headers: headers).catchError((_) => http.Response('[]', 500)),
      ]);

      final svcRes = results[0];
      if (svcRes.statusCode == 200) {
        final list = jsonDecode(svcRes.body) as List<dynamic>;
        _services = list.map((e) => DevRowModel.fromJson(e as Map<String, dynamic>)).toList();
      }

      final schedRes = results[1];
      if (schedRes.statusCode == 200) {
        final list = jsonDecode(schedRes.body) as List<dynamic>;
        _scheduled = list.map((e) => DevRowModel.fromJson(e as Map<String, dynamic>)).toList();
      }

      final proxyRes = results[2];
      if (proxyRes.statusCode == 200) {
        final list = jsonDecode(proxyRes.body) as List<dynamic>;
        _proxy = list.map((e) => DevRowModel.fromJson(e as Map<String, dynamic>)).toList();
      }

      final depRes = results[3];
      if (depRes.statusCode == 200) {
        final list = jsonDecode(depRes.body) as List<dynamic>;
        _deployments = list.map((e) => DevRowModel.fromJson(e as Map<String, dynamic>)).toList();
      }

      _error = null;
    } catch (e) {
      debugPrint('Error fetching devops data: $e');
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> triggerServiceAction(String name, String action) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return false;

    try {
      final res = await http.post(
        backend.devopsServiceActionHttpUri(name, action.toLowerCase()),
        headers: {'X-Archangel-Token': backend.token!},
      );
      fetchAll();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error triggering service action: $e');
      return false;
    }
  }

  Future<bool> triggerScheduled(String name) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return false;

    try {
      final res = await http.post(
        backend.devopsScheduledRunHttpUri(name),
        headers: {'X-Archangel-Token': backend.token!},
      );
      fetchAll();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error triggering scheduled timer: $e');
      return false;
    }
  }

  Future<String?> testProxy(String domain) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return null;

    try {
      final res = await http.post(
        backend.devopsProxyTestHttpUri(domain),
        headers: {'X-Archangel-Token': backend.token!},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['message'] as String?;
      }
    } catch (e) {
      debugPrint('Error testing proxy: $e');
    }
    return null;
  }

  Future<Map<String, String>?> runDeployment(String name) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return null;

    try {
      final res = await http.post(
        backend.devopsDeploymentRunHttpUri(name),
        headers: {'X-Archangel-Token': backend.token!},
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      fetchAll();
      return {
        'message': data['message'] as String? ?? (res.statusCode == 200 ? 'Success' : 'Failed'),
        'output': data['output'] as String? ?? '',
      };
    } catch (e) {
      debugPrint('Error running deployment: $e');
      return {'message': 'Error: $e', 'output': ''};
    }
  }
}
