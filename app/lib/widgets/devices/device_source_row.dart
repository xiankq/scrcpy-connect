import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';

/// 来源图形与 footnote 行高（18）对齐的大小。
const _sourceGlyphSize = DesignTokens.componentChevronSize;

/// 内容来源设备：`footnote` + `text-secondary`，起始手机图形。
class DeviceSourceRow extends StatelessWidget {
  const DeviceSourceRow({
    super.key,
    required this.device,
    this.padding = EdgeInsets.zero,
  });

  final DeviceSnapshot device;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Icon(
            LucideIcons.smartphone,
            size: _sourceGlyphSize,
            color: colors.textSecondary,
          ),
          const SizedBox(width: DesignTokens.spacingXs),
          Expanded(
            child: Text(
              deviceName(device),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.of(context).footnote
                  .copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
