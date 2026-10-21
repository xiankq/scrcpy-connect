import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Connection and authorization forms share body text and field feedback.
/// Applies to device settings as well as embedded USB and QR content.
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
          // InputDecorator scales a floating label by 0.75.
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

/// Authorization and connection changes retain the form's readable type scale.
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
