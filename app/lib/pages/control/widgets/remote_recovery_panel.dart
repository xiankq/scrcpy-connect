import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

class RemoteRecoveryPanel extends StatelessWidget {
  const RemoteRecoveryPanel({
    super.key,
    required this.presentation,
    required this.independent,
    required this.onManageActivities,
    required this.onContinueOnPhoneScreen,
    required this.onCloseUnknownAppLaunch,
    required this.onRetry,
    this.waitingForFirstFrame = false,
    this.onReturn,
  });

  final RemotePresentation presentation;
  final bool independent;
  final VoidCallback onManageActivities;
  final VoidCallback onContinueOnPhoneScreen;
  final VoidCallback onCloseUnknownAppLaunch;
  final VoidCallback? onRetry;
  final bool waitingForFirstFrame;
  final VoidCallback? onReturn;

  String get _title => waitingForFirstFrame
      ? '无法打开'
      : presentation.sessionEnded
      ? '控制会话已结束'
      : presentation.qualityRetryable
      ? '画面调整未完成'
      : presentation.paused
      ? '已暂停'
      : '无法打开画面';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget action(String label, VoidCallback callback) => TextButton(
      onPressed: presentation.connecting ? null : callback,
      child: Text(label),
    );
    final actions = [
      if (presentation.errorCode == 'resource_busy')
        action('管理当前活动', onManageActivities),
      if (independent &&
          presentation.error != null &&
          !presentation.qualityRetryable &&
          !presentation.appLaunchUnknown &&
          !presentation.stateUnverified)
        action('在手机屏幕继续', onContinueOnPhoneScreen),
      if (presentation.appLaunchUnknown)
        action('关闭本次打开记录', onCloseUnknownAppLaunch),
      if (onRetry != null)
        action(
          presentation.qualityRetryable
              ? '画面与控制'
              : waitingForFirstFrame &&
                    (presentation.appLaunchUnknown ||
                        presentation.stateUnverified)
              ? '重新核对'
              : presentation.appLaunchUnknown
              ? '只读检查'
              : presentation.appLaunchClosed
              ? '重新打开'
              : waitingForFirstFrame
              ? '重试'
              : '检查连接',
          onRetry!,
        ),
      if (waitingForFirstFrame && onReturn != null)
        TextButton(onPressed: onReturn, child: const Text('返回')),
    ];
    final message = presentation.error ?? '等待连接恢复后的首帧。';

    if (waitingForFirstFrame) {
      return SafeArea(
        child: Center(
          child: SingleChildScrollView(
            key: const ValueKey('remote-recovery-content'),
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: DesignTokens.spacingSm),
                  Wrap(alignment: WrapAlignment.center, children: actions),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: ContentSurface(
            key: const ValueKey('remote-recovery-content'),
            radius: DesignTokens.roundedLg,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      Icon(
                        presentation.paused
                            ? LucideIcons.pause
                            : LucideIcons.monitorOff,
                        size: DesignTokens.componentIconSmallSize,
                      ),
                      const SizedBox(width: DesignTokens.spacingXs),
                      Expanded(
                        child: Text(_title, style: theme.textTheme.titleMedium),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingXxs),
                Text(
                  message,
                  style: theme.textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (actions.isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: actions,
                    ),
                  )
                else
                  const SizedBox(height: DesignTokens.spacingXs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
