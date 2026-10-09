import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_store.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final settings = store.settings;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      title: Row(
        children: [
          const Expanded(child: Text('设置', style: AppText.h1)),
          AppIconButton(
            icon: Icons.close,
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel(text: '终端'),
              _row(
                title: '字号',
                description: '终端等宽字体大小，也可用 ⌘+ / ⌘- 调整',
                trailing: Row(
                  children: [
                    AppIconButton(
                      icon: Icons.remove,
                      tooltip: '减小',
                      onPressed: () => store.changeFontSize(-1),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text(
                        settings.fontSize.toStringAsFixed(0),
                        textAlign: TextAlign.center,
                        style: AppText.bodyStrong,
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.add,
                      tooltip: '增大',
                      onPressed: () => store.changeFontSize(1),
                    ),
                  ],
                ),
              ),
              const SectionLabel(text: '行为'),
              _row(
                title: '显示点文件',
                description: '在文件面板中展示以 . 开头的隐藏文件',
                trailing: Switch(
                  value: settings.showHiddenFiles,
                  onChanged: (value) =>
                      store.updateSettings(showHiddenFiles: value),
                ),
              ),
              _row(
                title: '连接后打开文件面板',
                description: '建立连接时自动加载远端主目录',
                trailing: Switch(
                  value: settings.openSftpByDefault,
                  onChanged: (value) =>
                      store.updateSettings(openSftpByDefault: value),
                ),
              ),
              _row(
                title: '关闭标签前确认',
                description: '避免误关正在运行的会话',
                trailing: Switch(
                  value: settings.confirmBeforeClose,
                  onChanged: (value) =>
                      store.updateSettings(confirmBeforeClose: value),
                ),
              ),
              const SectionLabel(text: '存储与安全'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 7),
                        Text('连接信息加密保存', style: AppText.bodyStrong),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '主机、用户名、密码与私钥均以 AES-256-GCM 加密后写入本机，'
                      '密钥文件权限为 600，且与本机硬件标识绑定：'
                      '把配置复制到其他电脑无法解密。',
                      style: AppText.secondary,
                    ),
                    if (store.storagePath != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        store.storagePath!,
                        style: AppText.mono,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionLabel(text: '关于'),
              const Text(
                'Fast Shell · 面向 macOS 的远程终端与文件工具\n'
                'SSH / SFTP 由 dartssh2 驱动，终端渲染由 xterm.dart 驱动',
                style: AppText.secondary,
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _row({
    required String title,
    required String description,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(description, style: AppText.tertiary),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
