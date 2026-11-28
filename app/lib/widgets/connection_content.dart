import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

/// 连接与授权表单共用正文和字段反馈，适用于设备设置以及内嵌 USB、二维码内容。
///
/// 字段为 `input`：输入 `body`；标签、说明 `footnote` + 次要色，错误 `footnote` + `error`。
class ConnectionContent extends StatelessWidget {
  const ConnectionContent({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final body = type.body;
    final caption = type.footnote.copyWith(color: colors.textSecondary);
    TextStyle labelStyle(TextStyle style, Set<WidgetState> states) =>
        style.copyWith(
          color: states.contains(WidgetState.error)
              ? colors.error
              : states.contains(WidgetState.focused)
              ? colors.text
              : colors.textSecondary,
        );
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(titleLarge: body, bodyLarge: body),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.componentInputPadding,
            vertical: DesignTokens.spacingSm,
          ),
          labelStyle: WidgetStateTextStyle.resolveWith(
            (states) => labelStyle(body, states),
          ),
          // InputDecorator 会将浮动标签缩放为 0.75 倍。
          floatingLabelStyle: WidgetStateTextStyle.resolveWith(
            (states) => labelStyle(
              caption.copyWith(fontSize: caption.fontSize! / .75),
              states,
            ),
          ),
          hintStyle: body.copyWith(color: colors.textSecondary),
          helperStyle: caption,
          helperMaxLines: 3,
          errorMaxLines: 3,
          errorStyle: type.footnote.copyWith(color: colors.error),
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
    await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => ConnectionContent(
        child: AppAlertDialog(
          glass: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: danger ? destructiveFilledStyle(dialogContext) : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ),
    ) ??
    false;
