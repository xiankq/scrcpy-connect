import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_setup_receipt.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';

class ConnectionAttemptStatus extends StatelessWidget {
  const ConnectionAttemptStatus({
    super.key,
    required this.busy,
    required this.checking,
    required this.cancelling,
    required this.deviceName,
    required this.paired,
    required this.onCancel,
    required this.onEdit,
    required this.onRetry,
    required this.onRecheck,
    required this.onConnectionPort,
    this.failure,
  });

  final bool busy, checking, cancelling, paired;
  final String deviceName;
  final SetupIssue? failure;
  final VoidCallback onCancel, onEdit, onRetry, onRecheck, onConnectionPort;

  @override
  Widget build(BuildContext context) {
    final code = failure?.code ?? '';
    final mismatched =
        code == 'device_identity_mismatch' || code == 'identity_mismatch';
    final unknown =
        code.contains('unknown') ||
        code.contains('unconfirmed') ||
        code == 'configuration_unverified';
    final authorization =
        code == 'authorization_required' || code == 'auth_failed';
    final title = mismatched
        ? '设备身份不符'
        : unknown
        ? '连接结果待确认'
        : paired
        ? '已配对，尚未连接'
        : authorization
        ? '请在手机上允许调试连接'
        : '连接未完成';
    final message = mismatched
        ? '响应设备与已保存设备不一致，请核对目标并修改连接信息。'
        : unknown
        ? '尚未确认本次连接结果。重新核对只检查当前状态，不会重发连接请求。'
        : paired && failure == null
        ? '配对授权已保留，请补充手机无线调试主页面的连接端口。'
        : failure?.message ?? '尚未确认连接可用，请检查地址、端口和手机授权。';
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Semantics(
        label: busy ? '正在连接设备 $deviceName' : '$title，$deviceName',
        liveRegion: true,
        child: Stack(
          children: [
            if (busy)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: DesignTokens.spacingMd),
                    Text('正在连接设备…', style: text.bodyMedium),
                  ],
                ),
              ),
            if (!busy)
              Positioned.fill(
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.spacingLg,
                        DesignTokens.componentIconButtonSize +
                            DesignTokens.spacingLg,
                        DesignTokens.spacingLg,
                        DesignTokens.spacingLg,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              (constraints.maxHeight -
                                      DesignTokens.componentIconButtonSize -
                                      DesignTokens.spacingLg * 2)
                                  .clamp(0, double.infinity),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth:
                                  DesignTokens.componentPageContentMaxWidth,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  title,
                                  style: text.titleLarge?.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: DesignTokens.spacingSm),
                                Text(
                                  message,
                                  style: text.bodyLarge?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: DesignTokens.spacingLg),
                                if (!mismatched)
                                  TextButton(
                                    onPressed: checking
                                        ? null
                                        : unknown
                                        ? onRecheck
                                        : paired
                                        ? onConnectionPort
                                        : onRetry,
                                    child: Text(
                                      checking
                                          ? '正在核对…'
                                          : unknown
                                          ? '重新核对'
                                          : paired
                                          ? '补充连接端口'
                                          : authorization
                                          ? '重新检查'
                                          : '重试',
                                    ),
                                  ),
                                TextButton(
                                  onPressed: checking ? null : onEdit,
                                  child: Text(
                                    mismatched ||
                                            (!unknown &&
                                                !paired &&
                                                !authorization)
                                        ? '返回修改'
                                        : '返回',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + DesignTokens.spacingMd,
              left: DesignTokens.spacingMd,
              child: GlassSurfaceGroup(
                child: GlassActionIcon(
                  tooltip: cancelling ? '正在取消…' : '关闭',
                  icon: const Icon(LucideIcons.x),
                  onPressed: cancelling ? null : onCancel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
