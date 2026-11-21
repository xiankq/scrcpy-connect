import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/apps/phone_app_launcher.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'workspace_app_grid.dart';

class FavoriteApps extends ConsumerWidget {
  const FavoriteApps({super.key, required this.device});

  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites =
        ref.watch(
          preferencesProvider.select(
            (state) => state.values.deviceSettings[device.id]?.favoriteApps,
          ),
        ) ??
        const <FavoriteDeviceApp>[];
    final online = device.status == .connected;
    Future<void> edit() async {
      if (favorites.isEmpty && !online) {
        feedback(context, '连接设备后可添加常用应用。');
        return;
      }
      final next = await Navigator.of(context).push<List<FavoriteDeviceApp>>(
        MaterialPageRoute(
          builder: (_) => favorites.isEmpty
              ? _ChooseApps(deviceId: device.id, initial: favorites)
              : _EditFavorites(device: device, initial: favorites),
        ),
      );
      if (next == null || !context.mounted) return;
      await performAction(
        context,
        () => ref
            .read(preferencesProvider.notifier)
            .updateDevice(device.id, DevicePreferences(favoriteApps: next)),
      );
    }

    return WorkspaceAppGrid(
      title: '常用应用',
      deviceId: device.id,
      apps: [
        for (final app in favorites)
          DeviceApp(
            packageName: app.packageName,
            name: app.name,
            userId: app.userId,
          ),
      ],
      onOpen: (app) {
        if (online) {
          openPhoneApp(context, ref, device, app);
        } else {
          feedback(context, '无法打开，请先连接设备。');
        }
      },
      empty: TextButton.icon(
        onPressed: edit,
        icon: const Icon(LucideIcons.plus),
        label: const Text('添加常用应用'),
      ),
      action: favorites.isEmpty
          ? null
          : TextButton(onPressed: edit, child: const Text('编辑')),
    );
  }
}

class _EditFavorites extends HookConsumerWidget {
  const _EditFavorites({required this.device, required this.initial});
  final DeviceSnapshot device;
  final List<FavoriteDeviceApp> initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = useState(initial);
    final online = ref.watch(
      deviceListProvider.select(
        (state) =>
            state.devices
                .where((item) => item.id == device.id)
                .firstOrNull
                ?.status ==
            .connected,
      ),
    );
    void reorder(int from, int to) {
      final next = [...apps.value];
      next.insert(to, next.removeAt(from));
      apps.value = next;
    }

    return PageFrame(
      title: '管理常用应用',
      onBack: () => Navigator.pop(context),
      bottom: FilledButton(
        onPressed: () => Navigator.pop(context, apps.value),
        child: const Text('完成'),
      ),
      child: CustomScrollView(
        slivers: [
          const PageChromeSliver(),
          SliverToBoxAdapter(
            child: ListTile(
              leading: const Icon(LucideIcons.listChecks),
              title: const Text('选择应用'),
              enabled: online,
              onTap: online
                  ? () async {
                      final result = await Navigator.of(context)
                          .push<List<FavoriteDeviceApp>>(
                            MaterialPageRoute(
                              builder: (_) => _ChooseApps(
                                deviceId: device.id,
                                initial: apps.value,
                              ),
                            ),
                          );
                      if (result != null && context.mounted) {
                        apps.value = result;
                      }
                    }
                  : null,
            ),
          ),
          SliverReorderableList(
            itemCount: apps.value.length,
            onReorderItem: reorder,
            itemBuilder: (context, index) {
              final app = apps.value[index];
              return Semantics(
                key: ValueKey((app.packageName, app.userId)),
                customSemanticsActions: {
                  if (index > 0)
                    const CustomSemanticsAction(label: '上移'): () =>
                        reorder(index, index - 1),
                  if (index + 1 < apps.value.length)
                    const CustomSemanticsAction(label: '下移'): () =>
                        reorder(index, index + 1),
                },
                child: ListTile(
                  leading: PhoneAppIcon(
                    deviceId: device.id,
                    packageName: app.packageName,
                    userId: app.userId,
                  ),
                  title: Text(app.name),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(DesignTokens.spacingSm),
                      child: Icon(LucideIcons.gripVertical),
                    ),
                  ),
                ),
              );
            },
          ),
          const PageChromeBottomSliver(),
        ],
      ),
    );
  }
}

class _ChooseApps extends HookConsumerWidget {
  const _ChooseApps({required this.deviceId, required this.initial});
  final String deviceId;
  final List<FavoriteDeviceApp> initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = useState(initial);
    final provider = installedDeviceAppsProvider(deviceId);
    final result = ref.watch(provider);
    return PageFrame(
      title: '选择常用应用',
      onBack: () => Navigator.pop(context),
      bottom: FilledButton(
        onPressed: () => Navigator.pop(context, selected.value),
        child: const Text('完成'),
      ),
      child: AsyncContent<List<DeviceApp>>(
        loading: result.isLoading,
        data: result.value,
        error: result.error,
        onRefresh: () => ref.invalidate(provider),
        emptyTitle: '暂时无法读取应用',
        builder: (context, apps) => ListView.builder(
          padding: PageChromePadding.of(context),
          itemCount: apps.length,
          itemBuilder: (context, index) {
            final app = apps[index];
            final entry = (
              packageName: app.packageName,
              name: app.name,
              userId: app.userId,
            );
            final old = selected.value
                .where(
                  (item) =>
                      item.packageName == app.packageName &&
                      item.userId == app.userId,
                )
                .firstOrNull;
            return CheckboxListTile(
              value: old != null,
              secondary: PhoneAppIcon(
                deviceId: deviceId,
                packageName: app.packageName,
                userId: app.userId,
              ),
              title: Text(app.name),
              onChanged: (next) {
                selected.value = next == true
                    ? [...selected.value, entry]
                    : selected.value.where((item) => item != old).toList();
              },
            );
          },
        ),
      ),
    );
  }
}
