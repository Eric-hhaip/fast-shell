/// 远端路径的纯字符串工具（统一使用 `/` 分隔）
class RemotePath {
  const RemotePath._();

  static String normalize(String path) {
    final isAbsolute = path.startsWith('/');
    final parts = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty && parts.last != '..') {
          parts.removeLast();
        } else if (!isAbsolute) {
          parts.add('..');
        }
        continue;
      }
      parts.add(segment);
    }
    final joined = parts.join('/');
    if (isAbsolute) return '/$joined';
    return joined.isEmpty ? '.' : joined;
  }

  static String join(String base, String name) {
    if (base.isEmpty) return '/$name';
    if (base.endsWith('/')) return normalize('$base$name');
    return normalize('$base/$name');
  }

  /// 返回父目录；已在根时返回 `/`
  static String parent(String path) {
    final normalized = normalize(path);
    if (normalized == '/' || normalized.isEmpty) return '/';
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return '/';
    return normalized.substring(0, index);
  }

  static String baseName(String path) {
    final normalized = normalize(path);
    if (normalized == '/') return '/';
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  /// 拆成面包屑：[{'/', '/'}, {'home', '/home'}, ...]
  static List<({String label, String path})> breadcrumbs(String path) {
    final normalized = normalize(path);
    final crumbs = <({String label, String path})>[
      (label: '/', path: '/'),
    ];
    var current = '';
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty) continue;
      current = '$current/$segment';
      crumbs.add((label: segment, path: current));
    }
    return crumbs;
  }
}
