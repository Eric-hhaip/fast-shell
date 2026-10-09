/// 远端目录中的一项
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.isDir,
    required this.isLink,
    required this.size,
    required this.modified,
    required this.mode,
  });

  final String name;
  final bool isDir;
  final bool isLink;
  final int size;
  final DateTime? modified;

  /// 权限字符串，如 `-rw-r--r--`
  final String mode;

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }

  String get readableSize => isDir ? '--' : formatSize(size);

  String get readableModified {
    final time = modified;
    if (time == null) return '--';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
