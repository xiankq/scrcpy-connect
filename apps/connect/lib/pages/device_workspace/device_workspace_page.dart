import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/device_workspace/widgets/device_hero.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceWorkspacePage extends HookConsumerWidget {
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
    useEffect(() {
      var active = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (active &&
            context.mounted &&
            ModalRoute.of(context)?.isCurrent != false) {
          controller.focusDevice(value(device, 'id')).ignore();
        }
      });
      return () => active = false;
    }, [device['id']]);
    return PageFrame(
      title: deviceName(current),
      subtitle: statusText(value(current, 'status')),
      actions: [
        IconButton(
          tooltip: '设备详情',
          onPressed: () =>
              DeviceDetailsRoute(deviceId: value(current, 'id'))
                  .push<void>(context),
          icon: const Icon(LucideIcons.ellipsis),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DeviceHero(controller: controller, device: current),
          if (appAudioError != null)
            StateNote(appAudioError, icon: LucideIcons.volumeX),
          const SectionTitle('应用与内容'),
          ContentPanel(
            child: Column(
              children: [
                ActionRow(
                  icon: LucideIcons.layoutGrid,
                  title: '手机应用',
                  subtitle: '接续原有任务，打开独立应用窗口',
                  onTap: () =>
                      AppsRoute(deviceId: value(current, 'id'))
                          .push<void>(context),
                ),
                ActionRow(
                  icon: LucideIcons.folder,
                  title: '文件管理',
                  subtitle: '浏览目录、取回与发送文件',
                  color: ConnectTokens.amber,
                  onTap: () => FilesRoute(
                    deviceId: value(current, 'id'),
                    path: '/sdcard',
                  ).push<void>(context),
                ),
                ActionRow(
                  icon: LucideIcons.images,
                  title: '手机相册',
                  subtitle: '查看照片和视频，手动保存原文件',
                  color: ConnectTokens.coral,
                  onTap: () =>
                      GalleryRoute(deviceId: value(current, 'id'))
                          .push<void>(context),
                ),
              ],
            ),
          ),
          const SectionTitle('通知与通信'),
          ContentPanel(
            child: Column(
              children: [
                ActionRow(
                  icon: LucideIcons.bell,
                  title: '实时通知',
                  subtitle: '处理当前通知，进入手机原应用',
                  onTap: () =>
                      NotificationsRoute(deviceId: value(current, 'id'))
                          .push<void>(context),
                ),
                ActionRow(
                  icon: LucideIcons.phone,
                  title: '来电与通话',
                  subtitle: '通话控制与双向语音分别检查',
                  color: ConnectTokens.mint,
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
            subtitle: '切换画面或暂停不可见会话',
            onTap: () =>
                SessionsRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.slidersHorizontal,
            title: '屏幕与输入工具',
            subtitle: '截图、实体屏幕、导航与剪贴板',
            onTap: () =>
                SessionToolsRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.gauge,
            title: '画质与声音',
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
