import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ssh_session.dart';
import '../theme.dart';

/// 会话状态对应的圆点颜色（标签页与侧栏共用同一套，避免出现不一致）
Color sessionStatusColor(SessionStatus status) => switch (status) {
  SessionStatus.connected => AppColors.success,
  SessionStatus.connecting => AppColors.warning,
  SessionStatus.failed => AppColors.danger,
  SessionStatus.closed => AppColors.textTertiary,
  SessionStatus.idle => AppColors.textTertiary,
};

/// 会话状态文案
String sessionStatusLabel(SessionStatus status) => switch (status) {
  SessionStatus.connected => '已连接',
  SessionStatus.connecting => '连接中…',
  SessionStatus.failed => '连接失败',
  SessionStatus.closed => '已断开',
  SessionStatus.idle => '未连接',
};

/// 小尺寸图标按钮
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 16,
    this.size = 30,
    this.active = false,
    this.danger = false,
    this.radius = 7,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final double size;
  final bool active;
  final bool danger;
  final double radius;

  /// 自定义图标颜色（未指定时按启用/激活/危险态着色）
  final Color? iconColor;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Color iconColor;
    if (!enabled) {
      iconColor = AppColors.textTertiary.withValues(alpha: 0.6);
    } else if (widget.danger) {
      iconColor = AppColors.danger;
    } else if (widget.active) {
      iconColor = AppColors.accent;
    } else if (widget.iconColor != null) {
      iconColor = widget.iconColor!;
    } else {
      iconColor = AppColors.textSecondary;
    }

    final background = !enabled
        ? Colors.transparent
        : widget.active
        ? AppColors.accentSoft
        : (_hover ? AppColors.canvas : Colors.transparent);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(
                color: widget.active ? AppColors.accentSoft : Colors.transparent,
              ),
            ),
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// 连接状态小圆点
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 5),
        ],
      ),
    );
  }
}

/// 状态药丸标签
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String text;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组标题
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 空状态提示
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 22, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 14),
            Text(title, style: AppText.bodyStrong, textAlign: TextAlign.center),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                style: AppText.secondary,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// 单行输入弹窗
Future<String?> showPromptDialog(
  BuildContext context, {
  required String title,
  String? description,
  String initialValue = '',
  String? hintText,
  String confirmText = '确定',
}) async {
  final controller = TextEditingController(text: initialValue);

  void submit(NavigatorState navigator) {
    navigator.pop(controller.text);
  }

  final result = await showDialog<String>(
    context: context,
    // 显式给不透明背景：不依赖主题解析 colorScheme，避免出现「弹窗一片黑」
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (context) {
      final navigator = Navigator.of(context);
      return AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: AppText.h1),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description != null) ...[
                Text(description, style: AppText.secondary),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                style: AppText.body,
                decoration: InputDecoration(hintText: hintText),
                onSubmitted: (_) => submit(navigator),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => submit(navigator),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

/// 确认弹窗
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(title, style: AppText.h1),
      content: message == null
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(message, style: AppText.secondary),
            ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 复制到剪贴板并给出轻提示
Future<void> copyWithToast(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(
      content: const Text('已复制到剪贴板', style: TextStyle(fontSize: 12.5)),
      behavior: SnackBarBehavior.floating,
      width: 200,
      duration: const Duration(milliseconds: 1400),
      backgroundColor: const Color(0xFF232A35),
    ),
  );
}

/// 字段标签 + 内容
class FieldLabel extends StatelessWidget {
  const FieldLabel({super.key, required this.text, this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(hint!, style: AppText.tertiary),
          ],
        ],
      ),
    );
  }
}
