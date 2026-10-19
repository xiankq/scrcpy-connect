import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class UsbGuidePage extends HookWidget {
  const UsbGuidePage({super.key, required this.controller});
  final AppController controller;
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
        message.value = '本次 USB 授权检查已取消。';
      } catch (error) {
        if (context.mounted) message.value = '$error';
      } finally {
        if (context.mounted) cancelling.value = false;
      }
    }

    Future<void> check([String? serial]) async {
      final id =
          'usb-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(attempt)}';
      attempt.value = id;
      busy.value = true;
      state.value = null;
      message.value = null;
      try {
        final result = await controller.execute(InteropCommand.devicesUsb, {
          'attemptId': id,
          'serial': ?serial,
          if (serial != null) 'connect': true,
        });
        if (!context.mounted || attempt.value != id) return;
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

    return PageFrame(
      title: 'USB 连接与授权',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: FeatureIcon(
              LucideIcons.usb,
              color: ConnectTokens.amber,

              size: DesignTokens.componentFeatureIconSize,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          Text('用数据线连接两台设备', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text('请使用支持数据传输的数据线。本机需要支持 USB 主机角色。'),
          const SectionTitle('在本机确认'),
          const Text('连接后，允许本应用访问 USB 设备。此权限不要求本机开启调试。'),
          const SectionTitle('在被控手机确认'),
          const Text('开启开发者选项与 USB 调试，在手机系统弹窗中允许此主控的调试授权。请核对授权对象。'),
          const SizedBox(height: DesignTokens.spacingMd),
          FilledButton(
            onPressed: busy.value ? null : () => check(),
            child: Text(busy.value ? '正在检查实际授权…' : '已连接，检查授权'),
          ),
          if (busy.value)
            TextButton(
              onPressed: cancelling.value ? null : cancel,
              child: Text(cancelling.value ? '正在取消…' : '取消本次检查'),
            ),
          if (message.value != null) StateNote(message.value!),
          const StateNote('“检查授权”只重新读取系统结果，不代替任何一端的系统授权。拒绝或超时后，可重新连接数据线再检查。'),
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
                          : '请选择要连接的 USB 设备，并在手机上确认调试授权。',
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
                      ).push<void>(context),
                      child: const Text('打开设备工作台'),
                    ),
                  for (final d in objects(state.value!['devices']))
                    ActionRow(
                      contentPadding: EdgeInsets.zero,
                      icon: LucideIcons.smartphone,
                      title: value(d, 'serial', deviceName(d)),

                      onTap: d['status'] == 'connected'
                          ? () =>
                                WorkspaceRoute(deviceId: value(d, 'id'))
                                    .push<void>(context)
                          : value(d, 'serial').isNotEmpty && !busy.value
                          ? () => check(value(d, 'serial'))
                          : null,
                    ),
                ],
              ),
            ),
          TextButton(
            onPressed: () async {
              if (busy.value) await cancel();
              if (context.mounted && !busy.value) {
                WirelessGuideRoute().push<void>(context);
              }
            },
            child: const Text('改用无线连接'),
          ),
        ],
      ),
    );
  }
}
