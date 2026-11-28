import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_opening_view.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

/// 画面上的恢复横幅最宽 340，不遮住整个画面。
const _bannerMaxWidth = 340.0;

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
    this.deviceLabel = '手机',
  });

  final RemotePresentation presentation;
  final bool independent;
  final VoidCallback onManageActivities;
  final VoidCallback onContinueOnPhoneScreen;
  final VoidCallback onCloseUnknownAppLaunch;
  final VoidCallback? onRetry;
  final bool waitingForFirstFrame;
  final VoidCallback? onReturn;

  /// 首帧失败的阶段卡片中「已连接」后的设备名。
  final String deviceLabel;

  String get _title => waitingForFirstFrame
      ? independent
            ? '无法打开独立应用画面'
            : '无法打开手机屏幕'
      : presentation.sessionEnded
      ? '控制会话已结束'
      : presentation.qualityRetryable
      ? '画面调整未完成'
      : presentation.paused
      ? '已暂停'
      : '无法打开画面';

  String get _retryLabel => presentation.qualityRetryable
      ? '画面与控制'
      : waitingForFirstFrame &&
            (presentation.appLaunchUnknown || presentation.stateUnverified)
      ? '重新核对'
      : presentation.appLaunchUnknown
      ? '只读检查'
      : presentation.appLaunchClosed
      ? '重新打开'
      : waitingForFirstFrame
      ? '重试'
      : '检查连接';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    // 首帧失败在页面底上原位显示：重试为唯一主动作，其余为次要胶囊；
    // 画面上的横幅用区块尺寸的文字按钮，避免遮住画面。
    final size = waitingForFirstFrame
        ? AppButtonSize.dock
        : AppButtonSize.section;
    final secondary = waitingForFirstFrame
        ? AppButtonRole.secondaryOnPage
        : AppButtonRole.text;
    Widget action(String label, VoidCallback callback) => AppButton(
      label: label,
      size: size,
      role: secondary,
      onPressed: presentation.connecting ? null : callback,
    );
    final retry = onRetry == null
        ? null
        : AppButton(
            label: _retryLabel,
            size: size,
            role: waitingForFirstFrame ? AppButtonRole.primary : secondary,
            icon: waitingForFirstFrame ? AppIcons.refresh : null,
            onPressed: presentation.connecting ? null : onRetry,
          );
    final actions = [
      if (presentation.errorCode == 'resource_busy')
        action('管理当前活动', onManageActivities),
      if (independent &&
          presentation.error != null &&
          !presentation.qualityRetryable &&
          !presentation.appLaunchUnknown &&
          !presentation.stateUnverified)
        action('移回手机屏幕', onContinueOnPhoneScreen),
      if (presentation.appLaunchUnknown)
        action('关闭本次打开记录', onCloseUnknownAppLaunch),
      if (!waitingForFirstFrame) ?retry,
      if (waitingForFirstFrame && onReturn != null)
        AppButton(
          label: '关闭',
          size: size,
          role: AppButtonRole.secondaryOnPage,
          onPressed: onReturn,
        ),
    ];
    final message = presentation.error ?? '连接恢复后，手机画面会继续显示。';

    if (waitingForFirstFrame) {
      // 首帧失败在等待原位显示（Ardot R1 9:858）：示意屏中央为失败标记，下方原因与阶段卡片，
      // 底部「重试」为唯一主动作，其余为次要胶囊。
      final buttons = [?retry, ...actions];
      return RemoteOpeningLayout(
        scrollKey: const ValueKey('remote-recovery-content'),
        phone: const RemotePhoneMock(child: RemoteOpeningFailureMark()),
        title: _title,
        detail: Semantics(
          liveRegion: true,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: type.subheadline.copyWith(color: colors.textSecondary),
          ),
        ),
        steps: remoteOpeningSteps(
          presentation,
          deviceLabel: deviceLabel,
          failed: true,
        ),
        footer: buttons.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignTokens.spacingSm,
                children: [
                  for (final button in buttons)
                    SizedBox(width: double.infinity, child: button),
                ],
              ),
      );
    }

    // 画面上的恢复提示是横幅：圆角 24、内距 18/12、`label` 标题（design.md「菜单、确认框与抽屉」）。
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          DesignTokens.spacingLg,
          DesignTokens.spacingSm,
          DesignTokens.spacingLg,
          0,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _bannerMaxWidth),
          child: ContentSurface(
            key: const ValueKey('remote-recovery-content'),
            radius: DesignTokens.componentBannerRounded,
            padding: EdgeInsets.fromLTRB(
              DesignTokens.componentBannerPadding,
              DesignTokens.spacingMd,
              DesignTokens.componentBannerPadding,
              actions.isEmpty ? DesignTokens.spacingMd : DesignTokens.spacingXs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Row(
                    spacing: DesignTokens.spacingSm,
                    children: [
                      Icon(
                        presentation.paused
                            ? LucideIcons.pause
                            : LucideIcons.monitorOff,
                        size: DesignTokens.componentSectionGlyphSize,
                        color: colors.primary,
                      ),
                      Expanded(child: Text(_title, style: type.label)),
                    ],
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingXxs),
                Text(
                  message,
                  style: type.footnote.copyWith(color: colors.textSecondary),
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
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
