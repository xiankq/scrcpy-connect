import 'dart:math' as math;

import 'package:design_system/design_system.dart';
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
  });

  final RemotePresentation presentation;
  final bool independent;
  final VoidCallback onManageActivities;
  final VoidCallback onContinueOnPhoneScreen;
  final VoidCallback onCloseUnknownAppLaunch;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final exit = ExitHandle.initialBoundsFor(constraints.biggest, media);
      final belowExit = exit.bottom + DesignTokens.spacingSm;
      final bottom = math.max(DesignTokens.spacingXl, media.padding.bottom);
      final roomBelow = constraints.maxHeight - belowExit - bottom;
      // 较矮的横屏使用退出控件旁边的空间，较高布局则预留顶部区域。
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
            child: Glass(
              radius: DesignTokens.roundedLg,
              padding: const EdgeInsets.all(DesignTokens.spacingLg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      presentation.paused
                          ? LucideIcons.pause
                          : LucideIcons.monitorOff,
                      size: DesignTokens.componentIconLargeSize,
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    Text(
                      presentation.sessionEnded
                          ? '控制会话已结束'
                          : presentation.qualityRetryable
                          ? '画面调整未完成'
                          : presentation.appLaunchUnknown
                          ? '应用打开结果待核对'
                          : presentation.stateUnverified
                          ? '正在核验会话状态'
                          : presentation.paused
                          ? '画面已暂停'
                          : '暂时无法打开实时画面',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      presentation.error ?? '等待连接恢复后的首帧。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    if (presentation.errorCode == 'resource_busy')
                      FilledButton(
                        onPressed: onManageActivities,
                        child: const Text('管理当前活动'),
                      ),
                    if (independent &&
                        presentation.error != null &&
                        !presentation.qualityRetryable &&
                        !presentation.appLaunchUnknown &&
                        !presentation.stateUnverified)
                      FilledButton(
                        onPressed: presentation.connecting
                            ? null
                            : onContinueOnPhoneScreen,
                        child: const Text('在手机屏幕继续'),
                      ),
                    if (presentation.appLaunchUnknown)
                      FilledButton(
                        onPressed: presentation.connecting
                            ? null
                            : onCloseUnknownAppLaunch,
                        child: const Text('关闭本次打开记录'),
                      ),
                    OutlinedButton(
                      onPressed: presentation.connecting ? null : onRetry,
                      child: Text(
                        presentation.qualityRetryable
                            ? '画面设置'
                            : presentation.appLaunchUnknown
                            ? '只读检查'
                            : presentation.appLaunchClosed
                            ? '重新打开'
                            : '重新检查',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
