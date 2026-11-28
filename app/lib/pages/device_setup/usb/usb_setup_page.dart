import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';
import 'package:scrcpy_connect/pages/device_setup/usb/usb_setup_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/pages/device_setup/usb/widgets/usb_status_card.dart';
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
    final content = useUsbSetupContent(
      context,
      ref,
      active: true,
      embedded: embedded,
      deviceId: deviceId,
      onUseWireless: onUseWireless,
      prepareConnection: prepareConnection,
    )!;
    if (embedded) {
      return SliverList.list(children: [content.body, ?content.primary]);
    }
    return PageFrame(
      title: '添加设备',
      bottom: content.primary,
      child: ConnectionContent(
        child: CustomScrollView(
          slivers: [
            const PageChromeSliver(),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.componentPagePadding,
                DesignTokens.spacingMd,
                DesignTokens.componentPagePadding,
                DesignTokens.componentPagePadding,
              ),
              sliver: SliverToBoxAdapter(child: content.body),
            ),
            const PageChromeBottomSliver(),
          ],
        ),
      ),
    );
  }
}

({Widget body, Widget? primary})? useUsbSetupContent(
  BuildContext context,
  WidgetRef ref, {
  required bool active,
  required String? deviceId,
  required VoidCallback? onUseWireless,
  required Future<bool> Function()? prepareConnection,
  bool embedded = true,
}) {
  final setup = ref.watch(deviceSetupProvider);
  final management = ref.watch(deviceManagementProvider);
  final scope = useMemoized(Object.new, [deviceId, active]);
  final viewScope = useRef(scope)..value = scope;
  final provider = usbSetupProvider(deviceId: deviceId, scope: scope);
  final usbSupport = useFuture(
    useMemoized(() async {
      if (!active || kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
        return false;
      }
      if (!Platform.isAndroid) return true;
      final response = await const PlatformChannels().requestOptional(
        'usb.hostSupport',
        const {},
      );
      return response?['supported'] == true;
    }, [active]),
  );
  if (!active) return null;
  final state = ref.watch(provider);
  final actions = ref.read(provider.notifier);
  final usbSupported = usbSupport.hasError ? false : usbSupport.data;
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

  ref.listen(provider.select((value) => value.result), (_, result) {
    if (result case UsbConnected(:final receipt)) {
      WorkspaceRoute(deviceId: receipt.deviceId).pushReplacement(context);
    }
  });
  final colors = AppColors.of(context);
  final type = AppTypography.of(context);
  if (usbSupported == null) {
    return (
      body: Text(
        '正在检查本机 USB 能力…',
        textAlign: TextAlign.center,
        style: type.subheadline.copyWith(color: colors.textSecondary),
      ),
      primary: null,
    );
  }
  if (!usbSupported) {
    return (
      body: const UsbStatusCard(
        title: '本机不支持 USB 连接',
        message: '可以通过无线调试连接手机。',
        status: UsbStatus.unsupported,
      ),
      primary: AppButton(
        role: AppButtonRole.primary,
        expand: true,
        onPressed:
            onUseWireless ??
            () => const WirelessGuideRoute().pushReplacement(context),
        label: '切到配对码',
      ),
    );
  }
  final devices = switch (state.result) {
    UsbSelectionRequired(:final devices) => devices,
    _ => const <UsbDeviceChoice>[],
  };
  final detected = devices.isNotEmpty || state.result is UsbConnected;
  final checking = state.phase == .checking;
  final inspected = state.result is UsbSelectionRequired;
  final primary = AppButton(
    role: AppButtonRole.primary,
    expand: true,
    onPressed: state.hasPendingAttempt ? null : () => check(),
    label: switch (state.phase) {
      .checking => '正在检查…',
      .cancelling => '正在取消…',
      .cleanupRequired => '等待清理完成',
      _ => inspected ? '重新检查' : '检查连接',
    },
  );
  final children = <Widget>[
    UsbStatusCard(
      title: checking
          ? '正在检查 USB'
          : detected
          ? '已检测到 USB 设备'
          : inspected
          ? '未检测到 USB 设备'
          : '连接手机',
      message: checking
          ? '如果本机或手机弹出授权提示，请点按允许。'
          : detected
          ? '选择下方设备，继续 USB 授权。'
          : inspected
          ? '检查数据线和手机的 USB 调试，再重新检查。'
          : '用支持数据传输的 USB 线连接手机。',
      status: checking
          ? UsbStatus.checking
          : detected
          ? UsbStatus.detected
          : UsbStatus.waiting,
    ),
    if (state.hasPendingAttempt)
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton(
          role: AppButtonRole.text,
          onPressed: state.phase == .cancelling ? null : actions.cancel,
          label: switch (state.phase) {
            .cancelling => '正在取消…',
            .cleanupRequired => '重试取消',
            _ => '取消本次检查',
          },
        ),
      ),
    if (state.message != null) StateNote(state.message!),
    if (state.result case UsbSelectionRequired(:final message?))
      if (message != state.message) StateNote(message),
  ];
  final trailing = <Widget>[
    if (!embedded)
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton(
          role: AppButtonRole.text,
          onPressed: () async {
            if (state.hasPendingAttempt) await actions.cancel();
            if (context.mounted &&
                identical(viewScope.value, scope) &&
                identical(ref.read(provider.notifier), actions) &&
                !ref.read(provider).hasPendingAttempt) {
              if (onUseWireless != null) {
                onUseWireless();
              } else {
                WirelessGuideRoute().pushReplacement(context);
              }
            }
          },
          label: '改用无线连接',
        ),
      ),
  ];
  final rows = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ...children,
      if (devices.isNotEmpty) ...[
        const SizedBox(height: DesignTokens.spacingMd),
        SettingsGroup(
          children: [
            for (final (index, device) in devices.indexed)
              AppListRow(
                leading: const ListIconBadge(
                  icon: LucideIcons.smartphone,
                  backgroundColor: FunctionTone.device,
                ),
                title: Text(
                  device.name?.isNotEmpty == true
                      ? device.name!
                      : device.serial.isNotEmpty
                      ? device.serial
                      : 'USB 设备 ${index + 1}',
                ),
                chevron: true,
                onTap: device.device?.status == .connected
                    ? () =>
                          WorkspaceRoute(deviceId: device.device!.id)
                              .pushReplacement(context)
                    : !state.hasPendingAttempt &&
                          (device.usbDeviceId?.isNotEmpty == true ||
                              device.serial.isNotEmpty)
                    ? () => check(
                        usbDeviceId: device.usbDeviceId?.isNotEmpty == true
                            ? device.usbDeviceId
                            : null,
                        serial: device.serial.isNotEmpty ? device.serial : null,
                      )
                    : null,
              ),
          ],
        ),
      ],
      ...trailing,
    ],
  );
  return (body: rows, primary: primary);
}
