import 'package:scrcpy_connect/widgets/grouped_list.dart';
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

class ConnectionFormPage extends HookWidget {
  const ConnectionFormPage({
    super.key,
    required this.controller,
    this.pairing = false,
    this.address = '',
    this.port = '',
    this.deviceId,
    this.transport,
  });
  final AppController controller;
  final bool pairing;
  final String address;
  final String port;
  final String? deviceId;
  final ConnectionTransport? transport;
  @override
  Widget build(BuildContext context) {
    final host = useTextEditingController(text: address);
    final portField = useTextEditingController(
      text: port.isNotEmpty
          ? port
          : transport == ConnectionTransport.tcp
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
    final selectedTransport = useState(ConnectionTransport.tls);
    final effectiveTransport = transport ?? selectedTransport.value;
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
        final currentDeviceId = responseDeviceId(result.value, deviceId);
        final pairingCode = code.text.trim();
        if (pairing) code.clear();
        final response = await controller.request(
          pairing ? 'devices.pair' : 'devices.add',
          {
            'address': host.text.trim(),
            'attemptId': attempt,
            'deviceId': ?currentDeviceId,
            'port': int.parse(portField.text.trim()),
            if (pairing) 'code': pairingCode,
            if (!pairing) 'transport': effectiveTransport.name,
          },
        );
        if (!context.mounted || activeAttempt.value != attempt) return;
        result.value = response;
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

    return PageFrame(
      title: pairing
          ? '使用配对码'
          : legacyTcp
          ? 'IP 地址连接'
          : '无线调试连接',
      child: Form(
        key: form,
        child: GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            Text(
              pairing
                  ? '填写配对窗口的信息'
                  : legacyTcp
                  ? '填写 IP 地址与连接端口'
                  : '填写无线调试主页面的信息',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              pairing
                  ? '配对端口与日常连接端口不同。配对码过期后，请在被控手机重新打开配对窗口。'
                  : legacyTcp
                  ? '先通过 USB 完成调试授权，并确认被控手机已允许按地址连接。此方式不使用无线调试的加密连接，请只在可信网络中使用。'
                  : '使用已经配对的地址及连接端口，连接必须加密。首次连接需要先配对。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: DesignTokens.spacingSectionTitle),
            if (!pairing) ...[
              if (transport == null && deviceId == null)
                ConnectSelectionField<ConnectionTransport>(
                  label: '连接方式',
                  value: selectedTransport.value,
                  icon: Icon(
                    LucideIcons.chevronDown,
                    size: DesignTokens.componentIconSmallSize,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ConnectionTransport.tls,
                      child: Text('无线调试连接', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: ConnectionTransport.tcp,
                      child: Text('IP 地址连接', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: busy.value
                      ? null
                      : (next) {
                          if (next != null) {
                            selectedTransport.value = next;
                            if (next == ConnectionTransport.tcp &&
                                portField.text.isEmpty) {
                              portField.text = '5555';
                            }
                          }
                        },
                )
              else
                Text(legacyTcp ? 'IP 地址连接' : '无线调试连接'),
              const SizedBox(height: DesignTokens.spacingMd),
            ],
            TextFormField(
              controller: host,
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
              controller: portField,
              validator: validatePort,
              enabled: !busy.value,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: pairing ? '配对端口' : '连接端口',
                helperText: pairing
                    ? '配对弹窗中显示的端口'
                    : legacyTcp
                    ? '填写被控手机允许按地址连接时设置的端口'
                    : '无线调试主页面中显示的端口，不固定为 5555',
              ),
            ),
            if (pairing) ...[
              const SizedBox(height: DesignTokens.spacingMd),
              TextFormField(
                controller: code,
                enabled: !busy.value,
                keyboardType: TextInputType.number,
                maxLength: 6,
                validator: (s) =>
                    RegExp(r'^\d{6}$').hasMatch(s ?? '') ? null : '请输入六位配对码',
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
                  : Text(pairing ? '配对并检查连接' : '连接设备'),
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
                    const Text(
                      '已配对，正在确认连接',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                    const Text('如果未自动发现连接服务，请填写无线调试主页面的连接端口，无需再次配对。'),
                    const SizedBox(height: DesignTokens.spacingMd),
                    OutlinedButton(
                      onPressed: () => ConnectionFormRoute(
                        address: host.text,
                        transport: ConnectionTransport.tls,
                        deviceId: responseDeviceId(result.value, deviceId),
                      ).push<void>(context),
                      child: const Text('填写连接端口'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: DesignTokens.spacingMd),
            if (!pairing && !legacyTcp)
              TextButton(
                onPressed: () => ConnectionFormRoute(
                  pairing: true,
                  address: host.text,
                  deviceId: responseDeviceId(result.value, deviceId),
                ).push<void>(context),
                child: Text(
                  _authorizationRejected(error.value) ? '重新配对' : '尚未配对？使用配对码',
                ),
              ),
            const StateNote('跨网连接需要已有可达网络，例如 VPN。无线调试不会自动提供互联网穿透。'),
          ],
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
    return '被控设备未信任此主控的授权身份。请在被控手机的“无线调试”中打开“使用配对码配对设备”，再使用当前显示的配对码重新配对。';
  }
  if (!pairing && failure is RequestFailure && failure.code == 'timeout') {
    return '连接超时。请检查被控设备当前的地址、连接端口和网络后重试。';
  }
  if (pairing &&
      failure is RequestFailure &&
      failure.message.toLowerCase().contains('pairing authentication failed')) {
    return '配对验证未通过。请确认正在使用被控手机当前配对窗口的端口和配对码，重新打开配对窗口后重试。';
  }
  if (pairing &&
      failure is RequestFailure &&
      (failure.code == 'disconnected' ||
          RegExp(
            r'\b(eof|end of file)\b',
            caseSensitive: false,
          ).hasMatch(failure.message))) {
    return '配对连接在完成前中断，暂时无法确认原因。请确认被控手机的配对窗口仍开启、网络可达；需要重试时，重新打开配对窗口并填写当前端口和配对码。';
  }
  return '$failure';
}
