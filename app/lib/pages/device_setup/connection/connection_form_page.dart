import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/connection_attempt_notifier.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/models/connection_attempt_request.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_address_fields.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_attempt_status.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_mode_selector.dart';
import 'package:scrcpy_connect/pages/device_setup/pairing/qr_pairing_page.dart';
import 'package:scrcpy_connect/pages/device_setup/usb/usb_setup_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

export 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_failure_note.dart'
    show ConnectionFailureNote;
export 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_mode_selector.dart'
    show AddDeviceMode;

class ConnectionFormPage extends HookConsumerWidget {
  const ConnectionFormPage({
    super.key,
    this.pairing = false,
    this.address = '',
    this.port = '',
    this.deviceId,
    this.transport,
    this.initialMode,
    this.reauthorizing = false,
    this.configuring = false,
    this.additionalContent,
  });
  final bool pairing;
  final String address;
  final String port;
  final String? deviceId;
  final ConnectionTransport? transport;
  final AddDeviceMode? initialMode;
  final bool reauthorizing;
  final bool configuring;
  final Widget? additionalContent;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceManagement = ref.watch(deviceManagementProvider);
    final setup = ref.watch(deviceSetupProvider);
    final connections = ref.watch(deviceConnectionsProvider);
    final mode = useState(
      initialMode ?? (this.pairing ? AddDeviceMode.pairing : AddDeviceMode.ip),
    );
    final completingPairing = useState(false);
    final currentDeviceId = useState(deviceId);
    final identityAddress = useRef(address.trim());
    final tlsLocked = useState(transport == ConnectionTransport.tls);
    final host = useTextEditingController(text: address);
    useListenable(host);
    final pairingPort = useTextEditingController(
      text: this.pairing ? port : '',
    );
    final portField = useTextEditingController(
      text: !this.pairing && port.isNotEmpty
          ? port
          : transport != ConnectionTransport.tls
          ? '5555'
          : '',
    );
    final code = useTextEditingController();
    final attemptPage = useState(false);
    final form = useMemoized(() => GlobalKey<FormState>());
    final scope = useMemoized(Object.new, [
      deviceId,
      configuring,
      reauthorizing,
    ]);
    final viewScope = useRef(scope)..value = scope;
    final provider = connectionAttemptProvider(scope: scope);
    final flow = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    final selectedTransport = useState(transport ?? ConnectionTransport.tcp);
    final effectiveTransport = completingPairing.value || tlsLocked.value
        ? ConnectionTransport.tls
        : selectedTransport.value;
    final pairing =
        mode.value == AddDeviceMode.pairing && !completingPairing.value;
    final activePort = pairing ? pairingPort : portField;
    final legacyTcp = effectiveTransport == ConnectionTransport.tcp;
    bool ownsScope() =>
        context.mounted &&
        identical(viewScope.value, scope) &&
        identical(setup, ref.read(deviceSetupProvider)) &&
        identical(connections, ref.read(deviceConnectionsProvider)) &&
        identical(deviceManagement, ref.read(deviceManagementProvider));
    useEffect(() {
      Future.microtask(() {
        if (ownsScope()) attemptPage.value = false;
      });
      return null;
    }, [scope, setup, connections, deviceManagement]);
    ref.listen(provider, (previous, next) {
      if (!ownsScope()) return;
      if (next.deviceId != null && next.address != null) {
        currentDeviceId.value = next.deviceId;
        identityAddress.value = next.address!;
      }
      if (next.pairing != null && next.pairing != previous?.pairing) {
        tlsLocked.value = true;
        selectedTransport.value = ConnectionTransport.tls;
        portField.clear();
      }
      final connected = next.connectedDeviceId;
      if (connected != null &&
          connected != previous?.connectedDeviceId &&
          attemptPage.value &&
          ModalRoute.of(context)?.isCurrent != false) {
        WorkspaceRoute(deviceId: connected).pushReplacement(context);
      }
    });

    String? targetDeviceId() => host.text.trim() == identityAddress.value
        ? currentDeviceId.value
        : deviceId;

    Future<bool> prepareConnection() async {
      if (!(form.currentState?.validate() ?? false)) {
        return false;
      }
      if ((configuring || reauthorizing) &&
          !await confirmConnectionChange(
            context,
            '应用连接配置？',
            '将沿用此设备的授权身份并核验目标。当前连接及活动可能中断；验证成功后才更新原设备记录。',
            action: '应用并连接',
          )) {
        return false;
      }
      if (!context.mounted) return false;
      return true;
    }

