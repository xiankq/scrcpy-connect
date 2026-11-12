import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/pages/device_setup/usb/usb_setup_notifier.dart';
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
    final setup = ref.watch(deviceSetupProvider);
    final management = ref.watch(deviceManagementProvider);
    final scope = useMemoized(Object.new, [deviceId]);
    final viewScope = useRef(scope)..value = scope;
    final provider = usbSetupProvider(deviceId: deviceId, scope: scope);
    final state = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    final usbSupported = kIsWeb
        ? false
        : defaultTargetPlatform != TargetPlatform.iOS;
    Future<void> check({String? serial, String? usbDeviceId}) async {
      if (state.hasPendingAttempt) return;
      final allowed = await prepareConnection?.call() ?? true;
      if (!allowed ||
          !context.mounted ||
          !identical(viewScope.value, scope) ||
          !identical(ref.read(deviceSetupProvider), setup) ||
          !identical(ref.read(deviceManagementProvider), management) ||
          !identical(ref.read(provider.notifier), actions)) {
        return;
      }
      await actions.check(serial: serial, usbDeviceId: usbDeviceId);
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
        onPressed: state.hasPendingAttempt ? null : () => check(),
        child: Text(state.phase == .checking ? '正在检查…' : '检查连接'),
      ),
      if (state.hasPendingAttempt)
        TextButton(
          onPressed: state.phase == .cancelling ? null : actions.cancel,
          child: Text(switch (state.phase) {
            .cancelling => '正在取消…',
            .cleanupRequired => '重试取消',
            _ => '取消本次检查',
          }),
        ),
      if (state.message != null) StateNote(state.message!),
      if (state.result != null)
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (state.result!) {
                UsbSelectionRequired(:final message) =>
                  message ?? '选择 USB 设备，并在手机上允许调试。',
                UsbConnected() => 'USB 连接已建立',
              }),
              if (state.result case UsbConnected(:final receipt))
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
    final devices = switch (state.result) {
      UsbSelectionRequired(:final devices) => devices,
      _ => const <UsbDeviceChoice>[],
    };
    final trailing = <Widget>[
      if (!embedded)
        TextButton(
          onPressed: () async {
            if (state.hasPendingAttempt) await actions.cancel();
            if (context.mounted &&
                identical(viewScope.value, scope) &&
                identical(ref.read(provider.notifier), actions) &&
                !ref.read(provider).hasPendingAttempt) {
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
              : (usbDeviceId.isNotEmpty || serial.isNotEmpty) &&
                    !state.hasPendingAttempt
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
