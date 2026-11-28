import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';

import '../models/add_device_mode.dart';

export '../models/add_device_mode.dart';

/// 四项横排所需的最小宽度（按 1 倍字号计）；不足时改为两列（Ardot 41:730）。
const _singleRowMinWidth = 288.0;

/// 两列变体（Ardot「连接方式 · 200% 字号」41:730）：外角 28 = 项角 24 + 内距 4。
const _gridRounded = DesignTokens.roundedXxl;
const _gridItemRounded = DesignTokens.roundedXl;
const _gridGap = DesignTokens.componentSegmentedPadding;
const _gridItemPadding = EdgeInsets.symmetric(
  horizontal: DesignTokens.spacingSm,
  vertical: DesignTokens.spacingMd,
);

/// 添加设备的连接方式分段（Ardot 连接方式 37:2083）：图标在上、标签在下的 64 高分段，
/// 图标为 design.md「功能色」规定的彩色线形图形。窄窗或大字下改为两列。
class ConnectionModeSelector extends StatelessWidget {
  const ConnectionModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AddDeviceMode selected;
  final ValueChanged<AddDeviceMode> onChanged;

  static const _tabs = [
    (
      AddDeviceMode.pairing,
      '配对码',
      AppIcons.connectionPairing,
      DesignTokens.colorAccentGreen,
    ),
    (
      AddDeviceMode.qr,
      '扫码',
      AppIcons.connectionScan,
      DesignTokens.colorAccentPurple,
    ),
    (
      AddDeviceMode.usb,
      'USB',
      AppIcons.connectionUsb,
      DesignTokens.colorAccentOrange,
    ),
    (
      AddDeviceMode.ip,
      'IP 连接',
      AppIcons.connectionIp,
      DesignTokens.colorAccentBlue,
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      if (constraints.maxWidth / scale >= _singleRowMinWidth) {
        return ConnectSegmentedControl<AddDeviceMode>(
          onPage: true,
          options: [for (final (mode, label, _, _) in _tabs) (mode, label)],
          icons: [
            for (final (_, _, icon, color) in _tabs) (icon: icon, color: color),
          ],
          selected: selected,
          onSelected: onChanged,
        );
      }
      return _ModeGrid(selected: selected, onChanged: onChanged);
    },
  );
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.selected, required this.onChanged});

  final AddDeviceMode selected;
  final ValueChanged<AddDeviceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final duration = reduceMotionOf(context)
        ? Duration.zero
        : shortTransitionDuration;
    Widget item((AddDeviceMode, String, IconData, Color) tab) {
      final (mode, label, icon, color) = tab;
      final active = mode == selected;
      final foreground = active ? colors.onPrimary : colors.textSecondary;
      final select = active ? null : () => onChanged(mode);
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          inMutuallyExclusiveGroup: true,
          onTap: select,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: select,
            child: AnimatedContainer(
              duration: duration,
              curve: standardCurve,
              alignment: Alignment.center,
              padding: _gridItemPadding,
              decoration: ShapeDecoration(
                color: active ? colors.primary : colors.primary.withAlpha(0),
                shape: const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(_gridItemRounded),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: DesignTokens.componentBarGlyphSize,
                    color: active ? colors.onPrimary : color,
                  ),
                  const SizedBox(height: DesignTokens.spacingXxs),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: (active ? type.label : type.subheadline).copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final tabs = ConnectionModeSelector._tabs;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.card,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(Radius.circular(_gridRounded)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_gridGap),
        child: Column(
          children: [
            for (var row = 0; row < tabs.length; row += 2) ...[
              if (row > 0) const SizedBox(height: _gridGap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    item(tabs[row]),
                    const SizedBox(width: _gridGap),
                    item(tabs[row + 1]),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
