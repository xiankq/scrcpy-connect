import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

/// 远端操作不可用时提供连接入口，连接后不自动重放该动作。
Future<void> offerDeviceConnection(
  BuildContext context,
  WidgetRef ref,
  DeviceSnapshot device,
) async {
  if (deviceConnectionInProgress(device)) {
    feedback(context, '设备正在连接，请稍后重试。');
    return;
  }
  final connections = ref.read(deviceConnectionsProvider);
  final unauthorized = device.status == DeviceConnectionStatus.unauthorized;
  if (!await confirmConnectionChange(
        context,
        unauthorized ? '手机尚未授权' : '设备尚未连接',
        '连接设备后再使用此功能。本机信息与连接偏好仍可查看。',
        action: unauthorized ? '重新授权' : '连接设备',
      ) ||
      !context.mounted ||
      !identical(connections, ref.read(deviceConnectionsProvider))) {
    return;
  }
  await startDeviceConnection(context, ref, device);
}

Future<void> startDeviceConnection(
  BuildContext context,
  WidgetRef ref,
  DeviceSnapshot device,
) async {
  final connections = ref.read(deviceConnectionsProvider);
  if (device.transport == DeviceTransport.usb) {
    await UsbGuideRoute(deviceId: device.id).push<void>(context);
  } else if (device.status == .unauthorized) {
    await AddDeviceRoute(deviceId: device.id).push<void>(context);
  } else {
    try {
      await connections.connectDevice(device.id);
    } catch (error) {
      if (context.mounted &&
          identical(connections, ref.read(deviceConnectionsProvider))) {
        feedback(
          context,
          failureMessage(error, fallback: '无法连接手机。请确认手机开着，再试一次。'),
        );
      }
    }
    if (context.mounted &&
        identical(connections, ref.read(deviceConnectionsProvider))) {
      await ref.read(deviceListProvider.notifier).refresh();
    }
  }
}

Future<void> stopDeviceConnection(
  BuildContext context,
  WidgetRef ref,
  DeviceSnapshot device,
) async {
  final management = ref.read(deviceManagementProvider);
  final current = ref.read(deviceListProvider.notifier).current(device);
  final online = current.status == DeviceConnectionStatus.connected;
  if (!await confirmConnectionChange(
        context,
        '${online ? '断开' : '停止'}与 ${deviceName(current)} 的连接？',
        '将停止连接和自动重连，关闭此设备的控制画面；进行中的传输和其他活动可能中断。设备记录与已保存文件保留，可稍后手动连接。',
        action: online ? '断开连接' : '停止连接',
      ) ||
      !context.mounted ||
      !identical(management, ref.read(deviceManagementProvider))) {
    return;
  }
  try {
    await management.disconnectDevice(current.id);
  } catch (error) {
    if (context.mounted) {
      feedback(
        context,
        failureMessage(error, fallback: '暂时无法确认连接是否已断开。请先查看设备列表。'),
      );
    }
  }
  if (context.mounted &&
      identical(management, ref.read(deviceManagementProvider))) {
    await ref.read(deviceListProvider.notifier).refresh();
  }
}

Future<bool> removeSavedDevice(
  BuildContext context,
  WidgetRef ref,
  DeviceSnapshot device,
) async {
  final management = ref.read(deviceManagementProvider);
  if (!await confirmConnectionChange(
        context,
        '移除 ${deviceName(device)}？',
        '将断开连接并删除本机设备记录与偏好。已保存文件会保留。如需撤销手机对本机的调试授权，请在手机的调试设置中操作。',
        action: '移除设备',
        danger: true,
      ) ||
      !context.mounted ||
      !identical(management, ref.read(deviceManagementProvider))) {
    return false;
  }
  var removed = false;
  try {
    await management.forgetDevice(device.id);
    removed = true;
  } catch (error) {
    if (context.mounted) {
      feedback(
        context,
        failureMessage(error, fallback: '暂时无法确认设备是否已移除。请先查看设备列表。'),
      );
    }
  }
  if (context.mounted &&
      identical(management, ref.read(deviceManagementProvider))) {
    await ref.read(deviceListProvider.notifier).refresh();
  }
  return removed;
}
