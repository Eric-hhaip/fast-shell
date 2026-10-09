import 'dart:convert';

/// 服务器监控：采集脚本 + 纯函数解析（可脱离 GUI 测试）
class MonitorService {
  MonitorService._();

  /// 主机指标采集（每 3 秒）：全部读 /proc / df / ps，最快几百毫秒返回。
  /// 刻意不含 docker —— docker CLI 启动慢（1-2 秒+），会拖垮整个轮询，
  /// 单独走 [dockerScript] 低频并行采集。
  static const hostScript = '''
echo ==FINFO==
hostname
uname -r
sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null
grep -c '^processor' /proc/cpuinfo
cut -d ' ' -f1 /proc/uptime
echo ==STAT==
head -1 /proc/stat
echo ==LOAD==
cat /proc/loadavg
echo ==MEM==
cat /proc/meminfo
echo ==DISK==
df -P -k
echo ==NET==
cat /proc/net/dev
echo ==TOP==
ps aux --sort=-%cpu 2>/dev/null | head -7
echo ==END==
''';

  /// docker 容器列表（单独低频采集，默认 12 秒一次）
  static const dockerScript =
      "docker ps -a --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}' 2>/dev/null";

  /// docker stats（按需，慢约 1-2 秒）
  static const dockerStatsScript =
      "docker stats --no-stream --format "
      "'{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}' 2>/dev/null";

  static String containerLogsScript(String name, {bool follow = false}) {
    final safe = name.replaceAll("'", '');
    return "docker logs ${follow ? '-f' : ''} --tail 300 '$safe' 2>&1";
  }

  static String containerActionScript(String name, String action) {
    final safe = name.replaceAll("'", '');
    return "docker $action '$safe' 2>&1";
  }

  // ------------------------------------------------------------- 解析

