import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transfer_task.dart';
import '../services/local_io.dart';
import '../state/app_store.dart';
import 'theme.dart';
import 'widgets/common.dart';

class TransferBar extends StatelessWidget {
  const TransferBar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final transfers = store.transfers;
    if (transfers.isEmpty) return const SizedBox.shrink();

    final active = transfers.where((task) => task.isActive).toList();
    final finished = transfers.length - active.length;
    final collapsed = store.transferBarCollapsed;

    final totalBytes = active.fold<int>(
      0,
      (sum, task) => sum + task.totalBytes,
    );
    final doneBytes = active.fold<int>(
      0,
      (sum, task) => sum + task.transferredBytes,
    );
    final overall = totalBytes > 0 ? doneBytes / totalBytes : 0.0;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: store.toggleTransferBar,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    collapsed
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.swap_vert,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    active.isEmpty
                        ? '传输队列'
                        : '正在传输 ${active.length} 项',
                    style: const TextStyle(
                      fontSize: 12.3,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (finished > 0) ...[
                    const SizedBox(width: 8),
                    Text('· 已完成 $finished', style: AppText.tertiary),
                  ],
                  if (collapsed && active.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: overall,
                          minHeight: 4,
                          backgroundColor: AppColors.canvas,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (finished > 0)
                    TextButton(
                      onPressed: store.clearFinishedTransfers,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 26),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('清除已完成'),
                    ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 168),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 6),
                itemCount: transfers.length,
                itemBuilder: (context, index) {
                  final task = transfers[transfers.length - 1 - index];
                  return _TransferRow(
                    task: task,
                    onCancel: () => store.cancelTransfer(task),
                    onClear: () => store.removeTransfer(task),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.task,
    required this.onCancel,
    required this.onClear,
  });

  final TransferTask task;
  final VoidCallback onCancel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusIcon) = switch (task.status) {
      TransferStatus.done => (AppColors.success, Icons.check_circle_outline),
      TransferStatus.failed => (AppColors.danger, Icons.error_outline),
      TransferStatus.cancelled => (
        AppColors.textTertiary,
        Icons.do_not_disturb_on_outlined,
      ),
      _ => (AppColors.accent, Icons.sync),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Row(
        children: [
          Icon(
            task.direction == TransferDirection.upload
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            size: 13,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 190,
            child: Tooltip(
              message: task.direction == TransferDirection.download
                  ? '保存到 ${task.localPath}'
                  : '读取自 ${task.localPath}',
              child: Text(
                task.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: task.status == TransferStatus.done
                        ? 1
                        : task.progress,
                    minHeight: 5,
                    backgroundColor: AppColors.canvas,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Text(
              task.error != null
                  ? task.error!
                  : '${task.progressText}  ${task.speedText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: task.error != null
                  ? const TextStyle(fontSize: 11.5, color: AppColors.danger)
                  : AppText.tertiary,
            ),
          ),
          const SizedBox(width: 8),
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 4),
          if (task.isActive)
            AppIconButton(
              icon: Icons.close,
              tooltip: '取消',
              size: 24,
              iconSize: 13,
              danger: true,
              onPressed: onCancel,
            )
          else ...[
            if (task.direction == TransferDirection.download &&
                task.status == TransferStatus.done)
              AppIconButton(
                icon: Icons.folder_open_outlined,
                tooltip: '在访达中显示',
                size: 24,
                iconSize: 14,
                iconColor: const Color(0xFF2F9BD8),
                onPressed: () => LocalIo.revealInFinder(task.localPath),
              ),
            AppIconButton(
              icon: Icons.clear_all,
              tooltip: '清除记录',
              size: 24,
              iconSize: 14,
              onPressed: onClear,
            ),
          ],
        ],
      ),
    );
  }
}
