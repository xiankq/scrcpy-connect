import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// 连接与授权表单共用正文和字段反馈，适用于设备设置以及内嵌 USB、二维码内容。
class ConnectionContent extends StatelessWidget {
  const ConnectionContent({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w400,
    );
    final caption = theme.textTheme.bodySmall!.copyWith(
      fontWeight: FontWeight.w400,
    );
    TextStyle labelStyle(TextStyle style, Set<WidgetState> states) =>
        style.copyWith(
          color: states.contains(WidgetState.error)
              ? theme.colorScheme.error
              : states.contains(WidgetState.focused)
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        );
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(titleLarge: body, bodyLarge: body),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.componentConnectionFieldPadding,
            vertical: DesignTokens.spacingXs,
          ),
          labelStyle: WidgetStateTextStyle.resolveWith(
            (states) => labelStyle(body, states),
          ),
          // InputDecorator 会将浮动标签缩放为 0.75 倍。
          floatingLabelStyle: WidgetStateTextStyle.resolveWith(
            (states) => labelStyle(
              caption.copyWith(
                fontSize: DesignTokens.typographyCaptionFontSize / .75,
              ),
              states,
            ),
          ),
          hintStyle: body.copyWith(color: theme.colorScheme.onSurfaceVariant),
          helperStyle: caption,
          helperMaxLines: 3,
          errorMaxLines: 3,
          errorStyle: caption.copyWith(color: theme.colorScheme.error),
          counterStyle: caption,
        ),
      ),
      child: DefaultTextStyle(style: body, child: child),
    );
  }
}

/// 授权与连接切换保持表单文字的可读字号。
Future<bool> confirmConnectionChange(
  BuildContext context,
  String title,
  String message, {
  required String action,
  bool danger = false,
}) async =>
    await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => ConnectionContent(
        child: GlassAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: ConnectTokens.danger,
                    )
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ),
    ) ??
    false;
