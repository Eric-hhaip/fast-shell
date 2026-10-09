enum TransferDirection {
  upload('上传'),
  download('下载');

  const TransferDirection(this.label);

  final String label;
}

enum TransferStatus { queued, running, done, failed, cancelled }

/// 一个上传 / 下载任务
class TransferTask {
  TransferTask({
    required this.id,
    required this.name,
    required this.direction,
    required this.localPath,
    required this.remotePath,
    required this.totalBytes,
  });

  final String id;
  final String name;
  final TransferDirection direction;
  final String localPath;
  final String remotePath;
  final int totalBytes;

  int transferredBytes = 0;
  TransferStatus status = TransferStatus.queued;
  String? error;
  bool cancelRequested = false;

  /// 最近一秒的瞬时速度（字节/秒）
  double speed = 0;

  DateTime? _lastTick;
  int _lastBytes = 0;

  double get progress {
    if (totalBytes <= 0) {
      return status == TransferStatus.done ? 1 : 0;
    }
    return (transferredBytes / totalBytes).clamp(0, 1).toDouble();
  }

  bool get isActive =>
      status == TransferStatus.queued || status == TransferStatus.running;

  String get statusLabel => switch (status) {
    TransferStatus.queued => '等待中',
    TransferStatus.running => '进行中',
    TransferStatus.done => '已完成',
    TransferStatus.failed => '失败',
    TransferStatus.cancelled => '已取消',
  };

  String get progressText {
    final done = _sizeText(transferredBytes);
    if (totalBytes <= 0) return done;
    return '$done / ${_sizeText(totalBytes)}';
  }

  String get speedText {
    if (status != TransferStatus.running || speed <= 0) return '';
    return '${_sizeText(speed.round())}/s';
  }

  void updateProgress(int transferred) {
    transferredBytes = transferred;
    final now = DateTime.now();
    final last = _lastTick;
    if (last == null) {
      _lastTick = now;
      _lastBytes = transferred;
      return;
    }
    final elapsed = now.difference(last).inMilliseconds;
    if (elapsed >= 400) {
      speed = (transferred - _lastBytes) * 1000 / elapsed;
      _lastTick = now;
      _lastBytes = transferred;
    }
  }

  static String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }
}
