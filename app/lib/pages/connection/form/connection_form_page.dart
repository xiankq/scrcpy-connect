import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/pages/connection/form/widgets/connection_ambient_loading.dart';

import 'widgets/connection_mode_selector.dart';
import 'widgets/connection_address_fields.dart';

import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/pages/connection/wireless/qr/connection_wireless_qr_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/services/connection/connection_validation.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

export 'widgets/connection_mode_selector.dart' show AddDeviceMode;
export 'widgets/connection_failure_note.dart' show ConnectionFailureNote;

class ConnectionFormPage extends HookWidget {
  const ConnectionFormPage({
    super.key,
    required this.controller,
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
  final AppController controller;
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
  Widget build(BuildContext context) {
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
    final checking = useState(false);
    final form = useMemoized(() => GlobalKey<FormState>());
    final busy = useState(false);
    final result = useState<Json?>(null);
    final error = useState<Object?>(null);
    final cancellation = useState<String?>(null);
    final activeAttempt = useRef<String?>(null);
    final pendingCancellation = useRef<String?>(null);
    final uiEpoch = useRef(0);
    final cancelling = useState(false);
    final selectedTransport = useState(transport ?? ConnectionTransport.tcp);
    final effectiveTransport = completingPairing.value || tlsLocked.value
        ? ConnectionTransport.tls
        : selectedTransport.value;
    final pairing =
        mode.value == AddDeviceMode.pairing && !completingPairing.value;
    final activePort = pairing ? pairingPort : portField;
    final legacyTcp = effectiveTransport == ConnectionTransport.tcp;
    useEffect(
      () => () {
        final attempt = activeAttempt.value ?? pendingCancellation.value;
        if (attempt != null) {
          controller.execute(ApplicationCommand.devicesCancel, {
            'attemptId': attempt,
          }).ignore();
        }
      },
      const [],
    );
    Future<bool> cancel() async {
      uiEpoch.value++;
      checking.value = false;
      final attempt = activeAttempt.value ?? pendingCancellation.value;
      activeAttempt.value = null;
      if (attempt == null) return true;
      pendingCancellation.value = attempt;
      cancelling.value = true;
      try {
        await controller.request('devices.cancel', {'attemptId': attempt});
        if (!context.mounted) return false;
        pendingCancellation.value = null;
        busy.value = false;
        error.value = null;
        cancellation.value = result.value?['paired'] == true
            ? '已取消连接，手机上的配对授权已保留。'
            : '已取消本次尝试。';
        await controller.refreshDevices();
        return context.mounted;
      } catch (failure) {
        if (context.mounted) {
          busy.value = false;
          error.value = RequestFailure(
            'result_unknown',
            '取消结果尚未确认，请重新核对。$failure',
          );
        }
        return false;
      } finally {
        if (context.mounted) cancelling.value = false;
      }
    }

    String? targetDeviceId() => host.text.trim() == identityAddress.value
        ? currentDeviceId.value
        : deviceId;

    Future<Json?> prepareConnection() async {
      if (!(form.currentState?.validate() ?? false)) {
        return null;
      }
      if ((configuring || reauthorizing) &&
          !await confirmConnectionChange(
            context,
            '应用连接配置？',
            '将沿用此设备的授权身份并核验目标。当前连接及活动可能中断；验证成功后才更新原设备记录。',
            action: '应用并连接',
          )) {
        return null;
      }
      if (!context.mounted) return null;
      return <String, dynamic>{};
    }

    Future<void> submit() async {
      if (busy.value || cancelling.value || pendingCancellation.value != null) {
        return;
      }
      final identity = await prepareConnection();
      if (identity == null || !context.mounted || busy.value) return;
      final attempt =
          '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(form)}';
      uiEpoch.value++;
      activeAttempt.value = attempt;
      busy.value = true;
      attemptPage.value = true;
      error.value = null;
      result.value = null;
      cancellation.value = null;
      try {
        final targetId = targetDeviceId();
        final pairingCode = code.text.trim();
        if (pairing) code.clear();
        final response = await controller.request(
          pairing
              ? 'devices.pair'
              : configuring || reauthorizing
              ? 'devices.configure'
              : 'devices.add',
          {
            ...identity,
            'address': host.text.trim(),
            'attemptId': attempt,
            'deviceId': ?targetId,
            'port': int.parse(activePort.text.trim()),
            if (pairing) 'code': pairingCode,
            if (!pairing) 'transport': effectiveTransport.name,
          },
        );
        if (!context.mounted || activeAttempt.value != attempt) return;
        result.value = response;
        if (configuring || reauthorizing) {
          if (responseDeviceId(response) != targetId ||
              (!pairing && response['connected'] != true)) {
            throw const RequestFailure(
              'configuration_unverified',
              '尚未核验原设备的连接配置，请重新检查。',
            );
          }
        }
        final connectionFailure = response['connectionFailure'];
        if (connectionFailure is Map<Object?, Object?>) {
          final failure = jsonObject(connectionFailure);
          final failureCode = value(failure, 'code', 'connection_failed');
          if (failureCode.contains('unknown') ||
              failureCode.contains('unconfirmed') ||
              failureCode == 'configuration_unverified') {
            pendingCancellation.value = attempt;
          }
          error.value = RequestFailure(
            failureCode,
            value(failure, 'message', '配对已完成，连接尚未建立。'),
          );
        }
        currentDeviceId.value = responseDeviceId(response, targetId);
        identityAddress.value = host.text.trim();
        if (pairing) {
          tlsLocked.value = true;
          selectedTransport.value = ConnectionTransport.tls;
          portField.clear();
        }
        if (!pairing && !configuring && !reauthorizing) {
          final device = response['device'] is Map<Object?, Object?>
              ? jsonObject(response['device'])
              : response;
          final id = device['id'] ?? response['deviceId'];
          if (id != null && device['status'] != 'connected') {
            await controller.execute(ApplicationCommand.devicesConnect, {
              'deviceId': id,
              'attemptId': attempt,
            });
          }
        }
        await controller.refreshDevices();
        if (!context.mounted ||
            activeAttempt.value != attempt ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        final id =
            response['deviceId'] ??
            response['id'] ??
            (response['device'] is Map<Object?, Object?>
                ? response['device']['id']
                : null);
        final matches = controller.snapshot().devices.where(
          (d) => d['id'] == id,
        );
        if (matches.isNotEmpty && matches.first['status'] == 'connected') {
          WorkspaceRoute(deviceId: value(matches.first, 'id'))
              .pushReplacement(context);
        }
      } catch (e) {
        if (context.mounted && activeAttempt.value == attempt) {
          error.value = e;
          if (e is RequestFailure &&
              (e.code.contains('unknown') ||
                  e.code.contains('unconfirmed') ||
                  e.code == 'configuration_unverified')) {
            pendingCancellation.value = attempt;
          }
          if (e is RequestFailure && e.details is Map) {
            final known = (e.details as Map)['result'];
            if (known is Map<Object?, Object?>) {
              result.value = jsonObject(known);
              currentDeviceId.value = responseDeviceId(
                result.value,
                currentDeviceId.value,
              );
            }
          }
        }
      } finally {
        if (context.mounted && activeAttempt.value == attempt) {
          busy.value = false;
          activeAttempt.value = null;
        }
      }
    }

    void selectMode(AddDeviceMode next) {
      uiEpoch.value++;
      checking.value = false;
      final attempt = activeAttempt.value;
      activeAttempt.value = null;
      if (attempt != null) {
        controller.execute(ApplicationCommand.devicesCancel, {
          'attemptId': attempt,
        }).ignore();
      }
      busy.value = false;
      cancelling.value = false;
      error.value = null;
      cancellation.value = null;
      attemptPage.value = false;
      mode.value = next;
    }

    void completePairing(String address, String? id) {
      uiEpoch.value++;
      checking.value = false;
      host.text = address;
      currentDeviceId.value = id ?? currentDeviceId.value;
      identityAddress.value = address.trim();
      tlsLocked.value = true;
      completingPairing.value = true;
      selectedTransport.value = ConnectionTransport.tls;
      portField.clear();
      result.value = null;
      error.value = null;
      cancellation.value = null;
      mode.value = AddDeviceMode.pairing;
      attemptPage.value = false;
    }

    Future<void> closeAttempt() async {
      final cancelled = await cancel();
      if (!context.mounted || !cancelled) return;
      if (pairing && result.value != null) {
        completePairing(
          host.text,
          responseDeviceId(result.value, currentDeviceId.value),
        );
      } else {
        attemptPage.value = false;
      }
    }

    Future<void> recheck() async {
      if (checking.value) return;
      checking.value = true;
      final epoch = uiEpoch.value;
      try {
        await controller.request('state.reconcile');
        await controller.refreshDevices();
        if (!context.mounted ||
            epoch != uiEpoch.value ||
            !attemptPage.value ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        final id = responseDeviceId(result.value, currentDeviceId.value);
        final matches = controller.snapshot().devices.where(
          (device) => device['id'] == id,
        );
        if (id != null &&
            matches.isNotEmpty &&
            matches.first['status'] == 'connected') {
          WorkspaceRoute(deviceId: id).pushReplacement(context);
        }
      } catch (failure) {
        if (context.mounted && epoch == uiEpoch.value) error.value = failure;
      } finally {
        if (context.mounted && epoch == uiEpoch.value) checking.value = false;
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
                                        onTap: busy.value
                                            ? null
                                            : () async {
                                                final previousMode = mode.value;
                                                if (mode.value ==
                                                        AddDeviceMode.qr ||
                                                    mode.value ==
                                                        AddDeviceMode.usb) {
                                                  selectMode(
                                                    AddDeviceMode.pairing,
                                                  );
                                                }
                                                final selection =
                                                    await const DiscoveryRoute(
                                                      selection: true,
                                                    ).push<Json>(context);
                                                if (!context.mounted) return;
                                                if (selection == null) {
                                                  selectMode(previousMode);
                                                  return;
                                                }
                                                final service =
                                                    selection['service'];
                                                if (service
                                                    is! Map<Object?, Object?>) {
                                                  selectMode(
                                                    switch (selection['mode']) {
                                                      'usb' =>
                                                        AddDeviceMode.usb,
                                                      'pairing' =>
                                                        AddDeviceMode.pairing,
                                                      _ => AddDeviceMode.ip,
                                                    },
                                                  );
                                                  return;
                                                }
                                                result.value = null;
                                                error.value = null;
                                                final device = jsonObject(
                                                  service,
                                                );
                                                final endpoints = objects(
                                                  device['endpoints'],
                                                );
                                                final endpoint =
                                                    endpoints.isEmpty
                                                    ? device
                                                    : endpoints.first;
                                                final isPairing =
                                                    device['kind'] == 'pairing';
                                                selectMode(
                                                  isPairing
                                                      ? AddDeviceMode.pairing
                                                      : AddDeviceMode.ip,
                                                );
                                                completingPairing.value = false;
                                                host.text = value(
                                                  endpoint,
                                                  'address',
                                                );
                                                if (isPairing) {
                                                  portField.clear();
                                                }
                                                (isPairing
                                                        ? pairingPort
                                                        : portField)
                                                    .text = value(
                                                  endpoint,
                                                  'port',
                                                );
                                                currentDeviceId.value =
                                                    deviceId ??
                                                    responseDeviceId(device);
                                                identityAddress.value = host
                                                    .text
                                                    .trim();
                                                tlsLocked.value =
                                                    transport ==
                                                        ConnectionTransport
                                                            .tls ||
                                                    device['kind'] != 'tcp';
                                                selectedTransport.value =
                                                    device['kind'] == 'tcp'
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
                                    QrPairPage(
                                      autoGenerate:
                                          !configuring && !reauthorizing,
                                      prepareConnection: prepareConnection,
                                      controller: controller,
                                      deviceId: targetDeviceId(),
                                      embedded: true,
                                      onUsePairingCode: () =>
                                          selectMode(AddDeviceMode.pairing),
                                      onConnectionPort: completePairing,
                                      onPaired: (paired) {
                                        final device = paired['device'];
                                        final record =
                                            device is Map<Object?, Object?>
                                            ? jsonObject(device)
                                            : <String, dynamic>{};
                                        host.text = value(
                                          paired,
                                          'address',
                                          value(record, 'address', host.text),
                                        );
                                        identityAddress.value = host.text
                                            .trim();
                                        currentDeviceId.value =
                                            responseDeviceId(
                                              paired,
                                              currentDeviceId.value,
                                            );
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
                                      enabled: !busy.value,
                                      onAddressChanged: (next) {
                                        if (next.trim() !=
                                            identityAddress.value) {
                                          result.value = null;
                                          error.value = null;
                                        }
                                      },
                                    ),
                                    if (cancellation.value != null)
                                      StateNote(cancellation.value!),
                                    const SizedBox(
                                      height: DesignTokens.spacingSectionTitle,
                                    ),
                                    FilledButton(
                                      onPressed: busy.value ? null : submit,
                                      child: busy.value
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
                              UsbGuidePage(
                                prepareConnection: prepareConnection,
                                controller: controller,
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
              child: ConnectionAmbientLoading(
                busy: busy.value,
                checking: checking.value,
                cancelling: cancelling.value,
                failure: error.value,
                paired:
                    result.value?['paired'] == true ||
                    (pairing && result.value != null),
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
                onRecheck: recheck,
                onConnectionPort: () => completePairing(
                  host.text,
                  responseDeviceId(result.value, currentDeviceId.value),
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
