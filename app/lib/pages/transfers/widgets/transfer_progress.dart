import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/progress_bar.dart';

double? transferProgressValue(int completed, int? total) =>
    total == null || total <= 0 ? null : (completed / total).clamp(0.0, 1.0);

/// 传输进度（Ardot 传输进度条 37:1209）：总量未知时不定进度，减少动态效果时停在起点。
class TransferProgress extends StatelessWidget {
  const TransferProgress({super.key, required this.value});
  final double? value;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.reduceMotionOf(context);
    return AppProgressBar(
      value: value ?? (reduceMotion ? 0 : null),
      semanticsLabel: value == null ? '正在传输' : '传输进度',
    );
  }
}
