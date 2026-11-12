import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// 图标属于目标设备与包名，不使用主控设备的图标集合。
class PhoneAppIcon extends ConsumerWidget {
  const PhoneAppIcon({
    super.key,
    required this.deviceId,
    required this.packageName,
    this.refreshKey,
    this.userId,
    this.size = DesignTokens.componentAppIconSize,
  });
  final String deviceId;
  final String packageName;
  final Object? refreshKey;
  final int? userId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(
      deviceAppIconProvider((
        deviceId: deviceId,
        packageName: packageName,
        userId: userId,
      ), revision: refreshKey),
    );
    final icon = result.asData?.value;
    Widget placeholder() => Icon(
      !result.isLoading ? LucideIcons.imageOff : LucideIcons.image,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      size: DesignTokens.componentIconSize,
      semanticLabel: !result.isLoading ? '图标暂不可用' : '正在读取图标',
    );
    return SizedBox.square(
      dimension: size,
      child: icon == null
          ? Center(child: placeholder())
          : Image.memory(
              icon.bytes,
              fit: BoxFit.contain,
              gaplessPlayback: false,
              errorBuilder: (_, _, _) => Center(child: placeholder()),
            ),
    );
  }
}
