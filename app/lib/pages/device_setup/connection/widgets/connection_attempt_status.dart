import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';

import 'connection_failure_note.dart';

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
    final code = failure?.code ?? '';
    final identityMismatch =
        code == 'device_identity_mismatch' || code == 'identity_mismatch';
    final needsCheck =
        code.contains('unknown') ||
        code.contains('unconfirmed') ||
        code == 'configuration_unverified';
    final pending = busy || checking || cancelling;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
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
    const buttonSize = Size.fromHeight(
      DesignTokens.componentButtonPrimaryHeight,
    );
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(DesignTokens.componentButtonPrimaryRounded),
      ),
    );
    final retry = !pending && !identityMismatch && !paired;
    return Scaffold(
      body: DesktopStage(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: const Alignment(0, -.31),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.spacingSm,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth:
                                DesignTokens.componentEmptyDeviceIntroWidth,
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
                                child: _ConnectionDiagram(pending: pending),
                              ),
                              const SizedBox(height: DesignTokens.roundedLg),
                              ContentArrival(
                                state: title,
                                child: Semantics(
                                  liveRegion: true,
                                  label: address.isEmpty ? null : address,
                                  child: Text(
                                    title,
                                    style: theme.textTheme.displaySmall?.copyWith(
                                      fontSize: DesignTokens
                                          .typographyConnectionTitleFontSize,
                                      fontWeight: DesignTokens
                                          .typographyConnectionTitleFontWeight,
                                      height: DesignTokens
                                          .typographyConnectionTitleLineHeight,
                                      letterSpacing: DesignTokens
                                          .typographyConnectionTitleLetterSpacing,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: DesignTokens.spacingSectionTitle,
                              ),
                              Semantics(
                                liveRegion: pending,
                                child: Text(
                                  subtitle,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: pending
                                        ? colors.onSurfaceVariant
                                        : colors.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              if (!pending && identityMismatch) ...[
                                const SizedBox(height: DesignTokens.spacingLg),
                                Text(
                                  '这不是已保存的手机。请检查 IP 地址。',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: DesignTokens.roundedMd,
                  ),
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesignTokens.componentEmptyDeviceIntroWidth,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: pending
                            ? OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: buttonSize,
                                  shape: buttonShape,
                                  backgroundColor: dark
                                      ? colors.surface
                                      : colors.surfaceContainerHigh,
                                  foregroundColor: colors.onSurface,
                                  side: dark
                                      ? BorderSide(
                                          color: colors.onSurfaceVariant,
                                        )
                                      : BorderSide.none,
                                ),
                                onPressed: cancelling ? null : onCancel,
                                child: const Text('取消连接'),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (retry) ...[
                                    TextButton(
                                      onPressed: onEdit,
                                      child: const Text('返回修改'),
                                    ),
                                    const SizedBox(
                                      height: DesignTokens.spacingMd,
                                    ),
                                  ],
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      minimumSize: buttonSize,
                                      shape: buttonShape,
                                    ),
                                    onPressed: retry
                                        ? needsCheck
                                              ? onRecheck
                                              : onRetry
                                        : onEdit,
                                    child: Text(
                                      retry
                                          ? needsCheck
                                                ? '重新检查'
                                                : '重试连接'
                                          : '返回修改',
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
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

class _ConnectionDiagram extends StatelessWidget {
  const _ConnectionDiagram({required this.pending});

  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final label = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final line = dark
        ? DesignTokens.componentConnectionTrackDarkBackgroundColor
        : DesignTokens.componentConnectionTrackBackgroundColor;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 342,
        height: 206,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 94,
              top: 80,
              child: Container(
                width: 156,
                height: DesignTokens.componentConnectionPathHeight,
                decoration: BoxDecoration(
                  color: dark
                      ? DesignTokens.componentConnectionPathDarkBackgroundColor
                      : DesignTokens.componentConnectionPathBackgroundColor,
                  borderRadius: BorderRadius.circular(
                    DesignTokens.componentConnectionPathRounded,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 28,
              top: 59,
              child: Image.asset(
                dark
                    ? 'assets/device/connection-host-dark.png'
                    : 'assets/device/connection-host.png',
                width: 86,
                height: 86,
              ),
            ),
            Positioned(
              left: 232,
              top: 30,
              child: Image.asset(
                'assets/device/connection-phone.png',
                width: 84,
                height: 144,
              ),
            ),
            for (final x in [pending ? 113.0 : 105.0, pending ? 189.0 : 191.0])
              Positioned(
                left: x,
                top: 101,
                child: Container(
                  width: pending ? 40 : 46,
                  height: DesignTokens.spacingMicro,
                  decoration: BoxDecoration(
                    color: line,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.roundedFull,
                    ),
                  ),
                ),
              ),
            if (pending)
              Positioned(
                left: 159,
                top: 90,
                child: ExcludeSemantics(
                  child: ContentLoadingIndicator(
                    size: DesignTokens.componentIconSize,
                    color: dark
                        ? DesignTokens.componentConnectionArcDarkBackgroundColor
                        : DesignTokens.componentConnectionArcBackgroundColor,
                  ),
                ),
              )
            else
              Positioned(
                left: 155,
                top: 86,
                child: Container(
                  width: DesignTokens.componentIconLargeSize,
                  height: DesignTokens.componentIconLargeSize,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    AppIcons.close,
                    size: DesignTokens.componentIconSmallSize,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            for (final (left, text) in const [(18.0, '本机'), (220.0, '手机')])
              Positioned(
                left: left,
                top: 177,
                width: 109,
                child: Text(text, style: label, textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
