import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../services/ssh_session.dart';
import '../state/app_store.dart';
import 'theme.dart';
import 'widgets/common.dart';

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({
    super.key,
    required this.tab,
    required this.onClose,
  });

  final TerminalTab tab;
  final VoidCallback onClose;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'terminal');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _copySelection() async {
    final tab = widget.tab;
    final range = tab.terminalController.selection;
    if (range == null) return;
    final text = tab.terminal.buffer.getText(range);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    tab.terminalController.clearSelection();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    widget.tab.terminal.paste(text);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final tab = widget.tab;
    final status = tab.status;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _copySelection,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _paste,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            store.clearTerminal(tab),
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
            store.changeFontSize(1),
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
            store.changeFontSize(-1),
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            widget.onClose,
      },
      child: Column(
        children: [
          _toolbar(store, tab, status),
          Expanded(
            child: Container(
              color: AppColors.terminalBackdrop,
              child: Stack(
                children: [
                  Positioned.fill(
                    // 终端每来一段输出就重绘一次，用 RepaintBoundary 把它
                    // 和窗口其余部分隔开，避免牵连整页重绘
                    child: RepaintBoundary(
                      child: TerminalView(
                        tab.terminal,
                        controller: tab.terminalController,
                        focusNode: _focusNode,
                        autofocus: true,
                        theme: appTerminalTheme,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        textStyle: TerminalStyle(
                          fontSize: store.settings.fontSize,
                          height: 1.32,
                          fontFamily: 'SF Mono',
                          fontFamilyFallback: const [
                            'Menlo',
                            'Monaco',
                            'PingFang SC',
                            'monospace',
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (status == SessionStatus.connecting)
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: _ProgressLine(),
                    ),
                ],
              ),
            ),
          ),
          _keyBar(tab),
        ],
      ),
    );
  }

  Widget _toolbar(AppStore store, TerminalTab tab, SessionStatus status) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      // 左侧的 状态点 / user@host / 状态文字 已删：与上方标签页完全重复，
      // 连接失败的原因会直接打印在终端里，重连入口保留在右侧。
      child: Row(
        children: [
          const Spacer(),
          if (status == SessionStatus.failed ||
              status == SessionStatus.closed) ...[
            TextButton.icon(
              onPressed: () => store.reconnectTab(tab),
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('重新连接'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
              ),
            ),
            const SizedBox(width: 2),
          ],
          AppIconButton(
            icon: Icons.monitor_heart_outlined,
            tooltip: '服务器监控（⌘⇧M）',
            active: tab.showMonitor,
            iconColor: const Color(0xFF12B5A5),
            onPressed: () => store.toggleMonitor(tab),
          ),
          AppIconButton(
            icon: Icons.article_outlined,
            tooltip: 'SFTP 文件（⌘⇧F）',
            active: tab.showSftp,
            onPressed: () => store.toggleSftp(tab),
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: '降低字号（⌘-）',
            onPressed: () => store.changeFontSize(-1),
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_up,
            tooltip: '提高字号（⌘+）',
            onPressed: () => store.changeFontSize(1),
          ),
          AppIconButton(
            icon: Icons.cleaning_services_outlined,
            tooltip: '清屏（⌘K）',
            onPressed: () => store.clearTerminal(tab),
          ),
          AppIconButton(
            icon: Icons.power_settings_new,
            tooltip: tab.isConnected ? '断开连接' : '关闭标签',
            danger: tab.isConnected,
            onPressed: () {
              if (tab.isConnected) {
                store.disconnectTab(tab);
              } else {
                widget.onClose();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _keyBar(TerminalTab tab) {
    Widget key(String label, String sequence, {String? tooltip}) {
      return _VirtualKey(
        label: label,
        tooltip: tooltip ?? label,
        onPressed: tab.isConnected
            ? () {
                tab.session.writeString(sequence);
                _focusNode.requestFocus();
              }
            : null,
      );
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          key('Esc', '\x1b'),
          key('Tab', '\t'),
          key('Ctrl+C', '\x03', tooltip: '发送中断信号'),
          key('Ctrl+D', '\x04', tooltip: '发送 EOF'),
          key('↑', '\x1b[A'),
          key('↓', '\x1b[B'),
          key('←', '\x1b[D'),
          key('→', '\x1b[C'),
          const Spacer(),
          Text(
            '⌘K 清屏 · ⌘C/⌘V 复制粘贴 · ⌘W 关闭标签',
            style: AppText.tertiary,
          ),
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.help_outline,
            tooltip: '快捷键说明',
            size: 24,
            iconSize: 14,
            onPressed: () => _showShortcuts(context),
          ),
        ],
      ),
    );
  }

  void _showShortcuts(BuildContext context) {
    const items = <(String, String)>[
      ('⌘ K', '清空终端显示与回滚缓冲'),
      ('⌘ C', '复制选中的文本'),
      ('⌘ V', '粘贴到终端'),
      ('⌘ +  /  ⌘ -', '调整终端字号'),
      ('⌘ ⇧ F', '打开 / 收起文件面板'),
      ('⌘ W', '关闭当前标签'),
      ('⌘ N', '新建连接'),
      ('⌘ R', '重新连接当前会话'),
      ('Esc / Tab', '发送转义与制表符'),
      ('Ctrl + C', '发送中断信号'),
    ];

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('快捷键', style: AppText.h1),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 104,
                        child: Text(
                          item.$1,
                          style: AppText.mono.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(child: Text(item.$2, style: AppText.secondary)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _VirtualKey extends StatefulWidget {
  const _VirtualKey({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<_VirtualKey> createState() => _VirtualKeyState();
}

class _VirtualKeyState extends State<_VirtualKey> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _hover && enabled ? AppColors.canvas : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                fontFamily: 'SF Mono',
                fontFamilyFallback: const ['Menlo', 'monospace'],
                color: enabled
                    ? AppColors.textSecondary
                    : AppColors.textTertiary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine();

  @override
  Widget build(BuildContext context) {
    return const LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Colors.transparent,
      color: AppColors.accent,
    );
  }
}

