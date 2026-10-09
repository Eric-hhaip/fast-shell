import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:path_provider/path_provider.dart';

/// 本地文件系统辅助：下载目录解析、写入权限探测、在访达中定位。
///
/// macOS 沙盒下，应用只能写入被授权的目录（~/Downloads、用户通过文件面板
/// 显式选择的文件/目录）。这里集中处理，避免各处重复踩坑。
class LocalIo {
  LocalIo._();

  static Directory? _cachedDownloads;

  /// 默认下载目录。macOS 上为 ~/Downloads，
  /// 对应 entitlements 里的 `com.apple.security.files.downloads.read-write`。
  static Future<Directory> downloadsDirectory() async {
    final cached = _cachedDownloads;
    if (cached != null) return cached;

    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    dir ??= _fallbackDownloads();

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDownloads = dir;
    return dir;
  }

  static Directory _fallbackDownloads() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory('$home/Downloads');
    }
    return Directory.systemTemp;
  }

  /// 拼接本地路径（统一用 `/`，macOS 下与 `\` 等价）
  static String join(String dir, String name) {
    if (dir.isEmpty) return name;
    return dir.endsWith('/') ? '$dir$name' : '$dir/$name';
  }

  /// 探测目录是否真的可写：写一个探针文件再删掉。
  ///
  /// 沙盒下 `Directory.exists()` 即使为 true 也可能不可写，
  /// 所以必须做一次真实写入。返回 null 表示可写，否则返回错误原因。
  static Future<String?> probeWritable(String dir) async {
    if (dir.isEmpty) return '目录为空';
    try {
      final probe = File(join(dir, '.fastshell-write-probe'));
      await probe.writeAsString('fastshell', flush: true);
      await probe.delete();
      return null;
    } on FileSystemException catch (error) {
      return error.osError?.message ?? error.message;
    } catch (error) {
      return describeError(error);
    }
  }

  /// 在访达中显示某个文件或目录
  static Future<void> revealInFinder(String path) async {
    if (path.isEmpty) return;
    final type = FileSystemEntity.typeSync(path);
    try {
      if (type == FileSystemEntityType.notFound) {
        final parent = _parentOf(path);
        await Process.run('open', [parent]);
      } else {
        await Process.run('open', ['-R', path]);
      }
    } catch (_) {
      // 打不开就算了，不影响主流程
    }
  }

  static String _parentOf(String path) {
    final index = path.lastIndexOf('/');
    if (index <= 0) return '/';
    return path.substring(0, index);
  }
}

/// 把任意异常翻译成适合直接展示给用户的一句话
String describeError(Object error) {
  if (error is StateError) return error.message;

  if (error is FileSystemException) {
    final reason = error.osError?.message ?? error.message;
    if (reason.contains('Operation not permitted') ||
        reason.contains('Permission denied')) {
      return '本地写入被系统拒绝（$reason），请换一个位置或检查沙盒权限';
    }
    if (reason.contains('No such file or directory')) {
      return '本地路径不存在（$reason）';
    }
    if (reason.contains('No space left')) {
      return '本地磁盘空间不足';
    }
    return '本地文件操作失败（$reason）';
  }

  if (error is SocketException) {
    return error.osError?.message ?? error.message;
  }

  if (error is SftpStatusError) {
    return 'SFTP 操作被拒绝（code ${error.code}）：多为远端权限不足';
  }

  if (error is SSHAuthFailError || error is SSHAuthAbortError) {
    return '认证失败：请检查用户名、密码或私钥';
  }

  if (error is SSHChannelRequestError) {
    return '远端拒绝了会话请求（${error.message}）';
  }

  if (error is SSHKeyDecryptError) {
    return '私钥解密失败：密码短语不正确';
  }

  if (error is TimeoutException) {
    return '操作超时，请检查网络';
  }

  return error.toString().replaceFirst('Exception: ', '');
}
