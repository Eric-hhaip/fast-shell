// 日志文本处理（纯 Dart，无 Flutter 依赖，便于 tool/verify.dart 直接跑）

/// 日志文本无害化：**只剔除 NUL 字节，不截断、不改写任何内容**。
///
/// 终端能理解所有 C0 控制字符（\t \n \r \b ESC…），其中 ESC 是 ANSI 颜色
/// 序列的引导字节，绝不能删——删掉只会让 `[31m` 这类残留变成可见乱码。
/// 因此这里只清掉唯一无意义、且会让 C 字符串截断的 NUL。
String sanitizeLogChunk(String raw) {
  if (!raw.contains('\u0000')) return raw; // 绝大多数情况零拷贝返回
  return raw.replaceAll('\u0000', '');
}

/// 统计文本行数（按 \n）
int countLogLines(String text) {
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) count++;
  }
  return count;
}
