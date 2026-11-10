import 'dart:math' as math;

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/remote_presentation.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/widgets/exit_handle.dart';

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
  final VoidCallback onRetry;
  final bool waitingForFirstFrame;
  final VoidCallback? onReturn;

  String get _title => presentation.sessionEnded
      ? '控制会话已结束'
      : presentation.qualityRetryable
      ? '画面调整未完成'
      : presentation.appLaunchUnknown || presentation.stateUnverified
      ? waitingForFirstFrame
            ? '屏幕启动结果待确认'
            : presentation.appLaunchUnknown
            ? '应用打开结果待核对'
            : '正在核验会话状态'
      : waitingForFirstFrame
      ? independent
            ? '无法打开独立窗口'
            : '无法打开手机屏幕'
      : presentation.paused
      ? '画面已暂停'
      : '暂时无法打开实时画面';

  Widget _action(
    BuildContext context,
    String label,
    VoidCallback callback, {
    bool primary = false,
  }) {
    final onPressed = presentation.connecting ? null : callback;
    if (waitingForFirstFrame) {
      return TextButton(onPressed: onPressed, child: Text(label));
    }
    return primary
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label));
  }

  Widget _content(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!waitingForFirstFrame) ...[
          Icon(
            presentation.paused ? LucideIcons.pause : LucideIcons.monitorOff,
            size: DesignTokens.componentIconLargeSize,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
        ],
        Text(
          _title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: DesignTokens.spacingXs),
        Text(
          presentation.error ?? '等待连接恢复后的首帧。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        if (presentation.errorCode == 'resource_busy')
          _action(context, '管理当前活动', onManageActivities, primary: true),
        if (independent &&
            presentation.error != null &&
            !presentation.qualityRetryable &&
            !presentation.appLaunchUnknown &&
            !presentation.stateUnverified)
          _action(context, '在手机屏幕继续', onContinueOnPhoneScreen, primary: true),
        if (presentation.appLaunchUnknown)
          _action(context, '关闭本次打开记录', onCloseUnknownAppLaunch, primary: true),
        _action(
          context,
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
              : '重新检查',
          onRetry,
        ),
        if (waitingForFirstFrame && onReturn != null)
          TextButton(onPressed: onReturn, child: const Text('返回')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final exit = waitingForFirstFrame
          ? Rect.fromLTWH(
              media.padding.left + 20,
              media.padding.top + 12,
              44,
              44,
            )
          : ExitHandle.initialBoundsFor(constraints.biggest, media);
      final belowExit = exit.bottom + DesignTokens.spacingSm;
      final bottom = math.max(DesignTokens.spacingXl, media.padding.bottom);
      final roomBelow = constraints.maxHeight - belowExit - bottom;
      final below = roomBelow >= DesignTokens.componentRowHeight * 2;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          below
              ? math.max(DesignTokens.spacingXl, media.padding.left)
              : exit.right + DesignTokens.spacingSm,
          below
              ? belowExit
              : math.max(DesignTokens.spacingXl, media.padding.top),
          math.max(DesignTokens.spacingXl, media.padding.right),
          bottom,
        ),
        child: Center(
          child: SingleChildScrollView(
            key: const ValueKey('remote-recovery-content'),
            child: waitingForFirstFrame
                ? _content(context)
                : Glass(
                    radius: DesignTokens.roundedLg,
                    padding: const EdgeInsets.all(DesignTokens.spacingLg),
                    child: _content(context),
                  ),
          ),
        ),
      );
    },
  );
}
