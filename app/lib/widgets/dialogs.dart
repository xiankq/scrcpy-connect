import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';

void feedback(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(glassSnackBar(message));

/// A neutral foreground follows the glass appearance, rather than SnackBar's
/// inverse default text colors. Build it in the receiving messenger's context.
SnackBar glassSnackBar(String message) => SnackBar(
  behavior: SnackBarBehavior.floating,
  backgroundColor: Colors.transparent,
  elevation: 0,
  padding: EdgeInsets.zero,
  content: Builder(
    builder: (context) => Glass(
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
Future<Json?> perform(
  BuildContext context,
  AppController controller,
  String command, [
  Json params = const {},
  String? success,
]) async {
  try {
    final result = await controller.request(command, params);
    if (context.mounted && success != null) feedback(context, success);
    return result;
  } catch (error) {
    if (context.mounted) feedback(context, '$error');
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
}) => showGlassDialog<String>(
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
  Widget build(BuildContext context) => GlassAlertDialog(
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
    await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: ConnectTokens.danger)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
