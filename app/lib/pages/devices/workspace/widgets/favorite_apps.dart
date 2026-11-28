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
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'workspace_app_grid.dart';

/// 应用行的原图标（Ardot「应用行 / 排序」37:915、「应用行 / 选择」37:920：36 点、圆角 8）。
const _rowIconSize = 36.0;

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
      onOpen: (source, app) {
        if (online) {
          openPhoneApp(context, ref, device, app, source: source);
        } else {
          feedback(context, '无法打开，请先连接设备。');
        }
      },
      empty: AppButton(
        size: AppButtonSize.section,
        icon: AppIcons.add,
        label: '添加常用应用',
        onPressed: edit,
      ),
      actionLabel: favorites.isEmpty ? null : '编辑',
      onAction: edit,
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

    final count = apps.value.length;
    return PageFrame(
      title: '管理常用应用',
      onBack: () => Navigator.pop(context),
      bottom: AppButton(
        role: AppButtonRole.primary,
        expand: true,
        onPressed: () => Navigator.pop(context, apps.value),
        label: '完成',
      ),
      child: CustomScrollView(
        slivers: [
          const PageChromeSliver(),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.componentPagePadding,
            ),
            sliver: SliverReorderableList(
              itemCount: count,
              onReorderItem: reorder,
              itemBuilder: (context, index) {
                final app = apps.value[index];
                return Semantics(
                  key: ValueKey((app.packageName, app.userId)),
                  customSemanticsActions: {
                    if (index > 0)
                      const CustomSemanticsAction(label: '上移'): () =>
                          reorder(index, index - 1),
                    if (index + 1 < count)
                      const CustomSemanticsAction(label: '下移'): () =>
                          reorder(index, index + 1),
                  },
                  child: _GroupSlice(
                    first: index == 0,
                    last: index == count - 1,
                    child: AppListRow(
                      leading: _AppIcon(deviceId: device.id, app: app),
                      leadingWidth: _rowIconSize,
                      title: Text(app.name),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          LucideIcons.gripVertical,
                          size: DesignTokens.componentBarGlyphSize,
                          color: AppColors.of(context).text,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (count > 0)
            const SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignTokens.componentPagePadding,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionFooter('按住把手拖动排序；读屏可用上移、下移调整。'),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.componentPagePadding,
              DesignTokens.componentListSectionGap,
              DesignTokens.componentPagePadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  ActionRow(
                    icon: AppIcons.add,
                    title: '选择应用',
                    value: '已选 $count 个',
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
                ],
              ),
            ),
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
      bottom: AppButton(
        role: AppButtonRole.primary,
        expand: true,
        onPressed: () => Navigator.pop(context, selected.value),
        label: '完成',
      ),
      child: AsyncContent<List<DeviceApp>>(
        loadingPlaceholder: const GroupedListView(
          padding: EdgeInsets.symmetric(
            horizontal: DesignTokens.componentPagePadding,
          ),
          children: [
            SettingsGroup(
              children: [
                SkeletonRows(
                  lines: 1,
                  leadingSize: _rowIconSize,
                  trailing: true,
                ),
              ],
            ),
          ],
        ),
        loading: result.isLoading,
        data: result.value,
        error: result.error,
        onRefresh: () => ref.invalidate(provider),
        emptyTitle: '暂时无法读取应用',
        builder: (context, apps) => ListView.builder(
          padding:
              const EdgeInsets.symmetric(
                horizontal: DesignTokens.componentPagePadding,
              ) +
              PageChromePadding.of(context),
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
            return _GroupSlice(
              first: index == 0,
              last: index == apps.length - 1,
              child: Semantics(
                checked: old != null,
                child: AppListRow(
                  selected: old != null,
                  leading: _AppIcon(
                    deviceId: deviceId,
                    app: (
                      packageName: app.packageName,
                      name: app.name,
                      userId: app.userId,
                    ),
                  ),
                  leadingWidth: _rowIconSize,
                  title: Text(app.name),
                  trailing: SelectionMark(selected: old != null),
                  onTap: () {
                    selected.value = old == null
                        ? [...selected.value, entry]
                        : selected.value.where((item) => item != old).toList();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.deviceId, required this.app});
  final String deviceId;
  final FavoriteDeviceApp app;

  @override
  Widget build(BuildContext context) => PhoneAppIcon(
    deviceId: deviceId,
    packageName: app.packageName,
    userId: app.userId,
    size: _rowIconSize,
  );
}

/// 开放列表中的一行，按位置画出分组卡片的一段：首行带上圆角、末行带下圆角，
/// 非末行在标题起点下方画分隔线（与 [SettingsGroup] 同一外观，但每行由视口分别布局）。
class _GroupSlice extends StatelessWidget {
  const _GroupSlice({
    required this.first,
    required this.last,
    required this.child,
  });
  final bool first;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    const radius = Radius.circular(DesignTokens.componentListGroupRounded);
    return Material(
      color: colors.card,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(
          top: first ? radius : Radius.zero,
          bottom: last ? radius : Radius.zero,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          child,
          if (!last)
            PositionedDirectional(
              start: listRowSeparatorIndent(_rowIconSize),
              end: DesignTokens.componentListRowPadding,
              bottom: 0,
              height: DesignTokens.componentSeparatorHeight,
              child: ColoredBox(color: colors.separator),
            ),
        ],
      ),
    );
  }
}
