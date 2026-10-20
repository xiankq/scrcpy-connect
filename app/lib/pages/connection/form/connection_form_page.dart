import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/pages/connection/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/pages/connection/wireless/qr/connection_wireless_qr_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum AddDeviceMode { pairing, qr, usb, ip }

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
  });
  final AppController controller;
  final bool pairing;
  final String address;
  final String port;
  final String? deviceId;
  final ConnectionTransport? transport;
  final AddDeviceMode? initialMode;
  final bool reauthorizing;
  @override
  Widget build(BuildContext context) {
    final mode = useState(
      initialMode ?? (this.pairing ? AddDeviceMode.pairing : AddDeviceMode.ip),
    );
    final modeKeys = useMemoized(
      () => {for (final mode in AddDeviceMode.values) mode: GlobalKey()},
    );
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final selected = modeKeys[mode.value]?.currentContext;
        if (selected != null) Scrollable.ensureVisible(selected, alignment: .5);
      });
      return null;
    }, [mode.value]);
    final completingPairing = useState(false);
    final currentDeviceId = useState(deviceId);
    final identityAddress = useRef(address.trim());
    final tlsLocked = useState(transport == ConnectionTransport.tls);
    final host = useTextEditingController(text: address);
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
    final form = useMemoized(() => GlobalKey<FormState>());
    final busy = useState(false);
    final result = useState<Json?>(null);
    final error = useState<Object?>(null);
    final activeAttempt = useRef<String?>(null);
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
        final attempt = activeAttempt.value;
        if (attempt != null) {
          controller.execute(InteropCommand.devicesCancel, {
            'attemptId': attempt,
          }).ignore();
        }
      },
      const [],
    );
    Future<void> cancel() async {
      final attempt = activeAttempt.value;
      if (attempt == null) return;
      cancelling.value = true;
      final cancelled = await perform(context, controller, 'devices.cancel', {
        'attemptId': attempt,
      });
      if (!context.mounted) return;
      cancelling.value = false;
      if (cancelled != null && activeAttempt.value == attempt) {
        activeAttempt.value = null;
        busy.value = false;
        error.value = '本次尝试已取消。已建立的配对信任会保留。';
        await controller.refreshDevices();
      }
    }

    Future<void> submit() async {
      if (!form.currentState!.validate()) return;
      final attempt =
          '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(form)}';
      activeAttempt.value = attempt;
      busy.value = true;
      error.value = null;
      try {
        final targetDeviceId = host.text.trim() == identityAddress.value
            ? currentDeviceId.value
            : deviceId;
        final pairingCode = code.text.trim();
        if (pairing) code.clear();
        final response = await controller.request(
          pairing ? 'devices.pair' : 'devices.add',
          {
            'address': host.text.trim(),
            'attemptId': attempt,
            'deviceId': ?targetDeviceId,
            'port': int.parse(activePort.text.trim()),
            if (pairing) 'code': pairingCode,
            if (!pairing) 'transport': effectiveTransport.name,
          },
        );
        if (!context.mounted || activeAttempt.value != attempt) return;
        result.value = response;
        currentDeviceId.value = responseDeviceId(response, targetDeviceId);
        identityAddress.value = host.text.trim();
        if (pairing) {
          tlsLocked.value = true;
          selectedTransport.value = ConnectionTransport.tls;
          portField.clear();
        }
        if (!pairing) {
          final device = response['device'] is Map<Object?, Object?>
              ? jsonObject(response['device'])
              : response;
          final id = device['id'] ?? response['deviceId'];
          if (id != null && device['status'] != 'connected') {
            await controller.execute(InteropCommand.devicesConnect, {
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
        }
      } finally {
        if (context.mounted && activeAttempt.value == attempt) {
          busy.value = false;
          activeAttempt.value = null;
        }
      }
    }

    void selectMode(AddDeviceMode next) {
      final attempt = activeAttempt.value;
      activeAttempt.value = null;
      if (attempt != null) {
        controller.execute(InteropCommand.devicesCancel, {
          'attemptId': attempt,
        }).ignore();
      }
      busy.value = false;
      cancelling.value = false;
      error.value = null;
      mode.value = next;
    }

    void completePairing(String address, String? id) {
      host.text = address;
      currentDeviceId.value = id ?? currentDeviceId.value;
      identityAddress.value = address.trim();
      tlsLocked.value = true;
      completingPairing.value = true;
      selectedTransport.value = ConnectionTransport.tls;
      portField.clear();
      result.value = null;
      error.value = null;
      mode.value = AddDeviceMode.pairing;
    }

    return PageFrame(
      title: reauthorizing ? '重新授权' : '添加设备',
      child: ConnectionContent(
        child: Form(
          key: form,
          child: GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ContentPanel(
                    padding: EdgeInsets.zero,
                    child: ActionRow(
                      icon: LucideIcons.radar,
                      title: '发现设备',
                      onTap: busy.value
                          ? null
                          : () async {
                              final previousMode = mode.value;
                              if (mode.value == AddDeviceMode.qr ||
                                  mode.value == AddDeviceMode.usb) {
                                selectMode(AddDeviceMode.pairing);
                              }
                              final selection = await const DiscoveryRoute(
                                selection: true,
                              ).push<Json>(context);
                              if (!context.mounted) return;
                              if (selection == null) {
                                selectMode(previousMode);
                                return;
                              }
                              final service = selection['service'];
                              if (service is! Map<Object?, Object?>) {
                                selectMode(switch (selection['mode']) {
                                  'usb' => AddDeviceMode.usb,
                                  'pairing' => AddDeviceMode.pairing,
                                  _ => AddDeviceMode.ip,
                                });
                                return;
                              }
                              result.value = null;
                              error.value = null;
                              final device = jsonObject(service);
                              final endpoints = objects(device['endpoints']);
                              final endpoint = endpoints.isEmpty
                                  ? device
                                  : endpoints.first;
                              final isPairing = device['kind'] == 'pairing';
                              selectMode(
                                isPairing
                                    ? AddDeviceMode.pairing
                                    : AddDeviceMode.ip,
                              );
                              completingPairing.value = false;
                              host.text = value(endpoint, 'address');
                              if (isPairing) portField.clear();
                              (isPairing ? pairingPort : portField).text =
                                  value(endpoint, 'port');
                              currentDeviceId.value =
                                  deviceId ?? responseDeviceId(device);
                              identityAddress.value = host.text.trim();
                              tlsLocked.value =
                                  transport == ConnectionTransport.tls ||
                                  device['kind'] != 'tcp';
                              selectedTransport.value = device['kind'] == 'tcp'
                                  ? ConnectionTransport.tcp
                                  : ConnectionTransport.tls;
                            },
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacingLg),
                  ContentPanel(
                    padding: EdgeInsets.zero,
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final entry in const [
                              (
                                AddDeviceMode.pairing,
                                '无线配对码',
                                LucideIcons.keyRound,
                                ConnectTokens.blue,
                              ),
                              (
                                AddDeviceMode.qr,
                                '扫码配对',
                                LucideIcons.qrCode,
                                ConnectTokens.mint,
                              ),
                              (
                                AddDeviceMode.usb,
                                'USB',
                                LucideIcons.usb,
                                ConnectTokens.amber,
                              ),
                              (
                                AddDeviceMode.ip,
                                'IP连接',
                                LucideIcons.network,
                                ConnectTokens.coral,
                              ),
                            ])
                              Semantics(
                                key: modeKeys[entry.$1],
                                label: entry.$2,
                                button: true,
                                selected: mode.value == entry.$1,
                                child: InkWell(
                                  onTap: () => selectMode(entry.$1),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth / 4,
                                      minHeight: DesignTokens
                                          .componentNavigationHeight,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: DesignTokens.spacingXs,
                                        vertical: DesignTokens.spacingTight,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            entry.$3,
                                            size:
                                                DesignTokens.componentIconSize,
                                            color: entry.$4,
                                          ),
                                          const SizedBox(
                                            height: DesignTokens.spacingXxs,
                                          ),
                                          Text(
                                            entry.$2,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  fontSize: DesignTokens
                                                      .typographyCaptionFontSize,
                                                  fontWeight:
                                                      mode.value == entry.$1
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                  color: mode.value == entry.$1
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                ),
                                          ),
                                          const SizedBox(
                                            height: DesignTokens.spacingXxs,
                                          ),
                                          Container(
                                            width:
                                                DesignTokens.componentIconSize,
                                            height:
                                                DesignTokens.spacingHairline *
                                                2,
                                            color: mode.value == entry.$1
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                : Colors.transparent,
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
                  const SizedBox(height: DesignTokens.spacingLg),
                  if (mode.value == AddDeviceMode.qr)
                    QrPairPage(
                      controller: controller,
                      embedded: true,
                      onUsePairingCode: () => selectMode(AddDeviceMode.pairing),
                      onConnectionPort: completePairing,
                      onPaired: (paired) {
                        final device = paired['device'];
                        final record = device is Map<Object?, Object?>
                            ? jsonObject(device)
                            : <String, dynamic>{};
                        host.text = value(
                          paired,
                          'address',
                          value(record, 'address', host.text),
                        );
                        identityAddress.value = host.text.trim();
                        currentDeviceId.value = responseDeviceId(
                          paired,
                          currentDeviceId.value,
                        );
                        tlsLocked.value = true;
                        selectedTransport.value = ConnectionTransport.tls;
                        portField.clear();
                      },
                    )
                  else if (mode.value == AddDeviceMode.usb)
                    UsbGuidePage(
                      controller: controller,
                      embedded: true,
                      onUseWireless: () => selectMode(AddDeviceMode.pairing),
                    )
                  else ...[
                    if (!pairing) ...[
                      Text(
                        legacyTcp
                            ? '先通过 USB 授权并允许按地址连接，仅在可信网络使用。'
                            : '使用手机无线调试主页面的连接端口。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: DesignTokens.spacingMd),
                    ],
                    TextFormField(
                      style: Theme.of(context).textTheme.bodyMedium,
                      controller: host,
                      onChanged: (next) {
                        if (next.trim() != identityAddress.value) {
                          result.value = null;
                          error.value = null;
                        }
                      },
                      validator: validateAddress,
                      enabled: !busy.value,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'IP 地址或主机名',
                        hintText: '192.168.1.8',
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    TextFormField(
                      style: Theme.of(context).textTheme.bodyMedium,
                      controller: activePort,
                      validator: validatePort,
                      enabled: !busy.value,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: pairing ? '配对端口' : '连接端口',
                        helperText: pairing
                            ? '配对窗口中的端口'
                            : legacyTcp
                            ? null
                            : '无线调试主页面中的端口',
                      ),
                    ),
                    if (pairing) ...[
                      const SizedBox(height: DesignTokens.spacingMd),
                      TextFormField(
                        style: Theme.of(context).textTheme.bodyMedium,
                        controller: code,
                        enabled: !busy.value,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        validator: (s) => RegExp(r'^\d{6}$').hasMatch(s ?? '')
                            ? null
                            : '请输入六位配对码',
                        decoration: const InputDecoration(labelText: '配对码'),
                      ),
                    ],
                    if (error.value != null)
                      ConnectionFailureNote(
                        failure: error.value!,
                        pairing: pairing,
                        legacyTcp: legacyTcp,
                      ),
                    const SizedBox(height: DesignTokens.spacingSectionTitle),
                    FilledButton(
                      onPressed: busy.value ? null : submit,
                      child: busy.value
                          ? const SizedBox(
                              width: DesignTokens.spacingMd,
                              height: DesignTokens.spacingMd,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(pairing ? '配对并连接' : '连接设备'),
                    ),
                    if (busy.value)
                      TextButton(
                        onPressed: cancelling.value ? null : cancel,
                        child: Text(cancelling.value ? '正在取消…' : '取消本次尝试'),
                      ),
                    if (result.value != null && pairing)
                      ContentPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已配对，尚未连接',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: DesignTokens.spacingXs),
                            Text(
                              '填写手机无线调试主页面的连接端口。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: DesignTokens.spacingMd),
                            OutlinedButton(
                              onPressed: () => completePairing(
                                host.text,
                                responseDeviceId(
                                  result.value,
                                  currentDeviceId.value,
                                ),
                              ),
                              child: const Text('填写连接端口'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    if (!pairing && !legacyTcp)
                      TextButton(
                        onPressed: () {
                          completingPairing.value = false;
                          selectMode(AddDeviceMode.pairing);
                        },
                        child: Text(
                          _authorizationRejected(error.value)
                              ? '重新配对'
                              : '尚未配对？使用配对码',
                        ),
                      ),
                  ],
                  TextButton(
                    onPressed: () => showGlassDialog<void>(
                      context: context,
                      builder: (dialogContext) => GlassAlertDialog(
                        title: const Text('连接帮助'),
                        content: SingleChildScrollView(
                          child: Text(
                            _connectionHelp(mode.value, legacyTcp: legacyTcp),
                            style: Theme.of(dialogContext).textTheme.bodyMedium,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('连接帮助'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the request failure intact while presenting actionable form feedback.
class ConnectionFailureNote extends StatelessWidget {
  const ConnectionFailureNote({
    super.key,
    required this.failure,
    required this.pairing,
    required this.legacyTcp,
  });

  final Object failure;
  final bool pairing;
  final bool legacyTcp;

  @override
  Widget build(BuildContext context) => StateNote(
    _failureMessage(failure, pairing: pairing, legacyTcp: legacyTcp),
    icon: LucideIcons.circleAlert,
    color: ConnectTokens.danger,
  );
}

bool _authorizationRejected(Object? failure) =>
    failure is RequestFailure &&
    (failure.code == 'authorization_required' ||
        RegExp(
          r'received fatal alert: (CertificateRequired|BadCertificate|CertificateUnknown|UnknownCA)\b',
        ).hasMatch(failure.message));

String _failureMessage(
  Object failure, {
  required bool pairing,
  required bool legacyTcp,
}) {
  if (!pairing && !legacyTcp && _authorizationRejected(failure)) {
    return '手机未授权本机，请重新配对。';
  }
  if (!pairing && failure is RequestFailure && failure.code == 'timeout') {
    return '连接超时，请检查地址、连接端口和网络。';
  }
  if (pairing &&
      failure is RequestFailure &&
      failure.message.toLowerCase().contains('pairing authentication failed')) {
    return '配对失败，请使用手机当前显示的配对端口和配对码。';
  }
  if (pairing &&
      failure is RequestFailure &&
      (failure.code == 'disconnected' ||
          RegExp(
            r'\b(eof|end of file)\b',
            caseSensitive: false,
          ).hasMatch(failure.message))) {
    return '配对中断，请确认手机配对窗口仍开启，然后重试。';
  }
  return '$failure';
}

String _connectionHelp(AddDeviceMode mode, {required bool legacyTcp}) =>
    switch (mode) {
      AddDeviceMode.usb => '使用支持数据传输的数据线，本机需要支持 USB 主机角色。\n\n在本机允许应用访问 USB 设备；在被控手机开启开发者选项与 USB 调试，并在系统弹窗中允许此主控。两端授权都以实际系统结果为准，点击“检查连接”只会重新检查。\n\n拒绝或超时后，重新插线并检查授权。本机无需开启调试。',
      AddDeviceMode.ip when legacyTcp => '先通过 USB 完成被控手机的调试授权，并允许按地址连接。填写手机当前的地址与连接端口；端口取决于设备设置，不凭端口判断连接方式。\n\n此方式不使用无线调试的加密连接，仅在可信网络使用。跨网连接需已有可达路径，例如 VPN；无线调试不会自动提供互联网穿透。',
      _ => '在被控手机的“设置 → 关于手机”连续点击版本号，开启开发者选项，再打开无线调试。\n\n使用配对码时，填写配对窗口的地址、配对端口与当前配对码；扫码时，在手机选择“使用二维码配对设备”，扫描本机显示的二维码。\n\n配对端口与连接端口不同。配对后，使用无线调试主页面的连接端口；已配对但未连接时无需重复配对。\n\n手机没有无线调试时，改用 USB 完成授权。本机无需开启调试。跨网连接需已有可达路径，例如 VPN，不会自动穿透网络。',
    };
