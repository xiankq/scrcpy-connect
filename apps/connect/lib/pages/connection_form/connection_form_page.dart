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
  });
  final AppController controller;
  final bool pairing;
  final String address;
  final String port;
  final String? deviceId;
  @override
  Widget build(BuildContext context) {
    final host = useTextEditingController(text: address);
    final portField = useTextEditingController(text: port);
    final code = useTextEditingController();
    final form = useMemoized(() => GlobalKey<FormState>());
    final busy = useState(false);
    final result = useState<Json?>(null);
    final error = useState<String?>(null);
    final activeAttempt = useRef<String?>(null);
    final cancelling = useState(false);
    useEffect(
      () => () {
        final attempt = activeAttempt.value;
        if (attempt != null) {
          controller.request('devices.cancel', {'attemptId': attempt}).ignore();
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
        final response = await controller.request(
          pairing ? 'devices.pair' : 'devices.add',
          {
            'address': host.text.trim(),
            'attemptId': attempt,
            if (deviceId != null) 'deviceId': deviceId,
            'port': int.parse(portField.text.trim()),
            if (pairing) 'code': code.text.trim(),
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
            await controller.request('devices.connect', {
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
          error.value = '$e';
        }
      } finally {
        if (context.mounted && activeAttempt.value == attempt) {
          busy.value = false;
          activeAttempt.value = null;
        }
      }
    }

    return PageFrame(
      title: pairing ? '使用配对码' : '手动连接',
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              pairing ? '填写配对窗口的信息' : '填写无线调试主页面的信息',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              pairing
                  ? '配对端口与日常连接端口不同。配对码过期后，请在被控手机重新打开配对窗口。'
                  : '使用已经授权的地址及连接端口。首次连接需要先配对。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
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
            const SizedBox(height: 20),
            TextFormField(
              controller: portField,
              validator: validatePort,
              enabled: !busy.value,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: pairing ? '配对端口' : '连接端口',
                helperText: pairing ? '配对弹窗中显示的端口' : '无线调试主页面中显示的端口，不固定为 5555',
              ),
            ),
            if (pairing) ...[
              const SizedBox(height: 20),
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
              StateNote(
                error.value!,
                icon: LucideIcons.circleAlert,
                color: ConnectTokens.danger,
              ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: busy.value ? null : submit,
              child: busy.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
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
                    const SizedBox(height: 8),
                    const Text('如果未自动发现连接服务，请填写无线调试主页面的连接端口，无需再次配对。'),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => ConnectionFormRoute(
                        address: host.text,
                        deviceId: responseDeviceId(result.value, deviceId),
                      ).push<void>(context),
                      child: const Text('填写连接端口'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (!pairing)
              TextButton(
                onPressed: () => ConnectionFormRoute(
                  pairing: true,
                  address: host.text,
                  deviceId: responseDeviceId(result.value, deviceId),
                ).push<void>(context),
                child: const Text('尚未配对？使用配对码'),
              ),
            const StateNote('跨网连接需要已有可达网络，例如 VPN。无线调试不会自动提供互联网穿透。'),
          ],
        ),
      ),
    );
  }
}
