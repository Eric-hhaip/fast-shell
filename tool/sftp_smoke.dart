// 端到端冒烟测试：用真实 SSH 服务（本地临时 sshd）验证 SshSession 的全部能力
// 运行：dart run tool/sftp_smoke.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:hhaip_shell/models/connection.dart';
import 'package:hhaip_shell/models/transfer_task.dart';
import 'package:hhaip_shell/services/ssh_session.dart';

int _passed = 0;
int _failed = 0;

void check(String label, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (ok) {
    _passed++;
    print('  ✓ $label');
  } else {
    _failed++;
    print('  ✗ $label → 期望 $expected，实际 $actual');
  }
}

Future<void> main() async {
  final root = '/tmp/hhaip-sshd';
  final base = '$root/data';
  final user = Platform.environment['USER'] ?? 'root';

  // 准备本地测试素材
  Directory('$base/proj/src').createSync(recursive: true);
  Directory('$base/proj/.hidden').createSync(recursive: true);
  File('$base/proj/README.md').writeAsStringSync('# hello\n第二行中文\n');
  File('$base/proj/src/main.sh').writeAsStringSync('echo hi\n');
  File('$base/proj/blob.bin').writeAsBytesSync([0, 1, 2, 255, 0, 7]);
  final upload = File('$root/upload.bin')
    ..writeAsBytesSync(List<int>.generate(300 * 1024, (i) => i % 251));

  final session = SshSession(
    SshConnection(
      host: '127.0.0.1',
      port: 2222,
      username: user,
      authType: SshAuthType.privateKey,
      privateKeyPath: '$root/client_key',
    ),
  );

  final terminalOutput = StringBuffer();
  var hostKeySeen = false;

  print('建立连接');
  await session.connect(
    onOutput: terminalOutput.write,
    onStatus: (status, error) {
      if (error != null) print('  · 状态 $status：$error');
    },
    onHostKey: (type, fingerprint) async {
      hostKeySeen = true;
      print('  · 主机密钥 $type $fingerprint');
      return true;
    },
  );
  check('连接已建立', session.isConnected, true);
  check('主机指纹回调已触发', hostKeySeen, true);

  print('目录浏览');
  final home = await session.resolveInitialDirectory();
  check('主目录解析', home.isNotEmpty, true);
  final rootDirs = await session.listDirectories('/');
  check('根目录含 usr', rootDirs.contains('usr'), true);
  check('根目录含 tmp', rootDirs.contains('tmp'), true);
  final sortedDirs = [...rootDirs]
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  check('目录已排序', rootDirs.first, sortedDirs.first);

  final entries = await session.listDir('$base/proj');
  check('列目录条目数', entries.length, 4);
  check('目录排在文件前', entries.first.isDir, true);
  check('权限位长度', entries.last.mode.length, 10);

  print('文件内容读取');
  final readme = await session.readTextFile('$base/proj/README.md');
  check('文本内容一致', readme.text, '# hello\n第二行中文\n');
  check('未截断', readme.truncated, false);
  check('非二进制', readme.binary, false);
  check('文件大小', readme.size, 24);

  final blob = await session.readTextFile('$base/proj/blob.bin');
  check('二进制识别', blob.binary, true);

  final big = File('$root/big.txt')
    ..writeAsStringSync('A' * (1024 * 1024 + 500));
  final bigRead = await session.readTextFile('$root/big.txt');
  check('大文件截断标记', bigRead.truncated, true);
  check('截断到 1MB', bigRead.text.length, 1024 * 1024);
  check('大文件真实大小', bigRead.size, big.lengthSync());

  print('文件写回');
  await session.writeTextFile('$base/proj/README.md', '# 改过了\n新增一行\n');
  check(
    '远端内容已更新',
    File('$base/proj/README.md').readAsStringSync(),
    '# 改过了\n新增一行\n',
  );

  print('上传 / 下载');
  final uploadTask = TransferTask(
    id: 'u1',
    name: 'upload.bin',
    direction: TransferDirection.upload,
    localPath: upload.path,
    remotePath: '$base/proj/upload.bin',
    totalBytes: upload.lengthSync(),
  );
  await session.uploadFile(uploadTask);
  check('上传字节数', uploadTask.transferredBytes, upload.lengthSync());
  check(
    '远端文件大小一致',
    File('$base/proj/upload.bin').lengthSync(),
    upload.lengthSync(),
  );

  final downloadDir = Directory('$root/download')..createSync(recursive: true);
  final downloadTask = TransferTask(
    id: 'd1',
    name: 'upload.bin',
    direction: TransferDirection.download,
    localPath: '${downloadDir.path}/upload.bin',
    remotePath: '$base/proj/upload.bin',
    totalBytes: upload.lengthSync(),
  );
  await session.downloadFile(downloadTask);
  check(
    '下载内容一致',
    File('${downloadDir.path}/upload.bin').readAsBytesSync().length,
    upload.lengthSync(),
  );

  print('目录操作');
  await session.mkdir('$base/proj/newdir');
  check('mkdir', Directory('$base/proj/newdir').existsSync(), true);
  await session.rename('$base/proj/newdir', '$base/proj/renamed');
  check('rename', Directory('$base/proj/renamed').existsSync(), true);
  await session.mkdirRecursive('$base/proj/a/b/c');
  check('mkdirRecursive', Directory('$base/proj/a/b/c').existsSync(), true);
  await session.deleteRecursive('$base/proj/a');
  check('deleteRecursive 目录', Directory('$base/proj/a').existsSync(), false);
  await session.deleteFile('$base/proj/renamed');
  check('目录已被清空', Directory('$base/proj/renamed').existsSync(), false);

  print('交互式 Shell（Linux 命令）');
  terminalOutput.clear();
  session.writeString('echo HHAIP_OK\n');
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  check('命令输出回显', terminalOutput.toString().contains('HHAIP_OK'), true);

  session.writeString('uname -s\n');
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  check('uname 输出', terminalOutput.toString().contains('Darwin'), true);

  await session.dispose();
  check('会话已关闭', session.isConnected, false);

  print('\n通过 $_passed 项，失败 $_failed 项');
  if (_failed > 0) exit(1);
}
