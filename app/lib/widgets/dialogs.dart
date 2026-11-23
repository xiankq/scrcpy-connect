import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

void feedback(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(appSnackBar(message));

/// 文字反馈使用实体面，前景在接收消息的上下文中跟随明暗主题。
SnackBar appSnackBar(String message) => SnackBar(
  behavior: SnackBarBehavior.floating,
  backgroundColor: DesignTokens.colorTransparent,
  elevation: 0,
  padding: EdgeInsets.zero,
  content: Builder(
    builder: (context) => ContentSurface(
      radius: DesignTokens.roundedLg,
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
      ),
    ),
  ),
);
Future<T?> performAction<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
  String failure = '操作未完成。请稍后重试。',
}) async {
  try {
    final result = await action();
    if (context.mounted && success != null) feedback(context, success);
    return result;
  } catch (error) {
    if (context.mounted) {
      feedback(context, failureMessage(error, fallback: failure));
    }
    return null;
  }
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? label,
  String action = '保存',
  int lines = 1,
}) => showAppDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    initial: initial,
    label: label,
    action: action,
    lines: lines,
  ),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.label,
    required this.action,
    required this.lines,
  });

  final String title, initial, action;
  final String? label;
  final int lines;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          ExcludeSemantics(child: Text(widget.label!)),
          const SizedBox(height: DesignTokens.spacingXs),
        ],
        Semantics(
          label: widget.label,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: widget.lines,
            maxLines: widget.lines + 3,
            onSubmitted: (s) {
              if (s.trim().isNotEmpty) Navigator.pop(context, s.trim());
            },
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: Text(widget.action),
      ),
    ],
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = '确认',
  bool danger = false,
}) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
