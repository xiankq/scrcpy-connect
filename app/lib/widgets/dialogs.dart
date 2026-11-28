import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/banner.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

export 'package:scrcpy_connect/widgets/banner.dart' show BannerTone;

void feedback(
  BuildContext context,
  String message, {
  BannerTone tone = BannerTone.info,
}) => ScaffoldMessenger.of(context).showSnackBar(
  appSnackBar(message, tone: tone),
  snackBarAnimationStyle: reduceMotionOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(reverseDuration: bannerExitDuration),
);

/// 文字反馈以横幅呈现；停留时长随语气（信息、成功 3 秒，警告 5 秒，错误 6 秒）。
SnackBar appSnackBar(String message, {BannerTone tone = BannerTone.info}) =>
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DesignTokens.colorOnMedia.withAlpha(0),
      elevation: 0,
      padding: EdgeInsets.zero,
      duration: tone.duration,
      content: AppBanner(message: message, tone: tone),
    );

Future<T?> performAction<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
  String failure = '操作未完成。请稍后重试。',
}) async {
  try {
    final result = await action();
    if (context.mounted && success != null) {
      feedback(context, success, tone: BannerTone.success);
    }
    return result;
  } catch (error) {
    if (context.mounted) {
      feedback(
        context,
        failureMessage(error, fallback: failure),
        tone: BannerTone.error,
      );
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
          const SizedBox(height: DesignTokens.spacingSm),
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

/// 确认框：取消为次要胶囊，确认为主要胶囊；[danger] 时确认为 `destructive` 实色白字。
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
        glass: true,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger ? destructiveFilledStyle(context) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action, textAlign: TextAlign.center),
          ),
        ],
      ),
    ) ??
    false;

/// 确认框主位置上的危险动作：`destructive` 实色、白色标签。
ButtonStyle destructiveFilledStyle(BuildContext context) =>
    FilledButton.styleFrom(
      backgroundColor: AppColors.of(context).destructive,
      foregroundColor: DesignTokens.colorOnMedia,
    );
