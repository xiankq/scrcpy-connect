import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/router/app_router.dart';

import 'qr_pairing_notifier.dart';

import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class QrPairingPage extends HookConsumerWidget {
  const QrPairingPage({
    super.key,
    this.deviceId,
    this.onUsePairingCode,
    this.onConnectionPort,
    this.onPaired,
    this.prepareConnection,
    this.autoGenerate = true,
  });
  final String? deviceId;
  final bool autoGenerate;
  final Future<bool> Function()? prepareConnection;
  final VoidCallback? onUsePairingCode;
  final ValueChanged<PairingReceipt>? onPaired;
  final void Function(String address, String? deviceId)? onConnectionPort;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = useQrPairingContent(
      context,
      ref,
      active: true,
      deviceId: deviceId,
      autoGenerate: autoGenerate,
      prepareConnection: prepareConnection,
      onConnectionPort: onConnectionPort,
      onPaired: onPaired,
      onUsePairingCode: onUsePairingCode,
      embedded: false,
    )!;
    return PageFrame(
      title: '添加设备',
      bottom: content.primary,
      child: ConnectionContent(
        child: GroupedListView(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.componentPagePadding,
            DesignTokens.spacingMd,
            DesignTokens.componentPagePadding,
            DesignTokens.componentPagePadding,
          ),
          children: [content.body],
        ),
      ),
    );
  }
}

({Widget body, Widget primary})? useQrPairingContent(
  BuildContext context,
  WidgetRef ref, {
  required bool active,
  required String? deviceId,
  required bool autoGenerate,
  required Future<bool> Function()? prepareConnection,
  required void Function(String, String?)? onConnectionPort,
  required ValueChanged<PairingReceipt>? onPaired,
  VoidCallback? onUsePairingCode,
  bool embedded = true,
}) {
  final deviceManagement = ref.watch(deviceManagementProvider);
  final setup = ref.watch(deviceSetupProvider);
  final scope = useMemoized(Object.new, [deviceId, active]);
  final viewScope = useRef(scope)..value = scope;
  final provider = qrPairingProvider(deviceId: deviceId, scope: scope);
  bool ownsView() =>
      context.mounted &&
      identical(viewScope.value, scope) &&
      identical(setup, ref.read(deviceSetupProvider)) &&
      identical(deviceManagement, ref.read(deviceManagementProvider));

  Future<void> generate() async {
    if (!ownsView() || ref.read(provider).busy) return;
    final allowed = await prepareConnection?.call() ?? true;
    if (!allowed || !ownsView()) return;
    await ref.read(provider.notifier).generate();
  }

  useEffect(() {
    if (active && autoGenerate) {
      Future.microtask(() {
        if (ownsView()) unawaited(generate());
      });
    }
    return null;
  }, [scope, setup, deviceManagement, autoGenerate]);

  if (!active) return null;
  final state = ref.watch(provider);
  final actions = ref.read(provider.notifier);
  ref.listen(provider.select((state) => state.receipt), (_, paired) {
    if (paired == null) return;
    onPaired?.call(paired);
    if (paired.connected && paired.deviceId != null) {
      WorkspaceRoute(deviceId: paired.deviceId!).pushReplacement(context);
    }
  });
  final colors = AppColors.of(context);
  final type = AppTypography.of(context);
  final paired = state.receipt;
  final hasQr = state.hasQr;
  final children = <Widget>[
    if (state.busy || hasQr)
      ContentPanel(
        padding: _qrCardPadding,
        child: Column(
          children: [
            if (hasQr)
              DecoratedBox(
                // 二维码固定在白底上，保证任何主题下都能被手机识别。
                decoration: const ShapeDecoration(
                  color: DesignTokens.colorOnMedia,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(DesignTokens.roundedMd),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingXxl),
                  child: QrImageView(data: state.payload!, size: _qrSize),
                ),
              )
            else
              const SizedBox.square(
                dimension: _qrTileSize,
                child: ContentLoadingIndicator(),
              ),
            if (hasQr && state.busy) ...[
              const SizedBox(height: DesignTokens.spacingLg),
              const ContentLoadingIndicator(),
            ],
          ],
        ),
      )
    else if (state.message == null)
      const StateNote('点击重新生成以获取配对二维码。'),
    if (state.message != null) StateNote(state.message!),
    if (hasQr) ...[
      const SizedBox(height: DesignTokens.spacingMd),
      Text(
        '在手机的无线调试中选择“使用二维码配对设备”，扫描此二维码。',
        style: type.subheadline.copyWith(color: colors.textSecondary),
      ),
    ],
    if (paired != null && paired.deviceId != null && !paired.connected)
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton(
          role: AppButtonRole.text,
          onPressed: () {
            if (onConnectionPort != null) {
              onConnectionPort(paired.address, paired.deviceId);
            } else {
              ConnectionFormRoute(
                transport: ConnectionTransport.tls,
                deviceId: paired.deviceId,
                address: paired.address,
              ).pushReplacement(context);
            }
          },
          label: '修改连接信息',
        ),
      ),
    if (!embedded) ...[
      const SizedBox(height: DesignTokens.spacingMd),
      AppButton(
        role: AppButtonRole.secondaryOnPage,
        expand: true,
        onPressed: state.busy
            ? null
            : () async {
                if (!await actions.cancel() ||
                    !context.mounted ||
                    !ownsView()) {
                  return;
                }
                if (onUsePairingCode != null) {
                  onUsePairingCode();
                  return;
                }
                ConnectionFormRoute(
                  pairing: true,
                  deviceId: ref.read(provider).receipt?.deviceId,
                ).pushReplacement(context);
              },
        label: '使用配对码',
      ),
    ],
  ];
  final primary = AppButton(
    role: AppButtonRole.primary,
    expand: true,
    onPressed: state.busy ? null : generate,
    label: '重新生成',
  );
  return (
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
    primary: primary,
  );
}

/// 扫码卡（Ardot 2:891）：`card` 内距 24，白色圆角 16 底块内放二维码。
const _qrCardPadding = EdgeInsets.all(DesignTokens.spacingXxl);
const _qrSize = 188.0;
const _qrTileSize = _qrSize + 2 * DesignTokens.spacingXxl;
