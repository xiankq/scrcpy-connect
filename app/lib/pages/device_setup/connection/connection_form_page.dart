import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
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
      FocusScope.of(context).unfocus();
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
      mode.value = AddDeviceMode.ip;
      attemptPage.value = false;
    }

    Future<void> closeAttempt() async {
      if (!await actions.cancel() || !context.mounted || !ownsScope()) return;
      attemptPage.value = false;
    }

    Widget page({Widget? supplemental, Widget? primary}) => PopScope(
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
              bottomGlass: false,
              bottom: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingXs,
                ),
                child: FilledButtonTheme(
                  data: FilledButtonThemeData(
                    style: FilledButtonTheme.of(context).style?.copyWith(
                      minimumSize: const WidgetStatePropertyAll(
                        Size.fromHeight(
                          DesignTokens.componentButtonPrimaryHeight,
                        ),
                      ),
                      shape: const WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(
                              DesignTokens.componentButtonPrimaryRounded,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child:
                      primary ??
                      (mode.value == .pairing || mode.value == .ip
                          ? FilledButton(
                              onPressed: flow.busy ? null : submit,
                              child: Text(pairing ? '配对并连接' : '连接设备'),
                            )
                          : const SizedBox.shrink()),
                ),
              ),
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
                                      child: ListTile(
                                        minTileHeight: DesignTokens
                                            .componentConnectionNearbyEntryHeight,
                                        leading: const Icon(
                                          AppIcons.connectionDiscovery,
                                          color: DesignTokens
                                              .componentConnectionIconNearbyTextColor,
                                        ),
                                        title: const Text('附近设备'),
                                        trailing: const Icon(
                                          AppIcons.forward,
                                          size: DesignTokens
                                              .componentIconSmallSize,
                                        ),
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
                                  if (mode.value == .pairing ||
                                      mode.value == .ip) ...[
                                    ConnectionAddressFields(
                                      address: host,
                                      port: activePort,
                                      pairingCode: code,
                                      pairing: pairing,
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
                                  ],
                                ],
                              ),
                            ),
                            ?supplemental,
                            SliverToBoxAdapter(
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(44, 44),
                                  ),
                                  onPressed: () =>
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              _ConnectionHelpPage(
                                                mode: mode.value,
                                                legacyTcp: legacyTcp,
                                              ),
                                        ),
                                      ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(switch (mode.value) {
                                          .pairing => '配对码帮助',
                                          .qr => '扫码帮助',
                                          .usb => 'USB 连接帮助',
                                          .ip => 'IP 连接帮助',
                                        }),
                                      ),
                                      const Icon(
                                        AppIcons.forward,
                                        size:
                                            DesignTokens.componentIconSmallSize,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (additionalContent != null)
                              SliverToBoxAdapter(child: additionalContent!),
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
                pairing: pairing,
                legacyTcp: legacyTcp,
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
              ),
            ),
        ],
      ),
    );

    return switch (mode.value) {
      .qr => QrPairingPage(
        autoGenerate: !configuring && !reauthorizing,
        prepareConnection: prepareConnection,
        deviceId: deviceId,
        embedded: true,
        onUsePairingCode: () => selectMode(.pairing),
        onConnectionPort: completePairing,
        onPaired: (paired) {
          host.text = paired.address;
          identityAddress.value = host.text.trim();
          currentDeviceId.value = paired.deviceId ?? currentDeviceId.value;
          tlsLocked.value = true;
          selectedTransport.value = ConnectionTransport.tls;
          portField.clear();
        },
        embeddedBuilder: (body, primary) => page(
          supplemental: SliverToBoxAdapter(child: body),
          primary: primary,
        ),
      ),
      .usb => UsbSetupPage(
        prepareConnection: prepareConnection,
        deviceId: targetDeviceId(),
        embedded: true,
        onUseWireless: () => selectMode(.pairing),
        embeddedBuilder: (body, primary) =>
            page(supplemental: body, primary: primary),
      ),
      _ => page(),
    };
  }
}

class _ConnectionHelpPage extends StatelessWidget {
  const _ConnectionHelpPage({required this.mode, required this.legacyTcp});
  final AddDeviceMode mode;
  final bool legacyTcp;

  @override
  Widget build(BuildContext context) {
    final (title, instructions) = switch (mode) {
      .pairing => (
        '配对码连接帮助',
        [
          '在手机上开启开发者选项和无线调试。',
          '选择“使用配对码配对设备”。在邻接填写配对窗口中的地址、端口和六位配对码。',
          '保持两台设备在同一可达网络，直到连接完成。',
        ],
      ),
      .qr => (
        '扫码连接帮助',
        [
          '在手机上打开开发者选项里的无线调试。',
          '选择“使用二维码配对设备”，扫描邻接显示的二维码。',
          '保持无线调试页面打开，直到设备出现在工作台。',
        ],
      ),
      .usb => (
        'USB 连接帮助',
        [
          '请使用支持数据传输的 USB 数据线连接两台设备。',
          '打开被控手机的开发者选项和 USB 调试。',
          '允许本机访问 USB 设备，并在被控手机上确认调试授权。',
        ],
      ),
      .ip => (
        'IP 连接帮助',
        [
          legacyTcp ? '先用 USB 完成调试授权，并在设备设置中开启 IP 连接。' : '在手机开发者选项中打开无线调试。',
          '填写手机连接地址和当前连接端口。',
          '保持网络可达。未加密的 IP 调试只适用于可信网络。',
        ],
      ),
    };
    return PageFrame(
      title: title,
      onBack: () => Navigator.pop(context),
      child: Builder(
        builder: (context) => ListView(
          padding:
              const EdgeInsets.all(DesignTokens.spacingMd) +
              PageChromePadding.of(context),
          children: [
            for (final (index, instruction) in instructions.indexed)
              ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(instruction),
              ),
          ],
        ),
      ),
    );
  }
}
