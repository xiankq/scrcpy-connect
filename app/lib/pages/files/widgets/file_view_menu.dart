import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';

/// 视图与排序就地面板（Ardot F2 2:1594 41:1253）：glass-menu，圆角 28，内距与间距 8，
/// 与底栏同宽（页面宽减左右 16），从底栏上方展开。
const _panelRounded = DesignTokens.roundedXxl;
const _panelMaxWidth = 370.0;

/// 面板底边与底栏顶边的间距。
const _panelGap = DesignTokens.spacingSm;

class FileViewMenuButton extends HookWidget {
  const FileViewMenuButton({
    super.key,
    required this.viewMode,
    required this.sortKey,
    required this.ascending,
    required this.onViewModeChanged,
    required this.onSortKeyChanged,
    required this.onAscendingChanged,
  });

  final FileViewMode viewMode;
  final FileSortKey sortKey;
  final bool ascending;
  final ValueChanged<FileViewMode> onViewModeChanged;
  final ValueChanged<FileSortKey> onSortKeyChanged;
  final ValueChanged<bool> onAscendingChanged;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final menu = useMemoized(MenuController.new);
    final colors = AppColors.of(context);
    final width = math.min(
      _panelMaxWidth,
      size.width -
          MediaQuery.paddingOf(context).horizontal -
          2 * DesignTokens.componentPagePadding,
    );
    return MenuAnchor(
      controller: menu,
      animated: !GlassMaterial.reduceMotion(context),
      consumeOutsideTap: true,
      clipBehavior: Clip.none,
      alignmentOffset: Offset(
        -width / 2,
        DesignTokens.componentFootBarPadding + _panelGap,
      ),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomCenter,
        backgroundColor: WidgetStatePropertyAll(colors.page.withAlpha(0)),
        surfaceTintColor: WidgetStatePropertyAll(colors.page.withAlpha(0)),
        shadowColor: WidgetStatePropertyAll(colors.page.withAlpha(0)),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      builder: (context, controller, child) => GlassActionBarButton(
        label: '视图与排序',
        icon: const Icon(AppIcons.viewOptions),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        SizedBox(
          width: width,
          child: GlassSurfaceGroup.isolated(
            variant: GlassVariant.menu,
            child: Glass(
              variant: GlassVariant.menu,
              radius: _panelRounded,
              padding: const EdgeInsets.all(DesignTokens.componentMenuPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * .65),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        container: true,
                        label: '排序',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (index, (value, title)) in const [
                              (FileSortKey.name, '名称'),
                              (FileSortKey.size, '大小'),
                              (FileSortKey.modified, '修改时间'),
                              (FileSortKey.type, '类型'),
                            ].indexed) ...[
                              if (index > 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal:
                                        DesignTokens.componentListRowPadding,
                                  ),
                                  child: SizedBox(
                                    height:
                                        DesignTokens.componentSeparatorHeight,
                                    child: ColoredBox(color: colors.separator),
                                  ),
                                ),
                              ChoiceRow<FileSortKey>(
                                value: value,
                                title: Text(title),
                                selected: value == sortKey,
                                onChanged: (value) {
                                  onSortKeyChanged(value);
                                  menu.close();
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spacingSm),
                      Semantics(
                        container: true,
                        label: '顺序',
                        child: ConnectSegmentedControl<bool>(
                          onGlass: true,
                          options: const [(true, '升序'), (false, '降序')],
                          selected: ascending,
                          onSelected: (value) {
                            onAscendingChanged(value);
                            menu.close();
                          },
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spacingSm),
                      Semantics(
                        container: true,
                        label: '布局',
                        child: ConnectSegmentedControl<FileViewMode>(
                          onGlass: true,
                          options: const [
                            (FileViewMode.list, '列表'),
                            (FileViewMode.grid, '宫格'),
                          ],
                          selected: viewMode,
                          onSelected: (value) {
                            onViewModeChanged(value);
                            menu.close();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
