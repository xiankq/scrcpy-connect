import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class UsbSetupPage extends HookConsumerWidget {
  const UsbSetupPage({
    super.key,
    this.embedded = false,
    this.deviceId,
    this.onUseWireless,
    this.prepareConnection,
  });
  final bool embedded;
  final Future<bool> Function()? prepareConnection;
  final String? deviceId;
  final VoidCallback? onUseWireless;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceManagement = ref.watch(deviceManagementProvider);
    final setup = ref.watch(deviceSetupProvider);
    final usbSupported = kIsWeb
        ? false
        : defaultTargetPlatform != TargetPlatform.iOS;
    final state = useState<UsbSetupResult?>(null);
    final busy = useState(false);
    final cancelling = useState(false);
    final attempt = useRef<String?>(null);
    final message = useState<String?>(null);
    bool ownsScope() =>
        context.mounted &&
        identical(setup, ref.read(deviceSetupProvider)) &&
        identical(deviceManagement, ref.read(deviceManagementProvider));
    useEffect(() {
      Future.microtask(() {
        if (!context.mounted || !ownsScope()) return;
        state.value = null;
        busy.value = false;
        cancelling.value = false;
        message.value = null;
      });
      return () {
        final id = attempt.value;
        attempt.value = null;
        if (id != null) deviceManagement.cancelConnectionAttempt(id).ignore();
      };
    }, [setup, deviceManagement, deviceId]);
    Future<void> cancel() async {
      final id = attempt.value;
      if (id == null || cancelling.value) return;
      cancelling.value = true;
      try {
        await deviceManagement.cancelConnectionAttempt(id);
        if (!context.mounted || !ownsScope() || attempt.value != id) {
          return;
        }
        attempt.value = null;
        busy.value = false;
        message.value = '检查已取消。';
      } catch (error) {
        if (context.mounted && ownsScope()) message.value = '$error';
      } finally {
        if (context.mounted && ownsScope()) cancelling.value = false;
      }
    }

    Future<void> check({String? serial, String? usbDeviceId}) async {
      if (busy.value) return;
      final allowed = await prepareConnection?.call() ?? true;
      if (!allowed || !context.mounted || !ownsScope() || busy.value) {
        return;
      }
      final id =
          'usb-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(attempt)}';
      attempt.value = id;
      busy.value = true;
      state.value = null;
      message.value = null;
      try {
        final result = await setup.connectUsb(
          attemptId: id,
          deviceId: deviceId,
          serial: serial,
          usbDeviceId: usbDeviceId,
          connect: serial != null || usbDeviceId != null,
        );
        if (!context.mounted || !ownsScope() || attempt.value != id) {
          return;
        }
        if (deviceId != null &&
            result.deviceId != null &&
            result.deviceId != deviceId) {
          throw const RequestFailure(
            'device_identity_mismatch',
            'USB连接结果不属于原设备，请重新检查。',
          );
        }
        state.value = result;
        await ref.read(deviceListProvider.notifier).refresh();
      } catch (error) {
        if (context.mounted && ownsScope() && attempt.value == id) {
          message.value = '$error';
        }
      } finally {
        if (context.mounted && ownsScope() && attempt.value == id) {
          busy.value = false;
          attempt.value = null;
        }
      }
    }

    if (!usbSupported) {
      final limited = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('当前主控不支持 USB 设备连接。请使用无线调试配对。'),
          const SizedBox(height: DesignTokens.spacingMd),
          FilledButton(
            onPressed:
                onUseWireless ??
                () => const WirelessGuideRoute().pushReplacement(context),
            child: const Text('使用配对码'),
          ),
        ],
      );
      return embedded
          ? SliverToBoxAdapter(child: limited)
          : PageFrame(
              title: '添加设备',
              child: ConnectionContent(child: limited),
            );
    }
    final children = <Widget>[
      Text('使用支持数据传输的数据线连接手机。', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: DesignTokens.spacingMd),
      Text('本机：允许访问 USB 设备。', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: DesignTokens.spacingSm),
      Text(
        '被控手机：开启 USB 调试，并在系统弹窗中允许调试。',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: DesignTokens.spacingSectionTitle),
      FilledButton(
        onPressed: busy.value ? null : () => check(),
        child: Text(busy.value ? '正在检查…' : '检查连接'),
      ),
      if (busy.value)
        TextButton(
          onPressed: cancelling.value ? null : cancel,
          child: Text(cancelling.value ? '正在取消…' : '取消本次检查'),
        ),
      if (message.value != null) StateNote(message.value!),
      if (state.value != null)
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (state.value!) {
                UsbSelectionRequired(:final message) =>
                  message ?? '选择 USB 设备，并在手机上允许调试。',
                UsbConnected() => 'USB 连接已建立',
              }),
              if (state.value case UsbConnected(:final receipt))
                FilledButton(
                  onPressed: () =>
                      WorkspaceRoute(deviceId: receipt.deviceId)
                          .pushReplacement(context),
                  child: const Text('打开设备工作台'),
                ),
            ],
          ),
        ),
    ];
    final devices = switch (state.value) {
      UsbSelectionRequired(:final devices) => devices,
      _ => const <UsbDeviceChoice>[],
    };
    final trailing = <Widget>[
      if (!embedded)
        TextButton(
          onPressed: () async {
            if (busy.value) await cancel();
            if (context.mounted && !busy.value) {
              if (onUseWireless != null) {
                onUseWireless!();
              } else {
                WirelessGuideRoute().pushReplacement(context);
              }
            }
          },
          child: const Text('改用无线连接'),
        ),
    ];
    final rows = SliverList.builder(
      itemCount: children.length + devices.length + trailing.length,
      itemBuilder: (context, index) {
        if (index < children.length) return children[index];
        final deviceIndex = index - children.length;
        if (deviceIndex >= devices.length) {
          return trailing[deviceIndex - devices.length];
        }
        final d = devices[deviceIndex];
        final usbDeviceId = d.usbDeviceId ?? '';
        final serial = d.serial;
        final name = d.name ?? '';
        final label = serial.isNotEmpty
            ? serial
            : name.isNotEmpty
            ? name
            : 'USB 设备 ${deviceIndex + 1}';
        return ActionRow(
          key: ValueKey('usb-${usbDeviceId.isNotEmpty ? usbDeviceId : label}'),
          icon: LucideIcons.smartphone,
          title: label,
          onTap: d.device?.status == .connected
              ? () =>
                    WorkspaceRoute(deviceId: d.device!.id)
                        .pushReplacement(context)
              : (usbDeviceId.isNotEmpty || serial.isNotEmpty) && !busy.value
              ? () => check(
                  usbDeviceId: usbDeviceId.isNotEmpty ? usbDeviceId : null,
                  serial: serial.isNotEmpty ? serial : null,
                )
              : null,
        );
      },
    );
    if (embedded) return rows;
    return PageFrame(
      title: '添加设备',
      child: ConnectionContent(
        child: CustomScrollView(
          slivers: [
            const PageChromeSliver(),
            SliverPadding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              sliver: rows,
            ),
            const PageChromeBottomSliver(),
          ],
        ),
      ),
    );
  }
}
