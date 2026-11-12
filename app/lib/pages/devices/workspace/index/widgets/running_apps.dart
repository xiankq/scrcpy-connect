import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';

import 'dart:async';

import 'package:scrcpy_connect/pages/devices/widgets/device_access.dart';

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app_launcher.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';

class RunningApps extends HookConsumerWidget {
  const RunningApps({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppNotifier controller;
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = device.id;
    final online = device.status == DeviceConnectionStatus.connected;
    final provider = runningDeviceAppsProvider(id);
    final result = online ? ref.watch(provider) : null;
    void refresh() {
      if (result?.isLoading != true) ref.invalidate(provider);
    }

    useOnAppLifecycleStateChange((previous, next) {
      if (online &&
          next == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        refresh();
      }
    });
    useEffect(() {
      if (!online) return null;
      final timer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (context.mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed)) {
          refresh();
        }
      });
      return timer.cancel;
    }, [online, id]);
    final apps = result?.asData?.value.apps ?? const <DeviceApp>[];
    final loading = online && result?.isLoading == true && apps.isEmpty;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SectionTitle(
            '活跃应用',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '刷新后台应用',
                  onPressed: online
                      ? refresh
                      : () =>
                            offerDeviceConnection(context, controller, device),
                  icon: const Icon(
                    LucideIcons.refreshCw,
                    size: DesignTokens.componentIconSmallSize,
                  ),
                ),
                TextButton(
                  onPressed: online
                      ? () => AppsRoute(deviceId: id).push<void>(context)
                      : () =>
                            offerDeviceConnection(context, controller, device),
                  child: const Text('全部应用'),
                ),
              ],
            ),
          ),
        ),
        if (!online || loading || result?.hasError == true || apps.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacingMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    !online
                        ? '连接后查看后台应用'
                        : loading
                        ? '正在读取后台应用'
                        : result?.hasError == true
                        ? '暂时无法读取后台应用'
                        : '没有已启动的应用',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (result?.hasError == true) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(switch (result?.error) {
                      RequestFailure(code: 'apps_running_unavailable') =>
                        '这台手机暂不支持读取后台应用，可从全部应用或手机屏幕继续。',
                      RequestFailure(code: 'permission_denied') =>
                        '手机系统未允许读取后台应用，可从全部应用继续。',
                      _ => '请确认手机连接正常后重新读取。',
                    }, style: Theme.of(context).textTheme.bodySmall),
                    if (result?.error case RequestFailure(
                      code: 'apps_running_unavailable' || 'permission_denied',
                    ))
                      const SizedBox.shrink()
                    else
                      TextButton(onPressed: refresh, child: const Text('重新读取')),
                  ],
                ],
              ),
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final scale =
                  MediaQuery.textScalerOf(context)
                      .scale(DesignTokens.typographyBodyFontSize) /
                  DesignTokens.typographyBodyFontSize;
              final columns =
                  (constraints.crossAxisExtent /
                          (DesignTokens.componentAppCellWidth *
                              scale.clamp(1, 2)))
                      .floor()
                      .clamp(1, 6);
              return SliverList.builder(
                itemCount: (apps.length / columns).ceil(),
                itemBuilder: (context, row) => Padding(
                  padding: const EdgeInsets.only(
                    bottom: DesignTokens.spacingMd,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var column = 0; column < columns; column++)
                        Expanded(
                          child: row * columns + column < apps.length
                              ? _app(
                                  context,
                                  apps[row * columns + column],
                                  id,
                                  refresh,
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _app(
    BuildContext context,
    DeviceApp app,
    String id,
    VoidCallback refresh,
  ) => InkWell(
    key: ValueKey((
      deviceId: id,
      userId: app.userId,
      packageName: app.packageName,
    )),
    borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
    onTap: () async {
      await openPhoneApp(context, controller, device, app, existingTask: true);
      if (context.mounted) refresh();
    },
    onLongPress: () => openPhoneApp(
      context,
      controller,
      device,
      app,
      changeMode: true,
      existingTask: true,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingXxs,
        vertical: DesignTokens.spacingXs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhoneAppIcon(
            deviceId: id,
            packageName: app.packageName,
            userId: app.userId,
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          Text(
            app.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}
