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
    this.embedded = false,
    this.onUsePairingCode,
    this.onConnectionPort,
    this.onPaired,
    this.prepareConnection,
    this.autoGenerate = true,
  });
  final String? deviceId;
  final bool embedded;
  final bool autoGenerate;
  final Future<bool> Function()? prepareConnection;
  final VoidCallback? onUsePairingCode;
  final ValueChanged<PairingReceipt>? onPaired;
  final void Function(String address, String? deviceId)? onConnectionPort;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceManagement = ref.watch(deviceManagementProvider);
    final setup = ref.watch(deviceSetupProvider);
    final scope = useMemoized(Object.new, [deviceId]);
    final viewScope = useRef(scope)..value = scope;
    final provider = qrPairingProvider(deviceId: deviceId, scope: scope);
    final state = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    bool ownsView() =>
        context.mounted &&
        identical(viewScope.value, scope) &&
        identical(setup, ref.read(deviceSetupProvider)) &&
        identical(deviceManagement, ref.read(deviceManagementProvider));
    ref.listen(provider.select((state) => state.receipt), (_, paired) {
      if (paired != null) onPaired?.call(paired);
    });

    Future<void> generate() async {
      if (state.busy) return;
      final allowed = await prepareConnection?.call() ?? true;
      if (!allowed || !ownsView()) return;
      await actions.generate();
    }

    useEffect(() {
      if (autoGenerate) {
        Future.microtask(() {
          if (ownsView()) unawaited(generate());
        });
      }
      return null;
    }, [setup, deviceManagement, deviceId, autoGenerate]);

    final paired = state.receipt;
    final hasQr = state.hasQr;
    final children = <Widget>[
      if (hasQr) ...[
        Text(
          '在手机的无线调试中选择“使用二维码配对设备”，扫描此二维码。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: DesignTokens.spacingLg),
      ],
      if (state.busy) const Center(child: CircularProgressIndicator()),
      if (hasQr)
        Center(
          child: Container(
            color: Colors.white,
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
      if (paired != null && paired.deviceId != null)
        FilledButton(
          onPressed: () {
            if (paired.connected) {
              WorkspaceRoute(deviceId: paired.deviceId!)
                  .pushReplacement(context);
            } else if (onConnectionPort != null) {
              onConnectionPort!(paired.address, paired.deviceId);
            } else {
              ConnectionFormRoute(
                transport: ConnectionTransport.tls,
                deviceId: paired.deviceId,
                address: paired.address,
              ).pushReplacement(context);
            }
          },
          child: Text(paired.connected ? '打开设备工作台' : '填写连接端口'),
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
                    onUsePairingCode!();
                    return;
                  }
                  ConnectionFormRoute(
                    pairing: true,
                    deviceId: ref.read(provider).receipt?.deviceId,
                  ).pushReplacement(context);
                },
          child: const Text('使用配对码'),
        ),
      const SizedBox(height: DesignTokens.spacingSectionTitle),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: state.busy ? null : generate,
          child: const Text('重新生成'),
        ),
      ),
    ];
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return PageFrame(
      title: '添加设备',
      child: ConnectionContent(
        child: GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: children,
        ),
      ),
    );
  }
}
