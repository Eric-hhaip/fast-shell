import 'dart:math';

/// 认证方式
enum SshAuthType {
  password('密码'),
  privateKey('私钥');

  const SshAuthType(this.label);

  final String label;

  static SshAuthType fromName(String? name) => SshAuthType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => SshAuthType.password,
  );
}

/// 一条远程连接配置（含敏感字段，整体加密落盘）
class SshConnection {
  SshConnection({
    String? id,
    this.name = '',
    this.host = '',
    this.port = 22,
    this.username = 'root',
    this.authType = SshAuthType.password,
    this.password = '',
    this.privateKeyPath = '',
    this.privateKeyPem = '',
    this.passphrase = '',
    this.group = '默认',
    this.note = '',
    this.hostKeyFingerprint,
    this.lastConnectedAt,
  }) : id = id ?? newId();

  String id;
  String name;
  String host;
  int port;
  String username;
  SshAuthType authType;
  String password;

  /// 私钥文件路径（与 [privateKeyPem] 二选一）
  String privateKeyPath;

  /// 直接粘贴的私钥内容
  String privateKeyPem;

  String passphrase;
  String group;
  String note;

  /// 上次握手时记录的服务器公钥指纹（OpenSSH 风格 SHA256:xxx）
  String? hostKeyFingerprint;

  DateTime? lastConnectedAt;

  static String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (host.trim().isNotEmpty) return '$username@$host';
    return '未命名连接';
  }

  String get address => '$username@$host:$port';

  SshConnection copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    SshAuthType? authType,
    String? password,
    String? privateKeyPath,
    String? privateKeyPem,
    String? passphrase,
    String? group,
    String? note,
    String? hostKeyFingerprint,
    bool clearHostKey = false,
    DateTime? lastConnectedAt,
  }) {
    return SshConnection(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      password: password ?? this.password,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      privateKeyPem: privateKeyPem ?? this.privateKeyPem,
      passphrase: passphrase ?? this.passphrase,
      group: group ?? this.group,
      note: note ?? this.note,
      hostKeyFingerprint: clearHostKey
          ? null
          : (hostKeyFingerprint ?? this.hostKeyFingerprint),
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'authType': authType.name,
    'password': password,
    'privateKeyPath': privateKeyPath,
    'privateKeyPem': privateKeyPem,
    'passphrase': passphrase,
    'group': group,
    'note': note,
    'hostKeyFingerprint': hostKeyFingerprint,
    'lastConnectedAt': lastConnectedAt?.toIso8601String(),
  };

  factory SshConnection.fromJson(Map<String, dynamic> json) {
    return SshConnection(
      id: json['id'] as String?,
      name: (json['name'] as String?) ?? '',
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: (json['username'] as String?) ?? 'root',
      authType: SshAuthType.fromName(json['authType'] as String?),
      password: (json['password'] as String?) ?? '',
      privateKeyPath: (json['privateKeyPath'] as String?) ?? '',
      privateKeyPem: (json['privateKeyPem'] as String?) ?? '',
      passphrase: (json['passphrase'] as String?) ?? '',
      group: (json['group'] as String?) ?? '默认',
      note: (json['note'] as String?) ?? '',
      hostKeyFingerprint: json['hostKeyFingerprint'] as String?,
      lastConnectedAt: DateTime.tryParse(
        (json['lastConnectedAt'] as String?) ?? '',
      ),
    );
  }
}
