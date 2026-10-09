import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/connection.dart';
import '../services/ssh_session.dart';
import '../state/app_store.dart';
import 'connection_editor.dart';
import 'quick_connect.dart';
import 'theme.dart';
import 'widgets/common.dart';

class SidebarView extends StatefulWidget {
  const SidebarView({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<SidebarView> createState() => _SidebarViewState();
}

class _SidebarViewState extends State<SidebarView> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _collapsed = {};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    final filtered = store.connections.where((connection) {
      if (_query.isEmpty) return true;
      final keyword = _query.toLowerCase();
      return connection.displayName.toLowerCase().contains(keyword) ||
          connection.host.toLowerCase().contains(keyword) ||
          connection.username.toLowerCase().contains(keyword) ||
          connection.group.toLowerCase().contains(keyword);
    }).toList();

    final grouped = <String, List<SshConnection>>{};
    for (final connection in filtered) {
      grouped.putIfAbsent(connection.group, () => []).add(connection);
    }
    final groupNames = grouped.keys.toList()..sort();

    return Container(
      width: 268,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(store),
          _searchBar(),
          Expanded(
            // 配置仓库是异步解密的，ready 之前显示载入态，
            // 避免闪一下「还没有连接」造成误判
            child: !store.ready
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(height: 10),
                        Text('正在载入连接…', style: AppText.tertiary),
                      ],
                    ),
                  )
                : store.connections.isEmpty
                    ? const EmptyHint(
                        icon: Icons.dns_outlined,
                        title: '还没有连接',
                        description: '点击右上角 +（或按 ⌘N）\n添加第一台服务器',
                      )
                    : filtered.isEmpty
                        ? const EmptyHint(
                            icon: Icons.search_off_outlined,
                            title: '没有匹配的连接',
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 12),
                            children: [
                              for (final group in groupNames) ...[
                                SectionLabel(
                                  text: group,
                                  trailing: AppIconButton(
                                    icon: _collapsed.contains(group)
                                        ? Icons.keyboard_arrow_right
                                        : Icons.keyboard_arrow_down,
                                    tooltip: _collapsed.contains(group)
                                        ? '展开'
                                        : '收起',
                                    size: 22,
                                    iconSize: 15,
                                    onPressed: () => setState(() {
                                      if (!_collapsed.remove(group)) {
                                        _collapsed.add(group);
                                      }
                                    }),
                                  ),
                                ),
                                if (!_collapsed.contains(group))
                                  for (final connection in grouped[group]!)
                                    _ConnectionTile(
                                      connection: connection,
                                      selected: store.selectedConnectionId ==
                                          connection.id,
                                      status: store.connectionStatus(
                                        connection.id,
                                      ),
                                      onTap: () => store.selectConnection(
                                        connection.id,
                                      ),
                                      onOpen: () =>
                                          store.openConnection(connection),
                                      onEdit: () => _editConnection(
                                        context,
                                        connection,
                                      ),
                                      onDuplicate: () =>
                                          store.duplicateConnection(
                                        connection,
                                      ),
                                      onDelete: () => _deleteConnection(
                                        context,
                                        connection,
                                      ),
                                      onClearHostKey: () async {
                                        await store.saveConnection(
                                          connection.copyWith(
                                            clearHostKey: true,
                                          ),
                                        );
                                      },
                                      onMoveUp:
                                          store.connections.indexOf(connection) >
                                                  0
                                              ? () => store.moveConnection(
                                                    connection,
                                                    -1,
                                                  )
                                              : null,
                                      onMoveDown:
                                          store.connections.indexOf(connection) <
                                                  store.connections.length - 1
                                              ? () => store.moveConnection(
                                                    connection,
                                                    1,
                                                  )
                                              : null,
                                    ),
                              ],
                            ],
                          ),
          ),
          _footer(store),
        ],
      ),
    );
  }

  Widget _header(AppStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/logo.png',
              width: 22,
              height: 22,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Fast Shell',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: TextField(
        controller: _search,
        style: AppText.body,
        onChanged: (value) => setState(() => _query = value.trim()),
        decoration: InputDecoration(
          hintText: '搜索连接',
          prefixIcon: const Icon(
            Icons.search,
            size: 15,
            color: AppColors.textTertiary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 30,
          ),
          fillColor: AppColors.surface,
          suffixIcon: _query.isEmpty
              ? null
              : AppIconButton(
                  icon: Icons.close,
                  tooltip: '清空',
                  size: 22,
                  iconSize: 14,
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 30,
          ),
        ),
        onSubmitted: (value) {
          final target = parseQuickTarget(value);
          if (target == null) return;
          final store = context.read<AppStore>();
          _search.clear();
          setState(() => _query = '');
          store.openConnection(
            SshConnection(
              host: target.host,
              port: target.port,
              username: target.username,
              group: '临时',
            ),
          );
        },
      ),
    );
  }

  Widget _footer(AppStore store) {
    final activeCount = store.tabs.where((tab) => tab.isConnected).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              store.connections.isEmpty
                  ? '共 0 个连接'
                  : '共 ${store.connections.length} 个连接 · $activeCount 个会话',
              style: AppText.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editConnection(
    BuildContext context,
    SshConnection connection,
  ) async {
    final store = context.read<AppStore>();
    final result = await ConnectionEditorDialog.show(
      context,
      initial: connection,
      categories: store.settings.categories,
      onAddCategory: store.addCategory,
      onDeleteCategory: store.deleteCategory,
    );
    if (result == null) return;
    await store.saveConnection(result);
  }

  Future<void> _deleteConnection(
    BuildContext context,
    SshConnection connection,
  ) async {
    final store = context.read<AppStore>();
    final confirmed = await showConfirmDialog(
      context,
      title: '删除连接',
      message: '确定删除「${connection.displayName}」吗？该操作不可撤销。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed) return;
    await store.deleteConnection(connection.id);
  }
}

class _ConnectionTile extends StatefulWidget {
  const _ConnectionTile({
    required this.connection,
    required this.selected,
    required this.status,
    required this.onTap,
    required this.onOpen,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onClearHostKey,
    this.onMoveUp,
    this.onMoveDown,
  });

  final SshConnection connection;
  final bool selected;

  /// 该连接当前会话状态；null 表示没有打开的会话
  final SessionStatus? status;

  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final Future<void> Function() onClearHostKey;

  /// 排序：null 表示已到头（菜单里置灰）
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<_ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<_ConnectionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    final background = widget.selected
        ? AppColors.accentSoft
        : (_hover ? Colors.black.withValues(alpha: 0.035) : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onOpen,
        onSecondaryTapDown: (details) {
          // 先选中被右键的那一行：列表里的蓝色高亮框即「本次操作对象」，
          // 菜单再与该行顶部对齐，一眼就能看出在操作哪台机器。
          widget.onTap();
          _showContextMenu(context, _menuAnchor());
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 1, 8, 1),
          padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: widget.selected
                  ? AppColors.accent.withValues(alpha: 0.25)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                connection.authType == SshAuthType.privateKey
                    ? Icons.vpn_key_outlined
                    : Icons.terminal,
                size: 15,
                color: widget.selected
                    ? AppColors.accent
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            connection.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.8,
                              height: 1.3,
                              fontWeight: widget.selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (widget.status != null) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: sessionStatusLabel(widget.status!),
                            child: StatusDot(
                              color: sessionStatusColor(widget.status!),
                              size: 6,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      connection.host.isEmpty ? '未配置主机' : connection.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.tertiary,
                    ),
                  ],
                ),
              ),
              if (_hover)
                AppIconButton(
                  icon: Icons.more_horiz,
                  tooltip: '更多',
                  size: 24,
                  iconSize: 15,
                  onPressed: () {
                    widget.onTap();
                    _showContextMenu(context, _menuAnchor());
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 菜单锚点：贴着当前连接行的右上角，顶部与该行顶部对齐。
  Offset _menuAnchor() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    final rowRight = box.localToGlobal(Offset(box.size.width, 0)).dx;
    final rowTop = box.localToGlobal(Offset.zero).dy;
    // 菜单自身有约 8px 内边距，回退 6px 后首项文字与行标题目视齐平
    return Offset(rowRight + 6, rowTop - 6);
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final selected = await showMenu<String>(
      context: context,
      // 默认的弹出动画明显拖慢节奏，直接秒出
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'open',
          height: 34,
          child: Text('打开终端'),
        ),
        const PopupMenuItem(value: 'edit', height: 34, child: Text('编辑连接')),
        const PopupMenuItem(value: 'duplicate', height: 34, child: Text('创建副本')),
        PopupMenuItem(
          value: 'copy',
          height: 34,
          enabled: widget.connection.host.isNotEmpty,
          child: const Text('复制 SSH 命令'),
        ),
        PopupMenuItem(
          value: 'up',
          height: 34,
          enabled: widget.onMoveUp != null,
          child: const Text('上移'),
        ),
        PopupMenuItem(
          value: 'down',
          height: 34,
          enabled: widget.onMoveDown != null,
          child: const Text('下移'),
        ),
        if (widget.connection.hostKeyFingerprint != null)
          const PopupMenuItem(
            value: 'forget',
            height: 34,
            child: Text('清除主机指纹'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          height: 34,
          child: Text(
            '删除',
            style: TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    );
    if (!context.mounted) return;

    switch (selected) {
      case 'open':
        widget.onOpen();
      case 'edit':
        widget.onEdit();
      case 'duplicate':
        widget.onDuplicate();
      case 'copy':
        final connection = widget.connection;
        final command = StringBuffer('ssh ${connection.username}@');
        command
          ..write(connection.host)
          ..write(connection.port == 22 ? '' : ' -p ${connection.port}');
        if (connection.authType == SshAuthType.privateKey &&
            connection.privateKeyPath.isNotEmpty) {
          command.write(' -i ${connection.privateKeyPath}');
        }
        await copyWithToast(context, command.toString());
      case 'up':
        widget.onMoveUp?.call();
      case 'down':
        widget.onMoveDown?.call();
      case 'forget':
        await widget.onClearHostKey();
      case 'delete':
        widget.onDelete();
    }
  }
}
