import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_summary.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';

/// 两个按钮并排所需的最小行宽（按文字缩放折算），不足时上下排列。
const _stackedActionsWidth = 240.0;

class DeviceHero extends HookConsumerWidget {
  const DeviceHero({super.key, required this.device, this.pane = false});
  final DeviceSnapshot device;
  final bool pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(deviceConnectionsProvider);
    final busy = useValueNotifier(false, [connections, device.id]);
    useListenable(busy);
    final currentBusy = useRef(busy);
    currentBusy.value = busy;
    bool isCurrent() =>
        context.mounted &&
        identical(currentBusy.value, busy) &&
        identical(connections, ref.read(deviceConnectionsProvider));
    final online = device.status == DeviceConnectionStatus.connected;
    final lifecycle = useAppLifecycleState();
    final visible =
        RemoteWindows.isVisible(context) &&
        ModalRoute.isCurrentOf(context) != false &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    final connectionId = device.connectionId;
    final battery = online && visible && connectionId != null
        ? ref.watch(
            deviceBatteryProvider(device.id, connectionId: connectionId),
          )
        : null;
    final unauthorized = device.status == DeviceConnectionStatus.unauthorized;
    final connecting = busy.value || deviceConnectionInProgress(device);
    final id = device.id;
    final mainAction = AppButton(
      role: AppButtonRole.primary,
      expand: true,
      onPressed: connecting
          ? busy.value && !deviceConnectionInProgress(device)
                ? null
                : () => stopDeviceConnection(context, ref, device)
          : () async {
              if (online) {
                await openRemoteRoute(context, deviceId: id);
              } else {
                busy.value = true;
                try {
                  await startDeviceConnection(context, ref, device);
                } finally {
                  if (isCurrent()) busy.value = false;
                }
              }
            },
      label: connecting
          ? '取消连接'
          : online
          ? '打开手机屏幕'
          : unauthorized
          ? '重新授权'
          : device.status == .failed
          ? '重试'
          : '连接',
    );
    final details = AppButton(
      expand: true,
      onPressed: () => DeviceDetailsRoute(deviceId: id).push<void>(context),
      label: '设备详情',
    );
    // 工作台概览（Ardot 37:1626）：hero-card，内距 20，概览与按钮间距 20，按钮间距 12。
    return Material(
      color: AppColors.of(context).card,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(DesignTokens.componentHeroCardRounded),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.componentHeroCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeviceSummary(
              device: device,
              battery: battery?.hasError == false
                  ? battery?.value?.value
                  : null,
              connecting: busy.value,
              pane: pane,
            ),
            const SizedBox(height: DesignTokens.spacingXl),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                return constraints.maxWidth / scale < _stackedActionsWidth
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          mainAction,
                          const SizedBox(height: DesignTokens.spacingMd),
                          details,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: mainAction),
                          const SizedBox(width: DesignTokens.spacingMd),
                          Expanded(child: details),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}
