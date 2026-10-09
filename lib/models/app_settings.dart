/// 应用设置（纯数据模型，无 Flutter 依赖，便于自检与序列化测试）
class AppSettings {
  AppSettings({
    this.fontSize = 13,
    this.showHiddenFiles = false,
    this.confirmBeforeClose = true,
    this.openSftpByDefault = false,
    List<String>? categories,
  }) : categories = categories ?? [...defaultCategories];

  /// 内置分类，不可删除（用户明确只保留一个「默认」，其余自己加）
  static const defaultCategories = ['默认'];

  double fontSize;
  bool showHiddenFiles;
  bool confirmBeforeClose;
  bool openSftpByDefault;

  /// 连接分类（用户自定义，可增删；连接上用 group 字段引用）
  final List<String> categories;

  bool isBuiltinCategory(String name) => defaultCategories.contains(name);

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'showHiddenFiles': showHiddenFiles,
    'confirmBeforeClose': confirmBeforeClose,
    'openSftpByDefault': openSftpByDefault,
    'categories': categories,
  };

  factory AppSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return AppSettings();
    // 老版本没有 categories 字段：补上内置分类，并保留数据里出现过的分组，
    // 保证历史连接不会因为设置缺项而丢分类
    final categories = <String>[...defaultCategories];
    final rawCategories = json['categories'];
    if (rawCategories is List) {
      for (final item in rawCategories) {
        if (item is String && item.trim().isNotEmpty) {
          final name = item.trim();
          if (!categories.contains(name)) categories.add(name);
        }
      }
    }
    return AppSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 13,
      showHiddenFiles: (json['showHiddenFiles'] as bool?) ?? false,
      confirmBeforeClose: (json['confirmBeforeClose'] as bool?) ?? true,
      openSftpByDefault: (json['openSftpByDefault'] as bool?) ?? false,
      categories: categories,
    );
  }
}