  /// 解析 [pollScript] 的输出。[prevCpu] / [prevNet] 用于计算两次采集间的
  /// CPU 使用率与网络速率（第一次采集没有参照，这两项为 null）。
  static HostSnapshot parseSnapshot(
    String output, {
    CpuSample? prevCpu,
    NetSample? prevNet,
  }) {
    String section = '';
    String hostname = '', kernel = '', os = '';
    int cores = 0, uptimeSeconds = 0;
    CpuSample? cpu;
    final loads = <double>[];
    final meminfo = <String, int>{};
    final disks = <DiskUsage>[];
    NetSample? net;
    final processes = <ProcInfo>[];
    final containers = <ContainerInfo>[];

    final lines = const LineSplitter().convert(output);
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('==') && line.endsWith('==')) {
        section = line.substring(2, line.length - 2);
        continue;
      }
      if (line.isEmpty) continue;
      switch (section) {
        case 'FINFO':
          if (hostname.isEmpty) {
            hostname = line;
          } else if (kernel.isEmpty) {
            kernel = line;
          } else if (os.isEmpty) {
            os = line.replaceAll('"', '');
          } else if (cores == 0) {
            cores = int.tryParse(line) ?? 0;
          } else {
            uptimeSeconds = int.tryParse(line) ?? 0;
          }
        case 'STAT':
          if (line.startsWith('cpu ') && cpu == null) {
            cpu = _parseCpuLine(line);
          }
        case 'LOAD':
          if (loads.isEmpty) {
            final parts = line.split(RegExp(r'\s+'));
            for (var i = 0; i < 3 && i < parts.length; i++) {
              loads.add(double.tryParse(parts[i]) ?? 0);
            }
          }
        case 'MEM':
          final match = RegExp(r'^(\w+):\s+(\d+)').firstMatch(line);
          if (match != null) {
            meminfo[match.group(1)!] = int.parse(match.group(2)!); // kB
          }
        case 'DISK':
          final disk = _parseDfLine(line);
          if (disk != null) disks.add(disk);
        case 'NET':
          net ??= _parseNetLine(line);
        case 'TOP':
          final proc = _parsePsLine(line);
          if (proc != null) processes.add(proc);
        case 'DOCKER':
          final container = _parseDockerLine(line);
          if (container != null) containers.add(container);
      }
    }

    // CPU 使用率：与上次采样对比
    double? cpuPercent;
    if (cpu != null && prevCpu != null) {
      final totalDelta = cpu.total - prevCpu.total;
      final idleDelta = cpu.idle - prevCpu.idle;
      if (totalDelta > 0) {
        cpuPercent = ((totalDelta - idleDelta) / totalDelta * 100)
            .clamp(0, 100)
            .toDouble();
      }
    }

    // 内存：优先 MemAvailable
    final memTotalKb = meminfo['MemTotal'] ?? 0;
    final memAvailKb =
        meminfo['MemAvailable'] ?? meminfo['MemFree'] ?? memTotalKb;
    final memUsedKb = (memTotalKb - memAvailKb).clamp(0, memTotalKb);
    final swapTotalKb = meminfo['SwapTotal'] ?? 0;
    final swapFreeKb = meminfo['SwapFree'] ?? 0;

    return HostSnapshot(
      hostname: hostname,
      kernel: kernel,
      os: os,
      cores: cores,
      uptimeSeconds: uptimeSeconds,
      load1: loads.isNotEmpty ? loads[0] : 0,
      load5: loads.length > 1 ? loads[1] : 0,
      load15: loads.length > 2 ? loads[2] : 0,
      cpuPercent: cpuPercent,
      cpuRaw: cpu,
      memTotalBytes: memTotalKb * 1024,
      memUsedBytes: memUsedKb * 1024,
      swapTotalBytes: swapTotalKb * 1024,
      swapUsedBytes: (swapTotalKb - swapFreeKb).clamp(0, swapTotalKb) * 1024,
      disks: disks,
      net: net,
      processes: processes,
      containers: containers,
    );
  }

  static CpuSample? _parseCpuLine(String line) {
    final parts = line.split(RegExp(r'\s+')).skip(1);
    var total = 0;
    var idle = 0;
    for (final (index, part) in parts.indexed) {
      final value = int.tryParse(part) ?? 0;
      total += value;
      if (index == 3) idle += value; // idle
      if (index == 4) idle += value; // iowait 不算忙碌
    }
    if (total == 0) return null;
    return CpuSample(idle: idle, total: total);
  }

  /// df -P -k：Filesystem 1024-blocks Used Available Capacity Mounted-on
  static DiskUsage? _parseDfLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 6) return null;
    final fs = parts[0];
    if (!parts[5].startsWith('/')) return null;
    const virtual = {'tmpfs', 'devtmpfs', 'udev', 'none', 'squashfs', 'shm'};
    if (virtual.contains(fs)) return null;
    final totalKb = int.tryParse(parts[1]);
    final usedKb = int.tryParse(parts[2]);
    if (totalKb == null || usedKb == null || totalKb <= 0) return null;
    return DiskUsage(
      filesystem: fs,
      mount: parts.sublist(5).join(' '),
      totalBytes: totalKb * 1024,
      usedBytes: usedKb * 1024,
    );
  }

  /// /proc/net/dev：iface: rx_bytes ... tx_bytes
  static NetSample? _parseNetLine(String line) {
    final index = line.indexOf(':');
    if (index < 0) return null;
    final name = line.substring(0, index).trim();
    if (name == 'lo' || name.isEmpty) return null;
    final parts = line.substring(index + 1).trim().split(RegExp(r'\s+'));
    if (parts.length < 9) return null;
    final rx = int.tryParse(parts[0]);
    final tx = int.tryParse(parts[8]);
    if (rx == null || tx == null) return null;
    return NetSample(interface: name, rxBytes: rx, txBytes: tx);
  }

  /// ps aux：USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
  static ProcInfo? _parsePsLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 11) return null;
    if (parts[0] == 'USER') return null;
    final pid = int.tryParse(parts[1]);
    final cpu = double.tryParse(parts[2]);
    final mem = double.tryParse(parts[3]);
    if (pid == null || cpu == null || mem == null) return null;
    return ProcInfo(
      pid: pid,
      user: parts[0],
      cpuPercent: cpu,
      memPercent: mem,
      command: parts.sublist(10).join(' '),
    );
  }

  /// 解析 docker ps 输出（docker 轮询通道单独使用）
  static List<ContainerInfo> parseContainers(String output) {
    final containers = <ContainerInfo>[];
    for (final line in const LineSplitter().convert(output)) {
      final container = _parseDockerLine(line.trim());
      if (container != null) containers.add(container);
    }
    return containers;
  }

  /// docker ps --format：ID|Names|Image|State|Status
  static ContainerInfo? _parseDockerLine(String line) {
    final parts = line.split('|');
    if (parts.length < 5) return null;
    return ContainerInfo(
      id: parts[0],
      name: parts[1],
      image: parts[2],
      state: parts[3],
      status: parts.sublist(4).join('|'),
    );
  }

  /// docker stats --format：Name|CPUPerc|MemUsage|MemPerc|NetIO
  static Map<String, ContainerStat> parseDockerStats(String output) {
    final result = <String, ContainerStat>{};
    for (final line in const LineSplitter().convert(output)) {
      final parts = line.trim().split('|');
      if (parts.length < 5) continue;
      result[parts[0]] = ContainerStat(
        cpuPercent: _stripPercent(parts[1]),
        memUsage: parts[2],
        memPercent: _stripPercent(parts[3]),
        netIo: parts[4],
      );
    }
    return result;
  }

  static double? _stripPercent(String value) {
    final number = double.tryParse(value.trim().replaceAll(RegExp(r'[%a-zA-Z]'), ''));
    return number;
  }
}

