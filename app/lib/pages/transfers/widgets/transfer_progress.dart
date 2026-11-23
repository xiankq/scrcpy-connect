import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

double? transferProgressValue(int completed, int? total) =>
    total == null || total <= 0 ? null : (completed / total).clamp(0.0, 1.0);

class TransferProgress extends StatelessWidget {
  const TransferProgress({super.key, required this.value});
  final double? value;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.reduceMotionOf(context);
    return LinearProgressIndicator(
      value: value ?? (reduceMotion ? 0 : null),
      semanticsLabel: value == null ? '正在传输' : '传输进度',
      minHeight: DesignTokens.componentTransferProgressHeight,
      borderRadius: const BorderRadius.all(
        Radius.circular(DesignTokens.componentTransferProgressRounded),
      ),
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? DesignTokens.componentTransferProgressDarkBackgroundColor
          : DesignTokens.componentTransferProgressBackgroundColor,
    );
  }
}
