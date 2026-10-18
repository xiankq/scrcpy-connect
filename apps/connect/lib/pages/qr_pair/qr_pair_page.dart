import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrPairPage extends HookWidget {
  const QrPairPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final data = useState<Json?>(null);
    final outcome = useState<Json?>(null);
    final message = useState<String?>(null);
    final busy = useState(false);
    final attempt = useRef<String?>(null);
    final generation = useRef(0);
    final earlyEvents = useRef(<String, Json>{});

    void accept(Json event) {
      final payload = event['data'] is Map<Object?, Object?>
          ? jsonObject(event['data'])
          : <String, dynamic>{};
      final id = value(payload, 'attemptId');
      if (id.isEmpty) return;
      if (id != attempt.value) {
        if (busy.value && earlyEvents.value.length < 8) {
          earlyEvents.value[id] = payload;
        }
        return;
      }
      switch (payload['status']) {
        case 'paired':
          outcome.value = payload['result'] is Map<Object?, Object?>
              ? jsonObject(payload['result'])
              : {};
          message.value = outcome.value!['connected'] == true
              ? '配对与连接已完成。'
              : '配对已完成，请继续核验连接端口。';
          attempt.value = null;
          controller.refreshDevices();
        case 'expired':
          message.value = '二维码已过期，请重新生成。';
          attempt.value = null;
        case 'failed':
        case 'cancelled':
          message.value = value(payload, 'message', '本次配对已结束，请重新生成。');
          attempt.value = null;
      }
    }

    Future<void> generate() async {
      final current = ++generation.value;
      final old = attempt.value;
      attempt.value = null;
      busy.value = true;
      data.value = null;
      outcome.value = null;
      message.value = null;
      earlyEvents.value.clear();
      try {
        if (old != null) {
          await controller.execute(InteropCommand.devicesCancel, {
            'attemptId': old,
          });
        }
        final result = await controller.execute(InteropCommand.devicesPairQr);
        final id = value(result, 'attemptId');
        if (!context.mounted || generation.value != current) {
          if (id.isNotEmpty) {
            controller.execute(InteropCommand.devicesCancel, {
              'attemptId': id,
            }).ignore();
          }
          return;
        }
        data.value = result;
        attempt.value = id.isEmpty ? null : id;
        final early = earlyEvents.value.remove(id);
        if (early != null) accept({'data': early});
      } catch (error) {
        if (context.mounted && generation.value == current) {
          message.value = '$error';
        }
      } finally {
        if (context.mounted && generation.value == current) busy.value = false;
      }
    }

    useEffect(() {
      final subscription = controller
          .eventStream()
          .where((e) => e['type'] == 'pairing.changed')
          .listen(accept);
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final expiry = data.value?['expiresAt'];
        if (attempt.value != null &&
            expiry is num &&
            DateTime.now().millisecondsSinceEpoch >= expiry * 1000) {
          final id = attempt.value!;
          attempt.value = null;
          message.value = '二维码已过期，请重新生成。';
          controller.execute(InteropCommand.devicesCancel, {
            'attemptId': id,
          }).ignore();
        }
      });
      Future.microtask(generate);
      return () {
        subscription.cancel();
        timer.cancel();
        generation.value++;
        final id = attempt.value;
        if (id != null) {
          controller.execute(InteropCommand.devicesCancel, {
            'attemptId': id,
          }).ignore();
        }
      };
    }, const []);

    final paired = outcome.value;
    final pairedDevice = paired?['device'];
    return PageFrame(
      title: '扫码配对',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('用被控手机扫描', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text('在被控手机的无线调试设置中，选择“使用二维码配对设备”。二维码有效期为两分钟。'),
          const SizedBox(height: 32),
          if (busy.value) const Center(child: CircularProgressIndicator()),
          if (!busy.value &&
              attempt.value != null &&
              value(data.value ?? {}, 'payload').isNotEmpty)
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: value(data.value!, 'payload'),
                  size: 176,
                ),
              ),
            )
          else if (!busy.value &&
              attempt.value != null &&
              data.value?['imageBase64'] != null)
            Center(
              child: Image.memory(
                base64Decode(value(data.value!, 'imageBase64')),
                width: 176,
                height: 176,
              ),
            )
          else if (!busy.value && message.value == null)
            StateNote(
              value(data.value ?? {}, 'reason', '扫码配对尚未提供有效二维码，请使用配对码。'),
            ),
          if (message.value != null) StateNote(message.value!),
          if (paired != null && responseDeviceId(paired) != null)
            FilledButton(
              onPressed: () {
                if (paired['connected'] == true &&
                    pairedDevice is Map<Object?, Object?>) {
                  WorkspaceRoute(
                    deviceId: value(jsonObject(pairedDevice), 'id'),
                  ).push<void>(context);
                } else {
                  ConnectionFormRoute(
                    deviceId: responseDeviceId(paired),
                    address: value(
                      paired,
                      'address',
                      pairedDevice is Map<Object?, Object?>
                          ? value(jsonObject(pairedDevice), 'address')
                          : '',
                    ),
                  ).push<void>(context);
                }
              },
              child: Text(
                paired['connected'] == true &&
                        pairedDevice is Map<Object?, Object?>
                    ? '打开设备工作台'
                    : '填写连接端口',
              ),
            ),
          FilledButton(
            onPressed: busy.value
                ? null
                : () async {
                    busy.value = true;
                    final id = attempt.value;
                    try {
                      if (id != null) {
                        await controller.execute(InteropCommand.devicesCancel, {
                          'attemptId': id,
                        });
                      }
                      if (!context.mounted) return;
                      attempt.value = null;
                      message.value = '本次扫码已取消。返回后可重新生成二维码。';
                      busy.value = false;
                      ConnectionFormRoute(
                        pairing: true,
                        deviceId: responseDeviceId(outcome.value),
                      ).push<void>(context);
                    } catch (error) {
                      if (context.mounted) message.value = '$error';
                    } finally {
                      if (context.mounted) busy.value = false;
                    }
                  },
            child: const Text('使用配对码'),
          ),
          TextButton(
            onPressed: busy.value ? null : generate,
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
  }
}
