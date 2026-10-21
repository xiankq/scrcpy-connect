import 'dart:async';

import 'package:scrcpy_connect/pages/devices/widgets/device_access.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';

class RunningApps extends HookWidget {
  const RunningApps({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;

  @override
  Widget build(BuildContext context) {
    final id = value(device, 'id');
    final online = device['status'] == 'connected';
    final revision = useState(0);
    final pending = useRef(false);
    void refresh() {
      if (!pending.value) revision.value++;
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
    final future = useMemoized(() {
      if (!online) return Future<Json>.value({});
      pending.value = true;
      return controller
          .request('apps.list', {'deviceId': id, 'filter': 'running'})
          .then((data) {
            if (data['deviceId'] != id ||
                data['source'] != 'runningTasks' ||
                data['live'] != true ||
                data['apps'] is! List) {
              throw const RequestFailure(
                'apps_running_unavailable',
                '当前设备未提供后台应用列表',
              );
            }
            return data;
          })
          .whenComplete(() => pending.value = false);
    }, [controller, id, online, revision.value]);
    final result = useFuture(future, preserveState: true);
    final apps = objects(result.data?['apps']);
    final loading =
        online &&
        result.connectionState != ConnectionState.done &&
        !result.hasData;
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
        if (!online || loading || result.hasError || apps.isEmpty)
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
                        : result.hasError
                        ? '暂时无法读取后台应用'
                        : '没有已启动的应用',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (result.hasError) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(switch (result.error) {
                      RequestFailure(code: 'apps_running_unavailable') =>
                        '这台手机暂不支持读取后台应用，可从全部应用或手机屏幕继续。',
                      RequestFailure(code: 'permission_denied') =>
                        '手机系统未允许读取后台应用，可从全部应用继续。',
                      _ => '请确认手机连接正常后重新读取。',
                    }, style: Theme.of(context).textTheme.bodySmall),
                    if (result.error case RequestFailure(
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
    Json app,
    String id,
    VoidCallback refresh,
  ) => InkWell(
    key: ValueKey('$id:${value(app, 'userId')}:${value(app, 'packageName')}'),
    borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
    onTap: () async {
      await openPhoneApp(context, device, app);
      if (context.mounted) refresh();
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingXxs,
        vertical: DesignTokens.spacingXs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhoneAppIcon(
            controller: controller,
            deviceId: id,
            packageName: value(app, 'packageName'),
            userId: value(app, 'userId'),
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          Text(
            value(app, 'name', value(app, 'packageName')),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}