/// 一次 CPU 采样（/proc/stat 首行累计值）
class CpuSample {
  const CpuSample({required this.idle, required this.total});
  final int idle;
  final int total;
}

/// 一次网络采样（累计字节数）
class NetSample {
  const NetSample({
    required this.interface,
    required this.rxBytes,
    required this.txBytes,
  });
  final String interface;
  final int rxBytes;
  final int txBytes;
}

class HostSnapshot {
  const HostSnapshot({
    required this.hostname,
    required this.kernel,
    required this.os,
    required this.cores,
    required this.uptimeSeconds,
    required this.load1,
    required this.load5,
    required this.load15,
    required this.cpuPercent,
    required this.cpuRaw,
    required this.memTotalBytes,
    required this.memUsedBytes,
    required this.swapTotalBytes,
    required this.swapUsedBytes,
    required this.disks,
    required this.net,
    required this.processes,
    required this.containers,
  });

  final String hostname;
  final String kernel;
  final String os;
  final int cores;
  final int uptimeSeconds;
  final double load1;
  final double load5;
  final double load15;
  final double? cpuPercent;

  /// 本次的原始 CPU 累计采样，供下次计算使用率差值
  final CpuSample? cpuRaw;
  final int memTotalBytes;
  final int memUsedBytes;
  final int swapTotalBytes;
  final int swapUsedBytes;
  final List<DiskUsage> disks;
  final NetSample? net;
  final List<ProcInfo> processes;
  final List<ContainerInfo> containers;

  double get memPercent =>
      memTotalBytes <= 0 ? 0 : memUsedBytes / memTotalBytes * 100;
}

class DiskUsage {
  const DiskUsage({
    required this.filesystem,
    required this.mount,
    required this.totalBytes,
    required this.usedBytes,
  });

  final String filesystem;
  final String mount;
  final int totalBytes;
  final int usedBytes;

  double get percent =>
      totalBytes <= 0 ? 0 : usedBytes / totalBytes * 100;
}

class ProcInfo {
  const ProcInfo({
    required this.pid,
    required this.user,
    required this.cpuPercent,
    required this.memPercent,
    required this.command,
  });

  final int pid;
  final String user;
  final double cpuPercent;
  final double memPercent;
  final String command;
}

class ContainerInfo {
  const ContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
  });

  final String id;
  final String name;
  final String image;
  final String state;
  final String status;

  bool get isRunning => state == 'running';
}

class ContainerStat {
  const ContainerStat({
    required this.cpuPercent,
    required this.memUsage,
    required this.memPercent,
    required this.netIo,
  });

  final double? cpuPercent;
  final String memUsage;
  final double? memPercent;
  final String netIo;
}