    Future<void> submit() async {
      if (!flow.canSubmit) return;
      if (!await prepareConnection() ||
          !context.mounted ||
          !ownsScope() ||
          !ref.read(provider).canSubmit) {
        return;
      }
      final request = pairing
          ? ConnectionAttemptRequest.pair(
              address: host.text.trim(),
              port: int.parse(activePort.text.trim()),
              code: code.text.trim(),
              deviceId: targetDeviceId(),
            )
          : ConnectionAttemptRequest.connect(
              endpoint: DeviceEndpoint(
                address: host.text.trim(),
                port: int.parse(activePort.text.trim()),
                transport: effectiveTransport == ConnectionTransport.tls
                    ? .tls
                    : .tcp,
              ),
              deviceId: targetDeviceId(),
              configure: configuring || reauthorizing,
            );
      if (pairing) code.clear();
      attemptPage.value = true;
      await actions.submit(request);
    }

    Future<bool> selectMode(AddDeviceMode next) async {
      final reset = await actions.reset();
      if (!context.mounted || !ownsScope()) return false;
      if (!reset) {
        attemptPage.value = true;
        return false;
      }
      attemptPage.value = false;
      mode.value = next;
      return true;
    }

    Future<void> completePairing(String address, String? id) async {
      if (!await actions.reset() || !context.mounted || !ownsScope()) return;
      host.text = address;
      currentDeviceId.value = id ?? currentDeviceId.value;
      identityAddress.value = address.trim();
      tlsLocked.value = true;
      completingPairing.value = true;
      selectedTransport.value = ConnectionTransport.tls;
      portField.clear();
      mode.value = AddDeviceMode.pairing;
      attemptPage.value = false;
    }

    Future<void> closeAttempt() async {
      if (!await actions.cancel() || !context.mounted || !ownsScope()) return;
      final receipt = ref.read(provider).pairing;
      if (pairing && receipt != null) {
        await completePairing(
          host.text,
          receipt.deviceId ?? currentDeviceId.value,
        );
      } else {
        attemptPage.value = false;
      }
    }

