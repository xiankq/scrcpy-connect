import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class UsbGuidePage extends HookWidget {
  const UsbGuidePage({
    super.key,
    required this.controller,
    this.embedded = false,
    this.deviceId,
    this.onUseWireless,
    this.prepareConnection,
  });
  final AppController controller;
  final bool embedded;
  final Future<Json?> Function()? prepareConnection;
  final String? deviceId;
  final VoidCallback? onUseWireless;
  @override
  Widget build(BuildContext context) {
    final state = useState<Json?>(null);
    final busy = useState(false);
    final cancelling = useState(false);
    final attempt = useRef<String?>(null);
    final message = useState<String?>(null);
    useEffect(
      () => () {
        final id = attempt.value;
        if (id != null) {
          controller.execute(InteropCommand.devicesCancel, {
            'attemptId': id,
          }).ignore();
        }
      },
      const [],
    );
    Future<void> cancel() async {
      final id = attempt.value;
      if (id == null || cancelling.value) return;
      cancelling.value = true;
      try {
        await controller.execute(InteropCommand.devicesCancel, {
          'attemptId': id,
        });
        if (!context.mounted || attempt.value != id) return;
        attempt.value = null;
        busy.value = false;
        message.value = '检查已取消。';
      } catch (error) {
        if (context.mounted) message.value = '$error';
      } finally {
        if (context.mounted) cancelling.value = false;
      }
    }

    Future<void> check({String? serial, String? usbDeviceId}) async {
      if (busy.value) return;
      final params =
          await prepareConnection?.call() ??
          (prepareConnection == null ? <String, dynamic>{} : null);
      if (params == null || !context.mounted || busy.value) return;
      final id =
          'usb-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(attempt)}';
      attempt.value = id;
      busy.value = true;
      state.value = null;
      message.value = null;
      try {
        final result = await controller.execute(InteropCommand.devicesUsb, {
          ...params,
          'attemptId': id,
          'deviceId': ?deviceId,
          'serial': ?serial,
          'usbDeviceId': ?usbDeviceId,
          if (serial != null || usbDeviceId != null) 'connect': true,
        });
        if (!context.mounted || attempt.value != id) return;
        if (deviceId != null &&
            responseDeviceId(result) != null &&
            responseDeviceId(result) != deviceId) {
          throw const RequestFailure(
            'device_identity_mismatch',
            'USB连接结果不属于原设备，请重新检查。',
          );
        }
        state.value = result;
        await controller.refreshDevices();
      } catch (error) {
        if (context.mounted && attempt.value == id) message.value = '$error';
      } finally {
        if (context.mounted && attempt.value == id) {
          busy.value = false;
          attempt.value = null;
        }
      }
    }

    final children = <Widget>[
      Text('使用支持数据传输的数据线连接手机。', style: Theme.of(context).textTheme.bodySmall),
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
              Text(
                value(
                  state.value!,
                  'message',
                  state.value!['connected'] == true
                      ? 'USB 连接已建立'
                      : '选择 USB 设备，并在手机上允许调试。',
                ),
              ),
              if (state.value!['connected'] == true &&
                  state.value!['device'] is Map<Object?, Object?> &&
                  responseDeviceId(state.value) != null)
                FilledButton(
                  onPressed: () => WorkspaceRoute(
                    deviceId: value(
                      Map<String, dynamic>.from(
                        state.value!['device'] as Map<Object?, Object?>,
                      ),
                      'id',
                    ),
                  ).pushReplacement(context),
                  child: const Text('打开设备工作台'),
                ),
            ],
          ),
        ),
    ];
    final devices = objects(state.value?['devices']);
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
        final usbDeviceId = value(d, 'usbDeviceId');
        final serial = value(d, 'serial');
        final name = value(d, 'name');
        final label = serial.isNotEmpty
            ? serial
            : name.isNotEmpty
            ? name
            : 'USB 设备 ${deviceIndex + 1}';
        return ActionRow(
          key: ValueKey('usb-${usbDeviceId.isNotEmpty ? usbDeviceId : label}'),
          icon: LucideIcons.smartphone,
          title: label,
          onTap: d['status'] == 'connected'
              ? () =>
                    WorkspaceRoute(deviceId: value(d, 'id'))
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
