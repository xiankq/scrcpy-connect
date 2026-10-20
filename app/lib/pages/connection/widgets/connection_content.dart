import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Connection forms use body text for input and captions for field feedback.
/// The scope also covers embedded USB and QR content without changing the app.
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
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          labelStyle: body.copyWith(color: theme.colorScheme.onSurfaceVariant),
          // InputDecorator scales a floating label by 0.75.
          floatingLabelStyle: caption.copyWith(
            fontSize: DesignTokens.typographyCaptionFontSize / .75,
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
