import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_hero.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceWorkspacePage extends ConsumerWidget {
  const DeviceWorkspacePage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appAudioError = ref.watch(
      appControllerProvider.select((state) => state.audioError),
    );
    ref.watch(appControllerProvider.select((state) => state.devices));
    final current = controller.currentDevice(device);
    return PageFrame(
      title: deviceName(current),

      actions: [
        IconButton(
          tooltip: '设备详情',
          onPressed: () =>
              DeviceDetailsRoute(deviceId: value(current, 'id'))
                  .push<void>(context),
          icon: const Icon(LucideIcons.ellipsis),
        ),
      ],
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          DeviceHero(controller: controller, device: current),
          if (appAudioError != null)
            StateNote(appAudioError, icon: LucideIcons.volumeX),
          const SectionTitle('应用与内容'),
          ContentPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ActionRow(
                  icon: LucideIcons.layoutGrid,
                  title: '手机应用',

                  onTap: () =>
                      AppsRoute(deviceId: value(current, 'id'))
                          .push<void>(context),
                ),
                ActionRow(
                  icon: LucideIcons.folder,
                  title: '文件管理',

                  onTap: () => FilesRoute(
                    deviceId: value(current, 'id'),
                    path: '/sdcard',
                  ).push<void>(context),
                ),
                ActionRow(
                  icon: LucideIcons.images,
                  title: '手机相册',

                  onTap: () =>
                      GalleryRoute(deviceId: value(current, 'id'))
                          .push<void>(context),
                ),
              ],
            ),
          ),
          const SectionTitle('通知与通信'),
          ContentPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ActionRow(
                  icon: LucideIcons.bell,
                  title: '实时通知',

                  onTap: () =>
                      NotificationsRoute(deviceId: value(current, 'id'))
                          .push<void>(context),
                ),
                ActionRow(
                  icon: LucideIcons.phone,
                  title: '来电与通话',

                  onTap: () =>
                      CallsRoute(deviceId: value(current, 'id'))
                          .push<void>(context),
                ),
              ],
            ),
          ),
          const SectionTitle('会话与设备'),
          ActionRow(
            icon: LucideIcons.panelsTopLeft,
            title: '当前控制会话',

            onTap: () =>
                SessionsRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.slidersHorizontal,
            title: '屏幕与输入工具',

            onTap: () =>
                SessionToolsRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.gauge,
            title: '画质',
            onTap: () =>
                QualityRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.shieldCheck,
            title: '功能支持状态',
            onTap: () =>
                CapabilitiesRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          const SizedBox(height: DesignTokens.spacingLg),
        ],
      ),
    );
  }
}
