import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

/// An unavailable remote action offers connection without replaying the action.
Future<void> offerDeviceConnection(
  BuildContext context,
  AppController controller,
  Json device,
) async {
  if (['connecting', 'checking', 'reconnecting'].contains(device['status'])) {
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

Future<bool> removeSavedDevice(
  BuildContext context,
  AppController controller,
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
