import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';

void feedback(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: lines,
        maxLines: lines + 3,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (s) {
          if (s.trim().isNotEmpty) Navigator.pop(context, s.trim());
        },
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
          child: Text(action),
        ),
      ],
    ),
  );
  // A route can still be completing its closing transition; disposal is deferred.
  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  return result;
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = '确认',
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
