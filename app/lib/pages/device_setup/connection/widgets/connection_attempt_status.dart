import 'package:scrcpy_connect/core/errors/request_failure.dart';

import 'connection_failure_note.dart';

import 'package:scrcpy_connect/widgets/content.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class ConnectionAttemptStatus extends StatelessWidget {
  const ConnectionAttemptStatus({
    super.key,
    required this.busy,
    required this.checking,
    required this.cancelling,
    required this.deviceName,
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
  final String deviceName;
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
    final accent = pending
        ? dark
              ? DesignTokens.componentConnectionSignalDarkBackgroundColor
              : DesignTokens.componentConnectionSignalBackgroundColor
        : theme.colorScheme.error;
    final title = cancelling
        ? '正在取消连接'
        : pending
        ? '正在连接'
        : needsCheck
        ? '请检查连接'
        : '连接失败';
    final subtitle = pending
        ? deviceName.isNotEmpty
              ? deviceName
              : '正在与设备建立连接'
        : identityMismatch
        ? '这个地址对应另一台手机。请返回核对手机上的连接信息。'
        : needsCheck
        ? '暂时无法确认手机是否已连接。'
        : connectionFailureMessage(
            RequestFailure(code, failure?.message ?? ''),
            pairing: pairing && !paired,
            legacyTcp: legacyTcp,
          );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(DesignTokens.spacingLg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 296),
                            child: Row(
                              children: [
                                _ConnectionEndpoint(icon: LucideIcons.monitor),
                                Expanded(
                                  child: Divider(
                                    color: accent.withValues(alpha: .45),
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: theme.colorScheme.surface,
                                    shape: const CircleBorder(),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      DesignTokens.spacingSm,
                                    ),
                                    child: pending
                                        ? ContentLoadingIndicator(
                                            size: DesignTokens
                                                .componentIconActionSize,
                                            color: accent,
                                          )
                                        : Icon(
                                            LucideIcons.unlink,
                                            color: accent,
                                            size: DesignTokens
                                                .componentIconActionSize,
                                          ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: accent.withValues(alpha: .45),
                                  ),
                                ),
                                _ConnectionEndpoint(
                                  icon: LucideIcons.smartphone,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingXl),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            title,
                            style: theme.textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingXs),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SizedBox(
                  width: double.infinity,
                  child: pending
                      ? OutlinedButton(
                          onPressed: cancelling ? null : onCancel,
                          child: const Text('取消连接'),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!identityMismatch && !paired)
                              FilledButton(
                                onPressed: needsCheck ? onRecheck : onRetry,
                                child: Text(needsCheck ? '重新检查' : '重试'),
                              ),
                            TextButton(
                              onPressed: onEdit,
                              child: const Text('返回修改'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionEndpoint extends StatelessWidget {
  const _ConnectionEndpoint({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
      color: Theme.of(context).colorScheme.surface,
    ),
    child: Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Icon(icon, size: DesignTokens.componentIconLargeSize),
    ),
  );
}
