import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection.dart';
import '../state/app_store.dart';
import 'connection_editor.dart';
import 'monitor_panel.dart';
import 'quick_connect.dart';
import 'settings_dialog.dart';
import 'sidebar.dart';
import 'sftp_panel.dart';
import 'terminal_panel.dart';
import 'theme.dart';
import 'transfer_bar.dart';
import 'widgets/common.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  double _sftpFraction = 0.48;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<AppStore>();
      store.hostKeyPrompter = _promptHostKey;
      // 仓库是异步初始化的，解密警告可能在 init 完成时才出现，
      // 所以监听而不是只在首帧读一次
      store.addListener(_checkStorageWarning);
      _checkStorageWarning();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context.read<AppStore>().removeListener(_checkStorageWarning);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台就暂停监控轮询，回来再续上
    context.read<AppStore>().setAppActive(state == AppLifecycleState.resumed);
  }

  void _checkStorageWarning() {
    if (!mounted) return;
    final store = context.read<AppStore>();
    final warning = store.storageWarning;
    if (warning == null) return;
    store.consumeStorageWarning();
    _toast(warning);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF232A35),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<bool> _promptHostKey(
    SshConnection connection,
    String keyType,
    String fingerprint,
    bool changed,
  ) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
        title: Row(
          children: [
            Icon(
              changed ? Icons.gpp_maybe_outlined : Icons.shield_outlined,
              size: 18,
              color: changed ? AppColors.danger : AppColors.warning,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                changed ? '主机密钥已变更' : '首次连接该主机',
                style: AppText.h1,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                changed
                    ? '这台服务器出示的密钥与上次记录不一致。可能是系统被重装，'
                          '也可能是中间人攻击——确认无误后再继续。'
                    : '这是第一次连接到该主机，请核对下面的指纹后再信任。',
                style: AppText.secondary,
              ),
              const SizedBox(height: 14),
              _infoRow('主机', connection.address),
              _infoRow('密钥类型', keyType),
              const SizedBox(height: 10),
              const FieldLabel(text: 'SHA256 指纹'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: SelectableText(fingerprint, style: AppText.mono),
              ),
              const SizedBox(height: 10),
              Text(
                changed
                    ? '信任后将更新本机记录的指纹。'
                    : '信任后会把该指纹记录到本地，之后连接会自动校验。',
                style: AppText.tertiary,
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: changed
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(changed ? '仍然信任并更新' : '信任并继续'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
          Expanded(
            child: Text(value, style: AppText.mono),
          ),
        ],
      ),
    );
  }

  Future<void> _newConnection() async {
    final store = context.read<AppStore>();
    final result = await ConnectionEditorDialog.show(
      context,
      categories: store.settings.categories,
      onAddCategory: store.addCategory,
      onDeleteCategory: store.deleteCategory,
    );
    if (result == null) return;
    await store.saveConnection(result);
    await store.openConnection(result);
  }

  Future<void> _quickConnect() async {
    final store = context.read<AppStore>();
    final input = await showPromptDialog(
      context,
      title: '快速连接',
      description: '输入 user@host 或 user@host:port，直接建立临时会话（不保存到连接列表）',
      hintText: 'root@192.168.1.10:22',
      confirmText: '连接',
    );
    if (input == null || input.trim().isEmpty) return;
    final target = parseQuickTarget(input);
    if (target == null) {
      _toast('格式不正确，示例：root@10.0.0.2:22');
      return;
    }
    await store.openConnection(
      SshConnection(
        host: target.host,
        port: target.port,
        username: target.username,
        group: '临时',
      ),
    );
  }

  Future<void> _closeTab(TerminalTab tab) async {
    final store = context.read<AppStore>();
    if (store.settings.confirmBeforeClose && tab.isConnected) {
      final confirmed = await showConfirmDialog(
        context,
        title: '关闭会话',
        message: '「${tab.connection.displayName}」仍在连接中，确定关闭吗？',
        confirmText: '关闭',
        danger: true,
      );
      if (!confirmed) return;
    }
    await store.closeTab(tab.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _newConnection,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
            showSettingsDialog(context),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
          final tab = store.activeTab;
          if (tab != null) store.reconnectTab(tab);
        },
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          shift: true,
        ): () {
          final tab = store.activeTab;
          if (tab != null) store.toggleSftp(tab);
        },
        const SingleActivator(
          LogicalKeyboardKey.keyM,
          meta: true,
          shift: true,
        ): () {
          final tab = store.activeTab;
          if (tab != null) store.toggleMonitor(tab);
        },
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
            _quickConnect,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.canvas,
          body: Row(
            children: [
              SidebarView(
                onOpenSettings: () => showSettingsDialog(context),
              ),
              Expanded(
                child: Column(
                  children: [
                    _TabStrip(
                      onNewConnection: _newConnection,
                      onCloseTab: _closeTab,
                    ),
                    Expanded(child: _workspace(store)),
                    const TransferBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workspace(AppStore store) {
    final tab = store.activeTab;
    if (tab == null) {
      return const _WelcomeView();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final sftpWidth = (width * _sftpFraction).clamp(
          320.0,
          (width - 380).clamp(320.0, width),
        );

        return Row(
          children: [
            Expanded(
              child: TerminalPanel(
                key: ValueKey(tab.id),
                tab: tab,
                onClose: () => _closeTab(tab),
              ),
            ),
            if (tab.showSftp) ...[
              MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _sftpFraction =
                          (_sftpFraction - details.delta.dx / width).clamp(
                            0.22,
                            0.72,
                          );
                    });
                  },
                  child: Container(
                    width: 6,
                    color: Colors.transparent,
                    alignment: Alignment.center,
                    child: Container(
                      width: 1,
                      color: AppColors.border,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: sftpWidth,
                child: SftpPanel(
                  key: ValueKey('${tab.id}-sftp'),
                  tab: tab,
                  onClose: () => store.toggleSftp(tab),
                ),
              ),
            ],
            if (tab.showMonitor) ...[
              const SizedBox(width: 1, child: ColoredBox(color: AppColors.border)),
              SizedBox(
                width: 420,
                child: MonitorPanel(
                  key: ValueKey('${tab.id}-monitor'),
                  tab: tab,
                  onClose: () => store.toggleMonitor(tab),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.onNewConnection,
    required this.onCloseTab,
  });

  final VoidCallback onNewConnection;
  final Future<void> Function(TerminalTab tab) onCloseTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final tabs = store.tabs;

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.chrome,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 6, top: 4),
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                return _TabChip(
                  tab: tab,
                  active: tab.id == store.activeTabId,
                  onTap: () => store.activateTab(tab.id),
                  onClose: () => onCloseTab(tab),
                );
              },
            ),
          ),
          AppIconButton(
            icon: Icons.add,
            tooltip: '新建连接（⌘N）',
            onPressed: onNewConnection,
          ),
          AppIconButton(
            icon: Icons.bolt_outlined,
            tooltip: '快速连接（⌘T）',
            onPressed: () async {
              final target = await showPromptDialog(
                context,
                title: '快速连接',
                description: '输入 user@host 或 user@host:port，直接建立临时会话',
                hintText: 'root@192.168.1.10:22',
                confirmText: '连接',
              );
              if (target == null || target.trim().isEmpty) return;
              final parsed = parseQuickTarget(target);
              if (parsed == null) return;
              if (!context.mounted) return;
              await context.read<AppStore>().openConnection(
                SshConnection(
                  host: parsed.host,
                  port: parsed.port,
                  username: parsed.username,
                  group: '临时',
                ),
              );
            },
          ),
          AppIconButton(
            icon: Icons.settings_outlined,
            tooltip: '设置（⌘,）',
            onPressed: () => showSettingsDialog(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final TerminalTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final status = tab.status;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 3),
          padding: const EdgeInsets.only(left: 10, right: 6),
          constraints: const BoxConstraints(minWidth: 86, maxWidth: 140),
          decoration: BoxDecoration(
            color: widget.active ? AppColors.surface : Colors.transparent,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(7),
            ),
            border: Border(
              top: BorderSide(
                color: widget.active ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
              left: BorderSide(
                color: widget.active ? AppColors.border : Colors.transparent,
              ),
              right: BorderSide(
                color: widget.active ? AppColors.border : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Tooltip(
                message: sessionStatusLabel(status),
                child: StatusDot(
                  color: sessionStatusColor(status),
                  size: 6,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  // 标签一律显示用户自定义的连接名（如 ME-01），
                  // 不跟随远端 OSC 标题（那个是 root@主机名，长且无辨识度）
                  tab.connection.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.active
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: widget.active
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (_hover || widget.active)
                AppIconButton(
                  icon: Icons.close,
                  tooltip: '关闭标签',
                  size: 20,
                  iconSize: 12,
                  onPressed: widget.onClose,
                )
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final recent = [...store.connections]
      ..sort((a, b) {
        final left = a.lastConnectedAt;
        final right = b.lastConnectedAt;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/logo.png',
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Fast Shell',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '远程终端 · SFTP 文件传输 · 连接管理\n密码与私钥本地加密保存，主机指纹自动校验',
              textAlign: TextAlign.center,
              style: AppText.secondary,
            ),
            const SizedBox(height: 26),
            Text(
              '点击右上角 ＋ 新建连接，或按 ⌘N / ⌘T',
              style: AppText.secondary.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 30),
              Text(
                '最近连接',
                style: AppText.tertiary.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final connection in recent.take(6))
                    _RecentChip(connection: connection),
                ],
              ),
            ],
            const SizedBox(height: 34),
            Text(
              '⌘N 新建连接 · ⌘T 快速连接 · ⌘, 设置',
              style: AppText.tertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentChip extends StatefulWidget {
  const _RecentChip({required this.connection});

  final SshConnection connection;

  @override
  State<_RecentChip> createState() => _RecentChipState();
}

class _RecentChipState extends State<_RecentChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => context.read<AppStore>().openConnection(connection),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? AppColors.accentSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover
                  ? AppColors.accent.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.terminal,
                size: 13,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 7),
              Text(
                connection.displayName,
                style: const TextStyle(
                  fontSize: 12.3,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(connection.host, style: AppText.tertiary),
            ],
          ),
        ),
      ),
    );
  }
}
