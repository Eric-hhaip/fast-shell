// 纯 Dart 逻辑自检（不依赖 flutter_test，可在无 GUI 环境运行）
// 运行：dart run tool/verify.dart
// ignore_for_file: avoid_print

import 'package:hhaip_shell/models/app_settings.dart';
import 'package:hhaip_shell/models/connection.dart';
import 'package:hhaip_shell/models/transfer_task.dart';
import 'package:hhaip_shell/services/log_text.dart';
import 'package:hhaip_shell/services/monitor_service.dart';
import 'package:hhaip_shell/services/remote_path.dart';
import 'package:hhaip_shell/ui/quick_connect.dart';

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

void main() {
  print('RemotePath');
  check('normalize 折叠 . 与 ..', RemotePath.normalize('/var/./log/../tmp'), '/var/tmp');
  check('normalize 合并斜杠', RemotePath.normalize('a//b///c'), 'a/b/c');
  check('normalize 根目录', RemotePath.normalize('/'), '/');
  check('normalize 越界不回溯', RemotePath.normalize('/../etc'), '/etc');
  check('join', RemotePath.join('/home/deploy', 'app'), '/home/deploy/app');
  check('join 到根', RemotePath.join('/', 'etc'), '/etc');
  check('parent', RemotePath.parent('/home/deploy/app'), '/home/deploy');
  check('parent 根', RemotePath.parent('/'), '/');
  check(
    'breadcrumbs',
    RemotePath.breadcrumbs('/home/deploy').map((c) => c.label).join('|'),
    '/|home|deploy',
  );

  print('快速连接解析');
  check('user@host', parseQuickTarget('root@10.0.0.2')?.username, 'root');
  check('默认端口', parseQuickTarget('root@10.0.0.2')?.port, 22);
  check('自定义端口', parseQuickTarget('deploy@example.com:2222')?.port, 2222);
  check('缺少 @ 返回 null', parseQuickTarget('example.com'), null);
  check('空串返回 null', parseQuickTarget(''), null);
  check('空用户名返回 null', parseQuickTarget('@host'), null);

  print('连接模型');
  final connection = SshConnection(
    name: '生产',
    host: '10.0.0.2',
    port: 2222,
    username: 'deploy',
    authType: SshAuthType.privateKey,
    privateKeyPath: '/Users/me/.ssh/id_ed25519',
    group: '线上',
  );
  final restored = SshConnection.fromJson(connection.toJson());
  check('序列化往返 id', restored.id, connection.id);
  check('序列化往返端口', restored.port, 2222);
  check('序列化往返认证方式', restored.authType, SshAuthType.privateKey);
  check('address', restored.address, 'deploy@10.0.0.2:2222');
  check('displayName 回退', SshConnection(host: 'a.com', username: 'ops').displayName, 'ops@a.com');

  print('传输任务进度');
  final task = TransferTask(
    id: 't1',
    name: 'a.bin',
    direction: TransferDirection.upload,
    localPath: '/tmp/a.bin',
    remotePath: '/root/a.bin',
    totalBytes: 1000,
  );
  task.updateProgress(250);
  check('进度百分比', (task.progress * 100).round(), 25);
  check('进度文案', task.progressText, '250 B / 1000 B');
  task.transferredBytes = 1000;
  check('完成进度', task.progress, 1.0);

  print('监控采集解析');
  const sampleOutput = '''
==FINFO==
my-server
5.10.0
"Tencent OS Server 3.1"
4
86400
==STAT==
cpu  100 0 100 700 100 0 0 0 0 0
==LOAD==
0.10 0.20 0.30 1/100 1234
==MEM==
MemTotal:        4000000 kB
MemAvailable:    2000000 kB
SwapTotal:             0 kB
SwapFree:              0 kB
==DISK==
Filesystem     1024-blocks     Used Available Capacity Mounted on
/dev/vda1        41152812 12345678  26652126  32%      /
tmpfs              996000        0    996000   0%      /dev/shm
/dev/vdb1       103080888 51540444  46316032  53%      /data
==NET==
  lo: 12345 100 0 0 0 0 0 0 678 6 0 0 0 0 0 0
  eth0: 1000000 800 0 0 0 0 0 0 500000 600 0 0 0 0 0 0
==TOP==
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  2.5  1.0  10000 20000 ?       Ss   10:00  1:00 /sbin/init
==DOCKER==
abc123|web|nginx:1.25|running|Up 2 days
def456|cache|redis:7|exited|Exited (0) 3 days ago
==END==
''';
  final snapshot = MonitorService.parseSnapshot(sampleOutput);
  check('主机名', snapshot.hostname, 'my-server');
  check('内核', snapshot.kernel, '5.10.0');
  check('系统', snapshot.os, 'Tencent OS Server 3.1');
  check('核数', snapshot.cores, 4);
  check('负载', snapshot.load1, 0.10);
  check('内存已用', snapshot.memUsedBytes, 2000000 * 1024);
  check('内存百分比', snapshot.memPercent.toStringAsFixed(1), '50.0');
  check('磁盘过滤 tmpfs', snapshot.disks.length, 2);
  check('磁盘挂载', snapshot.disks.first.mount, '/');
  check('网络接口取 eth0', snapshot.net?.interface, 'eth0');
  check('网络收字节', snapshot.net?.rxBytes, 1000000);
  check('进程解析', snapshot.processes.first.command, '/sbin/init');
  check('容器数量', snapshot.containers.length, 2);
  check('容器运行态', snapshot.containers.first.isRunning, true);
  check('容器停止态', snapshot.containers.last.isRunning, false);

  // CPU 使用率：两次采样对比
  final first = MonitorService.parseSnapshot(sampleOutput);
  const busierOutput = '''
==FINFO==
my-server
5.10.0
"Tencent OS Server 3.1"
4
86400
==STAT==
cpu  200 0 200 800 100 0 0 0 0 0
==END==
''';
  final second = MonitorService.parseSnapshot(
    busierOutput,
    prevCpu: first.cpuRaw,
  );
  // total 1000→1300（+300），idle 800→900（+100）→ busy (300-100)/300
  check('CPU 使用率', second.cpuPercent?.toStringAsFixed(1), '66.7');

  final stats = MonitorService.parseDockerStats(
      'web|12.34%|100 MiB / 2 GiB|4.88%|1.2 MB / 3.4 MB');
  check('容器统计名称', stats.keys.first, 'web');
  check('容器统计 CPU', stats['web']?.cpuPercent?.toStringAsFixed(2), '12.34');
  check('容器统计内存', stats['web']?.memUsage, '100 MiB / 2 GiB');

  check(
    '日志脚本',
    MonitorService.containerLogsScript('my web', follow: true),
    "docker logs -f --tail 300 'my web' 2>&1",
  );

  print('设置与分类');
  final defaults = AppSettings();
  check('内置分类只有默认', defaults.categories.join(','), '默认');
  final withCustom = AppSettings(categories: ['默认', '灰度环境']);
  check('自定义分类保留', withCustom.categories.join(','), '默认,灰度环境');
  final restoredSettings = AppSettings.fromJson(withCustom.toJson());
  check('分类序列化往返', restoredSettings.categories.join(','), '默认,灰度环境');
  check(
    '旧数据缺 categories 字段回退',
    AppSettings.fromJson({'fontSize': 15}).categories.join(','),
    '默认',
  );
  check(
    '去重与空值过滤',
    AppSettings.fromJson({
      'categories': ['默认', '  ', '生产', '生产', '', '生产'],
    }).categories.join(','),
    '默认,生产',
  );
  check('默认是内置不可删', defaults.isBuiltinCategory('默认'), true);
  check('自定义可删', withCustom.isBuiltinCategory('灰度环境'), false);

  print('日志行处理（不截断、不改写内容）');  check('保留 ANSI 颜色码', sanitizeLogChunk('\x1B[31mError\x1B[0m'), '\x1B[31mError\x1B[0m');
  check('保留制表符', sanitizeLogChunk('a\tb'), 'a\tb');
  check('保留换行', sanitizeLogChunk('a\nb'), 'a\nb');
  check('保留回车', sanitizeLogChunk('a\rb'), 'a\rb');
  check('保留退格', sanitizeLogChunk('a\bb'), 'a\bb');
  check('剔除 NUL', sanitizeLogChunk('a\x00b'), 'ab');
  final huge = 'x' * 300000;
  check('超长行完整保留', sanitizeLogChunk(huge).length, huge.length);
  check('普通行原样', sanitizeLogChunk('hello 世界'), 'hello 世界');
  check('行数统计', countLogLines('a\nb\nc'), 2);

  print('\n通过 $_passed 项，失败 $_failed 项');
  if (_failed > 0) {
    throw StateError('自检未通过');
  }
}
