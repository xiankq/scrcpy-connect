import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

/// 远端操作不可用时提供连接入口，连接后不自动重放该动作。
Future<void> offerDeviceConnection(
  BuildContext context,
  AppStore controller,
  Json device,
) async {
  if (deviceConnectionInProgress(device)) {
    feedback(context, '设备正在连接，请稍后重试。');
    return;
  }
  final unauthorized = device['status'] == 'unauthorized';
  if (!await confirmConnectionChange(
        context,
        unauthorized ? '手机尚未授权' : '设备尚未连接',
        '连接设备后再使用此功能。本机信息与连接偏好仍可查看。',
        action: unauthorized ? '重新授权' : '连接设备',
      ) ||
      !context.mounted) {
    return;
  }
  if (device['transport'] == 'usb') {
    await UsbGuideRoute(deviceId: value(device, 'id')).push<void>(context);
  } else if (unauthorized) {
    await AddDeviceRoute(deviceId: value(device, 'id')).push<void>(context);
  } else {
    await perform(context, controller, 'devices.connect', {
      'deviceId': device['id'],
    });
    await controller.refreshDevices();
  }
}

Future<void> stopDeviceConnection(
  BuildContext context,
  AppStore controller,
  Json device,
) async {
  final current = controller.currentDevice(device);
  final online = current['status'] == 'connected';
  if (!await confirmConnectionChange(
        context,
        '${online ? '断开' : '停止'}与 ${deviceName(current)} 的连接？',
        '将停止连接和自动重连，关闭此设备的控制画面；进行中的传输和其他活动可能中断。设备记录与已保存文件保留，可稍后手动连接。',
        action: online ? '断开连接' : '停止连接',
      ) ||
      !context.mounted) {
    return;
  }
  await perform(context, controller, 'devices.disconnect', {
    'deviceId': current['id'],
  });
  await controller.refreshDevices();
}

Future<bool> removeSavedDevice(
  BuildContext context,
  AppStore controller,
  Json device,
) async {
  if (!await confirmConnectionChange(
        context,
        '移除 ${deviceName(device)}？',
        '将断开连接并删除本机设备记录与偏好。已保存文件会保留。如需撤销手机对本机的调试授权，请在手机的调试设置中操作。',
        action: '移除设备',
        danger: true,
      ) ||
      !context.mounted) {
    return false;
  }
  final result = await perform(context, controller, 'devices.forget', {
    'deviceId': device['id'],
  });
  await controller.refreshDevices();
  return result != null;
}
