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
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class UsbSetupPage extends HookConsumerWidget {
  const UsbSetupPage({
    super.key,
    this.embedded = false,
    this.embeddedBuilder,
    this.deviceId,
    this.onUseWireless,
    this.prepareConnection,
  });
  final bool embedded;
  final Widget Function(Widget sliver, Widget? primary)? embeddedBuilder;
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
    final usbSupport = useFuture(
      useMemoized(() async {
        if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) return false;
        if (!Platform.isAndroid) return true;
        final response = await const PlatformChannels().requestOptional(
          'usb.hostSupport',
          const {},
        );
        return response?['supported'] == true;
      }),
    );
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
    Widget frame(Widget sliver, Widget? primary) {
      if (embedded) {
        return embeddedBuilder?.call(sliver, primary) ??
            SliverMainAxisGroup(
              slivers: [
                sliver,
                if (primary != null) SliverToBoxAdapter(child: primary),
              ],
            );
      }
      return PageFrame(
        title: '添加设备',
        bottom: primary,
        child: ConnectionContent(
          child: CustomScrollView(
            slivers: [
              const PageChromeSliver(),
              SliverPadding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                sliver: sliver,
              ),
              const PageChromeBottomSliver(),
            ],
          ),
        ),
      );
    }

    if (usbSupported == null) {
      return frame(
        const SliverToBoxAdapter(
          child: Text('正在检查本机 USB 能力…', textAlign: TextAlign.center),
        ),
        null,
      );
    }
    final theme = Theme.of(context);
    Widget statusCard(
      String title,
      String message, {
      IconData status = LucideIcons.circle,
      Color? accent,
      bool checking = false,
    }) => ContentPanel(
      radius: DesignTokens.componentWorkspaceAppPanelRounded,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight:
              DesignTokens.componentUsbStatusCardHeight -
              DesignTokens.spacingMd * 2,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.cable,
                    size: DesignTokens.componentIconLargeSize,
                    color: DesignTokens.componentConnectionIconUsbTextColor,
                  ),
                  const SizedBox(width: DesignTokens.spacingSm),
                  SizedBox(
                    width: DesignTokens.spacingLg,
                    child: Divider(color: accent),
                  ),
                  const SizedBox(width: DesignTokens.spacingXs),
                  SizedBox.square(
                    dimension: DesignTokens.componentIconSmallSize,
                    child: checking
                        ? ContentLoadingIndicator(
                            size: DesignTokens.componentIconSmallSize,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : Icon(
                            status,
                            color: accent ?? theme.colorScheme.onSurfaceVariant,
                            size: DesignTokens.componentIconSmallSize,
                          ),
                  ),
                  const SizedBox(width: DesignTokens.spacingXs),
                  SizedBox(
                    width: DesignTokens.spacingLg,
                    child: Divider(color: accent),
                  ),
                  const SizedBox(width: DesignTokens.spacingSm),
                  Icon(
                    LucideIcons.smartphone,
                    size: DesignTokens.componentIconLargeSize,
                    color: theme.colorScheme.onSurface,
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Semantics(
              liveRegion: true,
              child: Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
    if (!usbSupported) {
      return frame(
        SliverToBoxAdapter(
          child: statusCard(
            '本机不支持 USB 连接',
            '可以通过无线调试连接手机。',
            status: LucideIcons.circleAlert,
            accent: DesignTokens.colorWarning,
          ),
        ),
        FilledButton(
          onPressed:
              onUseWireless ??
              () => const WirelessGuideRoute().pushReplacement(context),
          child: const Text('切到配对码'),
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
    final primary = FilledButton(
      onPressed: state.hasPendingAttempt ? null : () => check(),
      child: Text(switch (state.phase) {
        .checking => '正在检查…',
        .cancelling => '正在取消…',
        .cleanupRequired => '等待清理完成',
        _ => inspected ? '重新检查' : '检查连接',
      }),
    );
    final children = <Widget>[
      statusCard(
        checking
            ? '正在检查 USB'
            : detected
            ? '已检测到 USB 设备'
            : inspected
            ? '未检测到 USB 设备'
            : '连接手机',
        checking
            ? '如果本机或手机弹出授权提示，请点按允许。'
            : detected
            ? '选择下方设备，继续 USB 授权。'
            : inspected
            ? '检查数据线和手机的 USB 调试，再重新检查。'
            : '用支持数据传输的 USB 线连接手机。',
        checking: checking,
        status: checking
            ? LucideIcons.loaderCircle
            : detected
            ? LucideIcons.circleCheck
            : LucideIcons.circle,
        accent: detected && !checking ? DesignTokens.colorSuccess : null,
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
      if (state.result case UsbSelectionRequired(:final message?))
        if (message != state.message) StateNote(message),
    ];
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
    final rows = SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          if (devices.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spacingSm),
            ContentPanel(
              radius: DesignTokens.componentConnectionNearbyEntryRounded,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, device) in devices.indexed)
                    ListTile(
                      leading: const Icon(
                        LucideIcons.smartphone,
                        size: DesignTokens.componentIconActionSize,
                        color: DesignTokens.componentConnectionIconIpTextColor,
                      ),
                      title: Text(
                        device.name?.isNotEmpty == true
                            ? device.name!
                            : device.serial.isNotEmpty
                            ? device.serial
                            : 'USB 设备 ${index + 1}',
                      ),
                      trailing: const Icon(
                        AppIcons.forward,
                        size: DesignTokens.componentIconSmallSize,
                      ),
                      onTap: device.device?.status == .connected
                          ? () =>
                                WorkspaceRoute(deviceId: device.device!.id)
                                    .pushReplacement(context)
                          : !state.hasPendingAttempt &&
                                (device.usbDeviceId?.isNotEmpty == true ||
                                    device.serial.isNotEmpty)
                          ? () => check(
                              usbDeviceId:
                                  device.usbDeviceId?.isNotEmpty == true
                                  ? device.usbDeviceId
                                  : null,
                              serial: device.serial.isNotEmpty
                                  ? device.serial
                                  : null,
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ],
          ...trailing,
        ],
      ),
    );
    return frame(rows, primary);
  }
}
