import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class QrPairPage extends HookWidget {
  const QrPairPage({
    super.key,
    required this.controller,
    this.deviceId,
    this.embedded = false,
    this.onUsePairingCode,
    this.onConnectionPort,
    this.onPaired,
    this.prepareConnection,
    this.autoGenerate = true,
  });
  final AppStore controller;
  final String? deviceId;
  final bool embedded;
  final bool autoGenerate;
  final Future<Json?> Function()? prepareConnection;
  final VoidCallback? onUsePairingCode;
  final ValueChanged<Json>? onPaired;
  final void Function(String address, String? deviceId)? onConnectionPort;
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
          if (deviceId != null && responseDeviceId(outcome.value) != deviceId) {
            outcome.value = null;
            message.value = '配对结果不属于原设备，请重新检查。';
            attempt.value = null;
            return;
          }
          onPaired?.call(outcome.value!);
          final failure = outcome.value!['connectionFailure'];
          final cleanup = outcome.value!['cleanupFailure'];
          message.value = cleanup is Map<Object?, Object?>
              ? '配对已完成，资源释放尚未确认。${value(jsonObject(cleanup), 'message')}'
              : outcome.value!['connected'] == true
              ? '配对与连接已完成。'
              : failure is Map<Object?, Object?>
              ? '已配对，尚未连接。${value(jsonObject(failure), 'message')}'
              : '已配对，尚未连接';
          attempt.value = null;
          controller.refreshDevices();
        case 'expired':
          message.value = '二维码已过期，请重新生成。';
          attempt.value = null;
        case 'failed':
        case 'cancelled':
          message.value = value(payload, 'message', '配对已结束，请重新生成。');
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
          await controller.execute(ApplicationCommand.devicesCancel, {
            'attemptId': old,
          });
        }
        final params =
            await prepareConnection?.call() ??
            (prepareConnection == null ? <String, dynamic>{} : null);
        if (params == null || !context.mounted || generation.value != current) {
          return;
        }
        final result = await controller.execute(
          ApplicationCommand.devicesPairQr,
          {...params, 'deviceId': ?deviceId},
        );
        final id = value(result, 'attemptId');
        if (!context.mounted || generation.value != current) {
          if (id.isNotEmpty) {
            controller.execute(ApplicationCommand.devicesCancel, {
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
          controller.execute(ApplicationCommand.devicesCancel, {
            'attemptId': id,
          }).ignore();
        }
      });
      if (autoGenerate) Future.microtask(generate);
      return () {
        subscription.cancel();
        timer.cancel();
        generation.value++;
        final id = attempt.value;
        if (id != null) {
          controller.execute(ApplicationCommand.devicesCancel, {
            'attemptId': id,
          }).ignore();
        }
      };
    }, const []);

    final paired = outcome.value;
    final pairedDevice = paired?['device'];
    final hasQr =
        !busy.value &&
        attempt.value != null &&
        (value(data.value ?? {}, 'payload').isNotEmpty ||
            data.value?['imageBase64'] != null);
    final children = <Widget>[
      if (hasQr) ...[
        Text(
          '在手机的无线调试中选择“使用二维码配对设备”，扫描此二维码。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: DesignTokens.spacingLg),
      ],
      if (busy.value) const Center(child: CircularProgressIndicator()),
      if (!busy.value &&
          attempt.value != null &&
          value(data.value ?? {}, 'payload').isNotEmpty)
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: QrImageView(
              data: value(data.value!, 'payload'),
              size: DesignTokens.componentPairingQrSize,
            ),
          ),
        )
      else if (!busy.value &&
          attempt.value != null &&
          data.value?['imageBase64'] != null)
        Center(
          child: Image.memory(
            base64Decode(value(data.value!, 'imageBase64')),
            width: DesignTokens.componentPairingQrSize,
            height: DesignTokens.componentPairingQrSize,
          ),
        )
      else if (!busy.value && message.value == null)
        StateNote(value(data.value ?? {}, 'reason', '点击重新生成以获取配对二维码。')),
      if (message.value != null) StateNote(message.value!),
      if (paired != null && responseDeviceId(paired) != null)
        FilledButton(
          onPressed: () {
            if (paired['connected'] == true &&
                pairedDevice is Map<Object?, Object?>) {
              WorkspaceRoute(deviceId: value(jsonObject(pairedDevice), 'id'))
                  .pushReplacement(context);
            } else {
              final address = value(
                paired,
                'address',
                pairedDevice is Map<Object?, Object?>
                    ? value(jsonObject(pairedDevice), 'address')
                    : '',
              );
              if (onConnectionPort != null) {
                onConnectionPort!(address, responseDeviceId(paired));
                return;
              }
              ConnectionFormRoute(
                transport: ConnectionTransport.tls,
                deviceId: responseDeviceId(paired),
                address: value(
                  paired,
                  'address',
                  pairedDevice is Map<Object?, Object?>
                      ? value(jsonObject(pairedDevice), 'address')
                      : '',
                ),
              ).pushReplacement(context);
            }
          },
          child: Text(
            paired['connected'] == true && pairedDevice is Map<Object?, Object?>
                ? '打开设备工作台'
                : '填写连接端口',
          ),
        ),
      if (!embedded)
        FilledButton(
          onPressed: busy.value
              ? null
              : () async {
                  busy.value = true;
                  final id = attempt.value;
                  try {
                    if (id != null) {
                      await controller.execute(
                        ApplicationCommand.devicesCancel,
                        {'attemptId': id},
                      );
                    }
                    if (!context.mounted) return;
                    attempt.value = null;
                    message.value = '扫码已取消，可重新生成。';
                    busy.value = false;
                    if (onUsePairingCode != null) {
                      onUsePairingCode!();
                      return;
                    }
                    ConnectionFormRoute(
                      pairing: true,
                      deviceId: responseDeviceId(outcome.value),
                    ).pushReplacement(context);
                  } catch (error) {
                    if (context.mounted) message.value = '$error';
                  } finally {
                    if (context.mounted) busy.value = false;
                  }
                },
          child: const Text('使用配对码'),
        ),
      const SizedBox(height: DesignTokens.spacingSectionTitle),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy.value ? null : generate,
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
