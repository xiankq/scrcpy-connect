import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/router/app_router.dart';
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
    final data = useState<QrPairingSession?>(null);
    final outcome = useState<PairingReceipt?>(null);
    final message = useState<String?>(null);
    final busy = useState(false);
    final attempt = useRef<String?>(null);
    final generation = useRef(0);
    bool current(int revision) =>
        context.mounted &&
        generation.value == revision &&
        identical(setup, ref.read(deviceSetupProvider)) &&
        identical(deviceManagement, ref.read(deviceManagementProvider));

    Future<void> receive(QrPairingSession session, int revision) async {
      PairingReceipt? receipt;
      Object? failure;
      try {
        receipt = await session.result;
      } catch (error) {
        failure = error;
        if (error case DeviceSetupFailure(receipt: PairingReceipt known)
            when known.recorded) {
          receipt = known;
        }
      }
      if (!current(revision) || attempt.value != session.attemptId) return;
      attempt.value = null;
      if (receipt case final paired? when paired.recorded) {
        if (deviceId != null && paired.deviceId != deviceId) {
          message.value = '配对结果不属于原设备，请重新检查。';
          return;
        }
        outcome.value = paired;
        onPaired?.call(paired);
        message.value = switch ((
          failure,
          paired.connected,
          paired.connectionFailure,
        )) {
          (final error?, _, _) => '配对已完成，资源释放尚未确认。$error',
          (_, true, _) => '配对与连接已完成。',
          (_, _, final issue?) => '已配对，尚未连接。${issue.message}',
          _ => '已配对，尚未连接',
        };
        unawaited(ref.read(deviceListProvider.notifier).refresh());
      } else {
        message.value = failure is RequestFailure && failure.code == 'expired'
            ? '二维码已过期，请重新生成。'
            : failure?.toString() ?? '配对已结束，请重新生成。';
      }
    }

    Future<void> generate() async {
      final revision = ++generation.value;
      final old = attempt.value;
      attempt.value = null;
      busy.value = true;
      data.value = null;
      outcome.value = null;
      message.value = null;
      try {
        if (old != null) await deviceManagement.cancelConnectionAttempt(old);
        final allowed = await prepareConnection?.call() ?? true;
        if (!allowed || !current(revision)) return;
        final session = await setup.beginQrPairing(deviceId: deviceId);
        if (!current(revision)) {
          deviceManagement.cancelConnectionAttempt(session.attemptId).ignore();
          return;
        }
        data.value = session;
        attempt.value = session.attemptId;
        unawaited(receive(session, revision));
      } catch (error) {
        if (current(revision)) message.value = '$error';
      } finally {
        if (current(revision)) busy.value = false;
      }
    }

    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final expiry = data.value?.expiresAt;
        if (attempt.value != null &&
            expiry != null &&
            !DateTime.now().isBefore(expiry)) {
          final id = attempt.value!;
          attempt.value = null;
          message.value = '二维码已过期，请重新生成。';
          deviceManagement.cancelConnectionAttempt(id).ignore();
        }
      });
      Future.microtask(() {
        if (!context.mounted ||
            !identical(setup, ref.read(deviceSetupProvider)) ||
            !identical(deviceManagement, ref.read(deviceManagementProvider))) {
          return;
        }
        if (autoGenerate) {
          unawaited(generate());
        } else {
          data.value = null;
          outcome.value = null;
          busy.value = false;
          message.value = null;
        }
      });
      return () {
        timer.cancel();
        generation.value++;
        final id = attempt.value;
        attempt.value = null;
        if (id != null) deviceManagement.cancelConnectionAttempt(id).ignore();
      };
    }, [setup, deviceManagement, deviceId]);

    final paired = outcome.value;
    final hasQr =
        !busy.value &&
        attempt.value != null &&
        data.value?.payload.isNotEmpty == true;
    final children = <Widget>[
      if (hasQr) ...[
        Text(
          '在手机的无线调试中选择“使用二维码配对设备”，扫描此二维码。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: DesignTokens.spacingLg),
      ],
      if (busy.value) const Center(child: CircularProgressIndicator()),
      if (hasQr)
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: QrImageView(
              data: data.value!.payload,
              size: DesignTokens.componentPairingQrSize,
            ),
          ),
        )
      else if (!busy.value && message.value == null)
        const StateNote('点击重新生成以获取配对二维码。'),
      if (message.value != null) StateNote(message.value!),
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
          onPressed: busy.value
              ? null
              : () async {
                  final revision = ++generation.value;
                  busy.value = true;
                  final id = attempt.value;
                  try {
                    if (id != null) {
                      await deviceManagement.cancelConnectionAttempt(id);
                    }
                    if (!context.mounted || !current(revision)) return;
                    attempt.value = null;
                    message.value = '扫码已取消，可重新生成。';
                    busy.value = false;
                    if (onUsePairingCode != null) {
                      onUsePairingCode!();
                      return;
                    }
                    ConnectionFormRoute(
                      pairing: true,
                      deviceId: outcome.value?.deviceId,
                    ).pushReplacement(context);
                  } catch (error) {
                    if (current(revision)) message.value = '$error';
                  } finally {
                    if (current(revision)) busy.value = false;
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
