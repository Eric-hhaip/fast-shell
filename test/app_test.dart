import 'package:flutter_test/flutter_test.dart';
import 'package:hhaip_shell/models/connection.dart';
import 'package:hhaip_shell/services/remote_path.dart';
import 'package:hhaip_shell/ui/quick_connect.dart';

void main() {
  group('RemotePath', () {
    test('normalize collapses dot segments', () {
      expect(RemotePath.normalize('/var/./log/../tmp'), '/var/tmp');
      expect(RemotePath.normalize('a//b///c'), 'a/b/c');
      expect(RemotePath.normalize('/'), '/');
      expect(RemotePath.normalize('/../etc'), '/etc');
    });

    test('join and parent', () {
      expect(RemotePath.join('/home/deploy', 'app'), '/home/deploy/app');
      expect(RemotePath.join('/', 'etc'), '/etc');
      expect(RemotePath.parent('/home/deploy/app'), '/home/deploy');
      expect(RemotePath.parent('/'), '/');
      expect(RemotePath.parent('/home'), '/');
    });

    test('breadcrumbs', () {
      final crumbs = RemotePath.breadcrumbs('/home/deploy');
      expect(crumbs.map((item) => item.label).toList(), [
        '/',
        'home',
        'deploy',
      ]);
      expect(crumbs.last.path, '/home/deploy');
    });
  });

  group('quick connect 解析', () {
    test('user@host', () {
      final target = parseQuickTarget('root@10.0.0.2');
      expect(target?.host, '10.0.0.2');
      expect(target?.username, 'root');
      expect(target?.port, 22);
    });

    test('user@host:port', () {
      final target = parseQuickTarget('deploy@example.com:2222');
      expect(target?.host, 'example.com');
      expect(target?.port, 2222);
    });

    test('非法输入返回 null', () {
      expect(parseQuickTarget('example.com'), isNull);
      expect(parseQuickTarget(''), isNull);
      expect(parseQuickTarget('@host'), isNull);
    });
  });

  group('连接序列化', () {
    test('往返后字段保持一致', () {
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
      expect(restored.id, connection.id);
      expect(restored.displayName, '生产');
      expect(restored.port, 2222);
      expect(restored.authType, SshAuthType.privateKey);
      expect(restored.address, 'deploy@10.0.0.2:2222');
    });

    test('无名称时回退为 user@host', () {
      final connection = SshConnection(host: 'a.com', username: 'ops');
      expect(connection.displayName, 'ops@a.com');
    });
  });
}
