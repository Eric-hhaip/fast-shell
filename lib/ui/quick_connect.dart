/// 解析快速连接输入：`user@host` 或 `user@host:port`
///
/// 返回 null 表示格式不合法。
({String host, int port, String username})? parseQuickTarget(String input) {
  final text = input.trim();
  if (text.isEmpty || !text.contains('@')) return null;

  final at = text.lastIndexOf('@');
  final username = text.substring(0, at);
  var hostPart = text.substring(at + 1);
  var port = 22;

  final colon = hostPart.lastIndexOf(':');
  if (colon > 0) {
    final parsed = int.tryParse(hostPart.substring(colon + 1));
    if (parsed != null && parsed > 0 && parsed <= 65535) {
      port = parsed;
      hostPart = hostPart.substring(0, colon);
    }
  }

  if (username.isEmpty || hostPart.isEmpty) return null;
  return (host: hostPart, port: port, username: username);
}
