import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';

import 'connection_failure_note.dart';

/// 连接过程正文的纵向位置：居中略偏上（与空态同为纵向 40%）。
const _contentAlignment = Alignment(0, -.2);

/// 并排的两个底部按钮在字号超过此倍数时改为纵排（design.md「文字」：横排可改为纵排）。
const _stackedButtonsScale = 1.5;

/// 连接过程（Ardot 2:965、9:264、2:2801）：全屏、无页头；中央为本机与手机的连线，
/// 下方 `large-title` 标题和 `subheadline` 阶段文字，底部为停靠尺寸按钮。
class ConnectionAttemptStatus extends StatelessWidget {
  const ConnectionAttemptStatus({
    super.key,
    required this.busy,
    required this.checking,
    required this.cancelling,
    required this.address,
    required this.paired,
    required this.pairing,
    required this.legacyTcp,
    required this.onCancel,
    required this.onEdit,
    required this.onRetry,
    required this.onRecheck,
    this.failure,
  });

  final bool busy, checking, cancelling, paired, pairing, legacyTcp;
  final String address;
  final SetupIssue? failure;
  final VoidCallback onCancel, onEdit, onRetry, onRecheck;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final code = failure?.code ?? '';
    final identityMismatch =
        code == 'device_identity_mismatch' || code == 'identity_mismatch';
    final needsCheck =
        code.contains('unknown') ||
        code.contains('unconfirmed') ||
        code == 'configuration_unverified';
    final pending = busy || checking || cancelling;
    final title = cancelling
        ? '正在取消连接'
        : pending
        ? '正在连接'
        : needsCheck
        ? '请检查连接'
        : '连接失败';
    final subtitle = switch ((
      pending,
      checking,
      cancelling,
      pairing,
      identityMismatch,
      needsCheck,
    )) {
      (true, _, true, _, _, _) => '正在结束本次连接尝试',
      (true, true, _, _, _, _) => '正在核对手机的连接状态',
      (true, _, _, true, _, _) => '正在配对并查找手机的连接地址',
      (true, _, _, _, _, _) => '正在与手机建立连接',
      (_, _, _, _, true, _) => '设备身份不一致',
      (_, _, _, _, _, true) => '暂时无法确认手机是否已连接。',
      _ => connectionFailureMessage(
        RequestFailure(code, failure?.message ?? ''),
        pairing: pairing && !paired,
        legacyTcp: legacyTcp,
      ),
    };
    final stage = pending
        ? _DiagramStage.connecting
        : identityMismatch || needsCheck
        ? _DiagramStage.attention
        : _DiagramStage.failed;
    final retry = !pending && !identityMismatch && !paired;
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > _stackedButtonsScale;
    final primary = AppButton(
      role: AppButtonRole.primary,
      expand: true,
      onPressed: retry
          ? needsCheck
                ? onRecheck
                : onRetry
          : onEdit,
      label: retry
          ? needsCheck
                ? '重新检查'
                : '重试连接'
          : '返回修改',
    );
    final edit = AppButton(
      role: AppButtonRole.secondaryOnPage,
      expand: true,
      onPressed: onEdit,
      label: '返回修改',
    );
    final Widget actions = pending
        ? AppButton(
            role: AppButtonRole.secondaryOnPage,
            expand: true,
            onPressed: cancelling ? null : onCancel,
            label: '取消连接',
          )
        : !retry
        ? primary
        : stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: DesignTokens.componentAlertActionsGap),
              edit,
            ],
          )
        : Row(
            children: [
              Expanded(child: edit),
              const SizedBox(width: DesignTokens.componentAlertActionsGap),
              Expanded(child: primary),
            ],
          );
    return Scaffold(
      backgroundColor: colors.page,
      body: DesktopStage(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignTokens.componentPageMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.componentPagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Align(
                          alignment: _contentAlignment,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              vertical: DesignTokens.spacingSm,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight:
                                        constraints.maxHeight /
                                        (2 *
                                            MediaQuery.textScalerOf(context)
                                                .scale(1)),
                                  ),
                                  child: _ConnectionDiagram(stage: stage),
                                ),
                                const SizedBox(
                                  height: DesignTokens.spacingXxxl,
                                ),
                                ContentArrival(
                                  state: title,
                                  child: Semantics(
                                    liveRegion: true,
                                    label: address.isEmpty ? null : address,
                                    child: Text(
                                      title,
                                      style: type.largeTitle,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: DesignTokens.spacingSm),
                                Semantics(
                                  liveRegion: pending,
                                  child: Text(
                                    subtitle,
                                    style: type.subheadline,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (!pending && identityMismatch) ...[
                                  const SizedBox(
                                    height: DesignTokens.spacingSm,
                                  ),
                                  Text(
                                    '这不是已保存的手机。请检查 IP 地址。',
                                    textAlign: TextAlign.center,
                                    style: type.subheadline.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      // 底部固定动作：底边留出安全区和 8（design.md「页面结构」）。
                      padding: const EdgeInsets.only(
                        top: DesignTokens.spacingSm,
                        bottom: DesignTokens.spacingSm,
                      ),
                      child: actions,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _DiagramStage { connecting, failed, attention }

/// 连接示意（Ardot 37:2557）各部件尺寸。
const _hostSize = 72.0;
const _hostRounded = DesignTokens.roundedLg;
const _hostGlyphSize = 32.0;
const _slotSize = 32.0;
const _lineWidth = 32.0;
const _lineHeight = 3.0;
const _phoneWidth = 64.0;
const _phoneHeight = 112.0;
const _phoneRounded = DesignTokens.roundedMd;
const _phoneBorder = 2.0;

class _ConnectionDiagram extends StatelessWidget {
  const _ConnectionDiagram({required this.stage});

  final _DiagramStage stage;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final label = AppTypography.of(context).footnote
        .copyWith(color: colors.textSecondary);
    final connecting = stage == _DiagramStage.connecting;
    Widget line(Color color) => Container(
      width: _lineWidth,
      height: _lineHeight,
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    );
    final slot = switch (stage) {
      _DiagramStage.connecting => const ExcludeSemantics(
        child: ContentLoadingIndicator(),
      ),
      _DiagramStage.failed => Icon(
        LucideIcons.circleX,
        size: DesignTokens.componentBarGlyphSize,
        color: colors.destructive,
      ),
      _DiagramStage.attention => Icon(
        LucideIcons.triangleAlert,
        size: DesignTokens.componentBarGlyphSize,
        color: colors.warning,
      ),
    };
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: _hostSize,
                height: _hostSize,
                decoration: ShapeDecoration(
                  color: colors.card,
                  shape: const RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(_hostRounded),
                    ),
                  ),
                ),
                child: Icon(
                  LucideIcons.monitor,
                  size: _hostGlyphSize,
                  color: colors.text,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingMd),
              line(connecting ? colors.primary : colors.separator),
              const SizedBox(width: DesignTokens.spacingSm),
              Container(
                width: _slotSize,
                height: _slotSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.card,
                  shape: BoxShape.circle,
                ),
                child: slot,
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              line(connecting ? colors.primaryContainer : colors.separator),
              const SizedBox(width: DesignTokens.spacingMd),
              Container(
                width: _phoneWidth,
                height: _phoneHeight,
                decoration: ShapeDecoration(
                  color: DesignTokens.colorDeviceScreen,
                  shape: RoundedSuperellipseBorder(
                    side: BorderSide(
                      color: colors.outline,
                      width: _phoneBorder,
                    ),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(_phoneRounded),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _hostSize,
                child: Text('本机', style: label, textAlign: TextAlign.center),
              ),
              const SizedBox(
                width:
                    2 * DesignTokens.spacingMd +
                    2 * _lineWidth +
                    2 * DesignTokens.spacingSm +
                    _slotSize,
              ),
              SizedBox(
                width: _phoneWidth,
                child: Text('手机', style: label, textAlign: TextAlign.center),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
