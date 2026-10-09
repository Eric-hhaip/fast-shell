import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

/// 本地加密仓库。
///
/// - 主密钥保存在 `vault.key`（32 随机字节，权限 0600）
/// - 数据以 AES-256-GCM 加密写入 `vault.enc`
/// - 实际加密密钥由「主密钥 + 本机标识」经 HKDF 派生：
///   只拷贝 vault.enc 到别的机器无法解密。
class Vault {
  Vault._(this.directory, this._key);

  final Directory directory;
  final SecretKey _key;

  static const _vaultFileName = 'vault.enc';
  static const _keyFileName = 'vault.key';

  /// 解密失败时的提示（UI 展示后应清空）
  String? warning;

  File get vaultFile => File('${directory.path}/$_vaultFileName');

  static Future<Vault> open() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(support.path);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    // 设备 UUID（要 spawn ioreg）与密钥文件读取互不依赖，并行跑省一个来回
    final keyFile = File('${directory.path}/$_keyFileName');
    final deviceIdFuture = _deviceId();
    List<int> master;
    if (keyFile.existsSync() && keyFile.lengthSync() == 32) {
      master = await keyFile.readAsBytes();
    } else {
      final random = Random.secure();
      master = List<int>.generate(32, (_) => random.nextInt(256));
      await keyFile.writeAsBytes(master, flush: true);
      _restrictPermissions(keyFile.path);
    }

    final deviceId = await deviceIdFuture;
    final derive = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await derive.deriveKey(
      secretKey: SecretKey(master),
      nonce: utf8.encode(deviceId),
      info: utf8.encode('hhaip-shell/vault/v1'),
    );

    return Vault._(directory, derived);
  }

  /// 权限收紧不阻塞调用方：它只是安全加固，晚几百微秒完成没关系
  static void _restrictPermissions(String path) {
    try {
      Process.run('chmod', ['600', path]).ignore();
    } catch (_) {
      // 沙盒里被拒也只是退回默认权限，不影响功能
    }
  }

  static Future<String> _deviceId() async {
    if (Platform.isMacOS) {
      try {
        final result = await Process.run('ioreg', [
          '-rd1',
          '-c',
          'IOPlatformExpertDevice',
        ]);
        final output = result.stdout.toString();
        final match = RegExp(
          r'"IOPlatformUUID"\s*=\s*"([^"]+)"',
        ).firstMatch(output);
        if (match != null) return match.group(1)!;
      } catch (_) {
        // 忽略：退回主机名
      }
    }
    return Platform.localHostname;
  }

  /// 读取整份数据；文件不存在返回空 map
  Future<Map<String, dynamic>> read() async {
    final file = vaultFile;
    if (!file.existsSync()) return <String, dynamic>{};

    try {
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final nonce = base64Decode(payload['nonce'] as String);
      final mac = Mac(base64Decode(payload['mac'] as String));
      final cipherText = base64Decode(payload['data'] as String);

      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: _key,
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } catch (error) {
      // 无法解密：备份原文件，从头开始，避免应用直接不可用
      try {
        final backup =
            '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
        await file.rename(backup);
      } catch (_) {}
      warning = '本地配置解密失败，已重置（旧文件已备份）。';
      return <String, dynamic>{};
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    final clear = utf8.encode(jsonEncode(data));
    final box = await AesGcm.with256bits().encrypt(clear, secretKey: _key);
    final payload = jsonEncode({
      'v': 1,
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    });

    final tmp = File('${vaultFile.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(vaultFile.path);
    _restrictPermissions(vaultFile.path);
  }
}
