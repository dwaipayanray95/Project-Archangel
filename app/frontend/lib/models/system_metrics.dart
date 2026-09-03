class CoreMetric {
  final int id;
  final double usagePercent;

  const CoreMetric({required this.id, required this.usagePercent});

  factory CoreMetric.fromJson(Map<String, dynamic> json) {
    return CoreMetric(
      id: (json['id'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CPUMetrics {
  final double usagePercent;
  final List<CoreMetric> cores;
  final List<double> history;

  const CPUMetrics({
    required this.usagePercent,
    required this.cores,
    required this.history,
  });

  factory CPUMetrics.fromJson(Map<String, dynamic> json) {
    final coresList = (json['cores'] as List<dynamic>?)
            ?.map((e) => CoreMetric.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final hist = (json['history'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];
    return CPUMetrics(
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      cores: coresList,
      history: hist,
    );
  }
}

class MemoryMetrics {
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  final double usagePercent;
  final List<double> history;

  const MemoryMetrics({
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
    required this.usagePercent,
    required this.history,
  });

  factory MemoryMetrics.fromJson(Map<String, dynamic> json) {
    final hist = (json['history'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];
    return MemoryMetrics(
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      availableBytes: (json['available_bytes'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      history: hist,
    );
  }

  double get totalGb => totalBytes / (1024 * 1024 * 1024);
  double get usedGb => usedBytes / (1024 * 1024 * 1024);
  double get availableGb => availableBytes / (1024 * 1024 * 1024);
}

class MountMetric {
  final String mountPoint;
  final String device;
  final int totalBytes;
  final int usedBytes;

  const MountMetric({
    required this.mountPoint,
    required this.device,
    required this.totalBytes,
    required this.usedBytes,
  });

  factory MountMetric.fromJson(Map<String, dynamic> json) {
    return MountMetric(
      mountPoint: json['mount_point'] as String? ?? '/',
      device: json['device'] as String? ?? '',
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
    );
  }

  double get usagePercent =>
      totalBytes > 0 ? (usedBytes / totalBytes) * 100.0 : 0.0;
}

class DiskMetrics {
  final double readBytesPerSec;
  final double writeBytesPerSec;
  final int totalBytes;
  final int usedBytes;
  final double usagePercent;
  final List<MountMetric> mounts;
  final List<double> history;

  const DiskMetrics({
    required this.readBytesPerSec,
    required this.writeBytesPerSec,
    required this.totalBytes,
    required this.usedBytes,
    required this.usagePercent,
    required this.mounts,
    required this.history,
  });

  factory DiskMetrics.fromJson(Map<String, dynamic> json) {
    final mountsList = (json['mounts'] as List<dynamic>?)
            ?.map((e) => MountMetric.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final hist = (json['history'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];
    return DiskMetrics(
      readBytesPerSec: (json['read_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      writeBytesPerSec:
          (json['write_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      mounts: mountsList,
      history: hist,
    );
  }

  double get readMbPerSec => readBytesPerSec / (1024 * 1024);
  double get writeMbPerSec => writeBytesPerSec / (1024 * 1024);
  double get totalMbPerSec => readMbPerSec + writeMbPerSec;
  double get totalGb => totalBytes / (1024 * 1024 * 1024);
  double get usedGb => usedBytes / (1024 * 1024 * 1024);
}

class NetInterfaceMetric {
  final String name;
  final double rxBytesPerSec;
  final double txBytesPerSec;

  const NetInterfaceMetric({
    required this.name,
    required this.rxBytesPerSec,
    required this.txBytesPerSec,
  });

  factory NetInterfaceMetric.fromJson(Map<String, dynamic> json) {
    return NetInterfaceMetric(
      name: json['name'] as String? ?? '',
      rxBytesPerSec: (json['rx_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      txBytesPerSec: (json['tx_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
    );
  }

  double get rxMbPerSec => rxBytesPerSec / (1024 * 1024);
  double get txMbPerSec => txBytesPerSec / (1024 * 1024);
}

class NetworkMetrics {
  final double rxBytesPerSec;
  final double txBytesPerSec;
  final List<NetInterfaceMetric> interfaces;
  final List<double> history;

  const NetworkMetrics({
    required this.rxBytesPerSec,
    required this.txBytesPerSec,
    required this.interfaces,
    required this.history,
  });

  factory NetworkMetrics.fromJson(Map<String, dynamic> json) {
    final ifaces = (json['interfaces'] as List<dynamic>?)
            ?.map((e) => NetInterfaceMetric.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final hist = (json['history'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];
    return NetworkMetrics(
      rxBytesPerSec: (json['rx_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      txBytesPerSec: (json['tx_bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      interfaces: ifaces,
      history: hist,
    );
  }

  double get rxMbPerSec => rxBytesPerSec / (1024 * 1024);
  double get txMbPerSec => txBytesPerSec / (1024 * 1024);
  double get totalMbPerSec => rxMbPerSec + txMbPerSec;
}

class SystemMetrics {
  final int timestamp;
  final CPUMetrics cpu;
  final MemoryMetrics memory;
  final DiskMetrics disk;
  final NetworkMetrics network;

  const SystemMetrics({
    required this.timestamp,
    required this.cpu,
    required this.memory,
    required this.disk,
    required this.network,
  });

  factory SystemMetrics.fromJson(Map<String, dynamic> json) {
    return SystemMetrics(
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      cpu: CPUMetrics.fromJson(
          (json['cpu'] as Map<String, dynamic>?) ?? const {}),
      memory: MemoryMetrics.fromJson(
          (json['memory'] as Map<String, dynamic>?) ?? const {}),
      disk: DiskMetrics.fromJson(
          (json['disk'] as Map<String, dynamic>?) ?? const {}),
      network: NetworkMetrics.fromJson(
          (json['network'] as Map<String, dynamic>?) ?? const {}),
    );
  }
}

class LiveProcessInfo {
  final int pid;
  final String name;
  final String user;
  final double cpu;
  final double mem;
  final String state;

  const LiveProcessInfo({
    required this.pid,
    required this.name,
    required this.user,
    required this.cpu,
    required this.mem,
    required this.state,
  });

  factory LiveProcessInfo.fromJson(Map<String, dynamic> json) {
    return LiveProcessInfo(
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      user: json['user'] as String? ?? '',
      cpu: (json['cpu'] as num?)?.toDouble() ?? 0.0,
      mem: (json['mem'] as num?)?.toDouble() ?? 0.0,
      state: json['state'] as String? ?? 'S',
    );
  }
}
