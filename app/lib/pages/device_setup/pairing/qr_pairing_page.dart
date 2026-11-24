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

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
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
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
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
  final paired = state.receipt;
  final hasQr = state.hasQr;
  final children = <Widget>[
    if (state.busy) const Center(child: CircularProgressIndicator()),
    if (hasQr)
      Center(
        child: Container(
          color: DesignTokens.colorWhite,
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: QrImageView(
            data: state.payload!,
            size: DesignTokens.componentPairingQrSize,
          ),
        ),
      )
    else if (!state.busy && state.message == null)
      const StateNote('点击重新生成以获取配对二维码。'),
    if (state.message != null) StateNote(state.message!),
    if (hasQr) ...[
      const SizedBox(height: DesignTokens.spacingXl),
      Text(
        '在手机的无线调试中选择“使用二维码配对设备”，扫描此二维码。',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
    ],
    if (paired != null && paired.deviceId != null && !paired.connected)
      TextButton(
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
        child: const Text('修改连接信息'),
      ),
    if (!embedded)
      FilledButton(
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
        child: const Text('使用配对码'),
      ),
  ];
  final primary = FilledButton(
    onPressed: state.busy ? null : generate,
    child: const Text('重新生成'),
  );
  return (
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
    primary: primary,
  );
}
