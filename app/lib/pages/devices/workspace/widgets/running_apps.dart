import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/pages/apps/phone_app_launcher.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';

import 'workspace_app_grid.dart';

class RunningApps extends HookConsumerWidget {
  const RunningApps({super.key, required this.device});
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
    final apps = result?.value?.apps ?? const <DeviceApp>[];
    final loading = result != null && result.isLoading && !result.hasValue;
    return SliverToBoxAdapter(
      child: WorkspaceAppGrid(
        title: '正在运行',
        deviceId: id,
        apps: apps,
        loading: loading,
        onOpen: (source, app) async {
          await openPhoneApp(context, ref, device, app, source: source);
          if (context.mounted) refresh();
        },
        actionLabel: '全部应用',
        onAction: online
            ? () => AppsRoute(deviceId: id).push<void>(context)
            : () => offerDeviceConnection(context, ref, device),
        empty: result?.hasError == true
            ? AppButton(
                role: AppButtonRole.text,
                size: AppButtonSize.section,
                onPressed: refresh,
                label: '读取失败，重试',
              )
            : Text(
                online ? '当前没有正在运行的应用' : '连接后查看正在运行的应用。',
                style: AppTypography.of(context).subheadline
                    .copyWith(color: AppColors.of(context).textSecondary),
              ),
      ),
    );
  }
}