    return PopScope(
      canPop: !attemptPage.value,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !attemptPage.value) return;
        await closeAttempt();
      },
      child: Stack(
        children: [
          Offstage(
            offstage: attemptPage.value,
            child: PageFrame(
              title: configuring
                  ? '连接配置'
                  : reauthorizing
                  ? '重新授权'
                  : '添加设备',
              child: ConnectionContent(
                child: Form(
                  key: form,
                  child: CustomScrollView(
                    slivers: [
                      const PageChromeSliver(),
                      SliverPadding(
                        padding: const EdgeInsets.all(DesignTokens.spacingMd),
                        sliver: SliverMainAxisGroup(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!configuring) ...[
                                    ContentPanel(
                                      padding: EdgeInsets.zero,
                                      child: ActionRow(
                                        icon: LucideIcons.radar,
                                        title: '发现设备',
                                        onTap: flow.busy
                                            ? null
                                            : () async {
                                                final previousMode = mode.value;
                                                if (mode.value ==
                                                        AddDeviceMode.qr ||
                                                    mode.value ==
                                                        AddDeviceMode.usb) {
                                                  if (!await selectMode(
                                                    AddDeviceMode.pairing,
                                                  )) {
                                                    return;
                                                  }
                                                }
                                                if (!context.mounted) return;
                                                final selection =
                                                    await const DiscoveryRoute(
                                                      selection: true,
                                                    ).push<DiscoveredDevice>(
                                                      context,
                                                    );
                                                if (!context.mounted ||
                                                    !ownsScope()) {
                                                  return;
                                                }
                                                if (selection == null) {
                                                  await selectMode(
                                                    previousMode,
                                                  );
                                                  return;
                                                }
                                                actions.clearFeedback();
                                                final device = selection;
                                                final endpoint = device
                                                    .endpoints
                                                    .firstOrNull;
                                                final isPairing =
                                                    device.kind == .pairing;
                                                if (!await selectMode(
                                                  isPairing
                                                      ? AddDeviceMode.pairing
                                                      : AddDeviceMode.ip,
                                                )) {
                                                  return;
                                                }
                                                if (!context.mounted ||
                                                    !ownsScope()) {
                                                  return;
                                                }
                                                completingPairing.value = false;
                                                host.text =
                                                    endpoint?.address ?? '';
                                                if (isPairing) {
                                                  portField.clear();
                                                }
                                                (isPairing
                                                            ? pairingPort
                                                            : portField)
                                                        .text =
                                                    endpoint?.port.toString() ??
                                                    '';
                                                currentDeviceId.value =
                                                    deviceId ?? device.deviceId;
                                                identityAddress.value = host
                                                    .text
                                                    .trim();
                                                tlsLocked.value =
                                                    transport ==
                                                        ConnectionTransport
                                                            .tls ||
                                                    device.kind != .tcp;
                                                selectedTransport.value =
                                                    device.kind == .tcp
                                                    ? ConnectionTransport.tcp
                                                    : ConnectionTransport.tls;
                                              },
                                      ),
                                    ),
                                    const SizedBox(
                                      height: DesignTokens.spacingMd,
                                    ),
                                  ],
                                  if (!configuring) ...[
                                    ConnectionModeSelector(
                                      selected: mode.value,
                                      onChanged: selectMode,
                                    ),
                                    const SizedBox(
                                      height: DesignTokens.spacingMd,
                                    ),
                                  ],
                                  if (mode.value == AddDeviceMode.qr)
                                    QrPairingPage(
                                      autoGenerate:
                                          !configuring && !reauthorizing,
                                      prepareConnection: prepareConnection,
                                      deviceId: deviceId,
                                      embedded: true,
                                      onUsePairingCode: () =>
                                          selectMode(AddDeviceMode.pairing),
                                      onConnectionPort: completePairing,
                                      onPaired: (paired) {
                                        host.text = paired.address;
                                        identityAddress.value = host.text
                                            .trim();
                                        currentDeviceId.value =
                                            paired.deviceId ??
                                            currentDeviceId.value;
                                        tlsLocked.value = true;
                                        selectedTransport.value =
                                            ConnectionTransport.tls;
                                        portField.clear();
                                      },
                                    )
                                  else if (mode.value != AddDeviceMode.usb) ...[
                                    ConnectionAddressFields(
                                      address: host,
                                      port: activePort,
                                      pairingCode: code,
                                      pairing: pairing,
                                      completingPairing:
                                          completingPairing.value,
                                      legacyTcp: legacyTcp,
                                      enabled: !flow.busy,
                                      onAddressChanged: (next) {
                                        if (next.trim() !=
                                            identityAddress.value) {
                                          actions.clearFeedback();
                                        }
                                      },
                                    ),
                                    if (flow.notice != null)
                                      StateNote(flow.notice!),
                                    const SizedBox(
                                      height: DesignTokens.spacingSectionTitle,
                                    ),
                                    FilledButton(
                                      onPressed: flow.busy ? null : submit,
                                      child: flow.busy
                                          ? const SizedBox(
                                              width: DesignTokens.spacingMd,
                                              height: DesignTokens.spacingMd,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(pairing ? '配对并连接' : '连接设备'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (mode.value == AddDeviceMode.usb)
                              UsbSetupPage(
                                prepareConnection: prepareConnection,
                                deviceId: targetDeviceId(),
                                embedded: true,
                                onUseWireless: () =>
                                    selectMode(AddDeviceMode.pairing),
                              ),
                            if (additionalContent != null)
                              SliverToBoxAdapter(child: additionalContent!),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: DesignTokens.spacingMd),
                            ),
                            SliverToBoxAdapter(
                              child: TextButton(
                                onPressed: () => showGlassDialog<void>(
                                  context: context,
                                  builder: (dialogContext) => GlassAlertDialog(
                                    title: Text(
                                      '连接帮助',
                                      style: Theme.of(dialogContext)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    content: Text(
                                      _connectionHelp(
                                        mode.value,
                                        legacyTcp: legacyTcp,
                                      ),
                                      style: Theme.of(dialogContext)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(),
                                        child: const Text('知道了'),
                                      ),
                                    ],
                                  ),
                                ),
                                child: const Text('连接帮助'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PageChromeBottomSliver(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (attemptPage.value)
            Positioned.fill(
              child: ConnectionAttemptStatus(
                busy: flow.busy,
                checking: flow.checking,
                cancelling: flow.cancelling,
                failure: flow.failure,
                paired:
                    flow.pairing?.recorded == true ||
                    (pairing && flow.pairing != null),
                deviceName: host.text.trim(),
                onCancel: closeAttempt,
                onEdit: closeAttempt,
                onRetry: () {
                  if (pairing && code.text.isEmpty) {
                    attemptPage.value = false;
                    form.currentState?.validate();
                  } else {
                    submit();
                  }
                },
                onRecheck: actions.recheck,
                onConnectionPort: () => completePairing(
                  host.text,
                  (flow.pairing?.deviceId ?? currentDeviceId.value),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _connectionHelp(AddDeviceMode mode, {required bool legacyTcp}) =>
    switch (mode) {
      AddDeviceMode.usb => '使用数据线连接，本机需支持 USB 主机角色。\n\n本机：允许应用访问 USB 设备。手机：开启 USB 调试，在系统弹窗中允许此主控。\n\n“检查连接”只读取实际授权结果。拒绝或超时后，重新插线并检查授权。本机无需开启调试。',
      AddDeviceMode.ip when legacyTcp => '先通过 USB 完成手机的调试授权，并允许按地址连接。填写手机当前的地址和连接端口。\n\n此方式不使用无线调试加密，仅在可信网络使用。跨网需已有 VPN 等可达路径，不会自动穿透网络。',
      _ => '手机：在“设置 → 关于手机”连续点击版本号，开启开发者选项，再打开无线调试。\n\n配对码：填写配对窗口的地址、配对端口和当前配对码。扫码：在手机选择“使用二维码配对设备”，扫描本机二维码。\n\n连接端口在无线调试主页面，与配对端口不同。已配对但未连接时，填写连接端口，无需重复配对。\n\n手机没有无线调试时，改用 USB 授权。本机无需开启调试。跨网需已有 VPN 等可达路径，不会自动穿透网络。',
    };
