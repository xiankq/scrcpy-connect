import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/pages/apps/phone_app_launcher.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';

/// 应用宫格项（Ardot 应用宫格项 37:2150）：宽 78，上下 8，图标 48 与 `caption` 标签间距 4。
const _cellWidth = 78.0;
const _iconSize = 48.0;
const _cellPadding = DesignTokens.spacingSm;
const _labelGap = DesignTokens.spacingXs;

/// 宫格卡片内距（Ardot R5 全部应用 2:1154：左右 8、上下 12，行间 12）。
const _gridPadding = EdgeInsets.symmetric(
  horizontal: DesignTokens.spacingSm,
  vertical: DesignTokens.spacingMd,
);
const _rowGap = DesignTokens.spacingMd;

class DeviceAppsPage extends HookConsumerWidget {
  const DeviceAppsPage({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useTextEditingController();
    useListenable(query);
    final provider = installedDeviceAppsProvider(device.id);
    final result = ref.watch(provider);
    void refresh() => ref.invalidate(provider);
    return PageFrame(
      title: '全部应用',
      search: (controller: query, hint: '搜索应用'),
      child: AsyncContent(
        loading: result.isLoading,
        data: result.value,
        loadingPlaceholder: CustomScrollView(
          slivers: [
            const PageChromeSliver(),
            const SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignTokens.componentPagePadding,
              ),
              sliver: SliverToBoxAdapter(
                child: LoadingSkeleton(child: _SkeletonGrid()),
              ),
            ),
            const PageChromeBottomSliver(),
          ],
        ),
        error: result.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法读取应用',
        alternative: AppButton(
          role: AppButtonRole.text,
          size: AppButtonSize.section,
          onPressed: () => openRemoteRoute(context, deviceId: device.id),
          label: '在手机上继续处理',
        ),
        builder: (context, data) {
          final apps = data
              .where(
                (app) => '${app.name} ${app.packageName}'
                    .toLowerCase()
                    .contains(query.text.toLowerCase()),
              )
              .toList();
          return CustomScrollView(
            slivers: [
              const PageChromeSliver(),
              if (apps.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyContent(
                    icon: LucideIcons.layoutGrid,
                    title: query.text.isEmpty ? '没有可显示的应用' : '未找到应用',
                    message: query.text.isEmpty
                        ? '连接设备后重新获取应用列表。'
                        : '试试应用名称或包名。',
                    action: AppButton(
                      role: AppButtonRole.secondaryOnPage,
                      size: AppButtonSize.section,
                      onPressed: query.text.isEmpty ? refresh : query.clear,
                      label: query.text.isEmpty ? '重新检查' : '清除搜索',
                    ),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.componentPagePadding,
                  ),
                  sliver: _GridCard(
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return _AppCell(
                        deviceId: device.id,
                        name: app.name,
                        packageName: app.packageName,
                        onTap: () => openPhoneApp(
                          context,
                          ref,
                          device,
                          app,
                          source: context,
                        ),
                      );
                    },
                  ),
                ),
                const SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: DesignTokens.componentPagePadding,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: SectionFooter('点按应用，选择在手机屏幕中打开或打开独立应用画面。'),
                  ),
                ),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: DesignTokens.spacingLg),
              ),
              const PageChromeBottomSliver(),
            ],
          );
        },
      ),
    );
  }
}

/// 全部应用的宫格卡片：`card` 圆角 24，按 78 点列宽等分列数，每行高随文字缩放。
class _GridCard extends StatelessWidget {
  const _GridCard({required this.itemCount, required this.itemBuilder});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final type = AppTypography.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(1).clamp(1.0, 2.0);
    final cellHeight =
        2 * _cellPadding +
        _iconSize +
        _labelGap +
        scaler.scale(type.caption.fontSize! * type.caption.height!);
    return DecoratedSliver(
      decoration: ShapeDecoration(
        color: AppColors.of(context).card,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentListGroupRounded),
          ),
        ),
      ),
      sliver: SliverPadding(
        padding: _gridPadding,
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) => SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  (constraints.crossAxisExtent / (_cellWidth * scale))
                      .floor()
                      .clamp(1, 12),
              mainAxisExtent: cellHeight,
              mainAxisSpacing: _rowGap,
            ),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        ),
      ),
    );
  }
}

/// 读取中的宫格占位：两行图标块，沿真实宫格的几何排列。
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.of(context).card,
    shape: const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(DesignTokens.componentListGroupRounded),
      ),
    ),
    child: Padding(
      padding: _gridPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context)
              .scale(1)
              .clamp(1.0, 2.0);
          final columns = (constraints.maxWidth / (_cellWidth * scale))
              .floor()
              .clamp(1, 12);
          return Wrap(
            runSpacing: _rowGap,
            children: [
              for (var index = 0; index < columns * 2; index++)
                SizedBox(
                  width: constraints.maxWidth / columns,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: _cellPadding),
                    child: Center(
                      child: SkeletonBlock(
                        width: _iconSize,
                        height: _iconSize,
                        radius: DesignTokens.roundedMd,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _AppCell extends StatelessWidget {
  const _AppCell({
    required this.deviceId,
    required this.name,
    required this.packageName,
    required this.onTap,
  });
  final String deviceId;
  final String name;
  final String packageName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    excludeFromSemantics: true,
    child: InkWell(
      customBorder: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.roundedMd)),
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppColors.of(context).pressed,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _cellPadding),
        child: Column(
          children: [
            PhoneAppIcon(
              size: _iconSize,
              deviceId: deviceId,
              packageName: packageName,
            ),
            const SizedBox(height: _labelGap),
            Text(
              name,
              style: AppTypography.of(context).caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
