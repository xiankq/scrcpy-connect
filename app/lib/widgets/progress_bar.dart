import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 进度条：高 3 胶囊，`primary` 前景，`primary-container` 轨道。
///
/// [value] 为空时不定进度；读屏值由调用方在所属条目上提供，或通过 [semanticsLabel]。
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, this.value, this.semanticsLabel});

  final double? value;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return LinearProgressIndicator(
      value: value?.clamp(0, 1),
      minHeight: DesignTokens.componentProgressHeight,
      color: colors.primary,
      backgroundColor: colors.primaryContainer,
      borderRadius: const BorderRadius.all(
        Radius.circular(DesignTokens.componentProgressRounded),
      ),
      semanticsLabel: semanticsLabel,
    );
  }
}
