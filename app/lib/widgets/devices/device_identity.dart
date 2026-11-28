import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';

/// 设备块（Ardot 37:710）上的状态，决定底色与状态点。
enum DeviceBlockState { connected, offline, connecting, needsAction, failed }

DeviceBlockState deviceBlockState(DeviceSnapshot device) =>
    switch (device.status) {
      .connected => DeviceBlockState.connected,
      .connecting || .checking || .reconnecting => DeviceBlockState.connecting,
      .unauthorized || .authorizing => DeviceBlockState.needsAction,
      .failed => DeviceBlockState.failed,
      .offline || .paired || .unknown => DeviceBlockState.offline,
    };

/// 设备块图形（Ardot 37:689「图形」28）。
const _deviceGlyphSize = 28.0;

/// 状态点外圈（Ardot 37:692：14 点状态点加 2 点 `card` 外描边；离线为 2.5 点 outline 空心环）。
const _statusDotSize = 14.0;
const _statusRing = 2.0;
const _offlineRing = 2.5;

/// 连接中状态点（Ardot 37:700：18 点 `card` 圆底内放 14 点线弧）。
const _connectingDotSize = 18.0;
const _connectingArcSize = 14.0;

/// 状态点距设备块右下的偏移（Ardot 37:692 位于 36,36，超出 52 点设备块 2 点）。
const _statusDotOverhang = DesignTokens.spacingXxs;

/// 工作台概览中的手机轮廓（Ardot 工作台概览 37:1626「手机轮廓」）。
const _showcaseWidth = 72.0;
const _showcaseHeight = 132.0;
const _showcaseRim = 2.0;
const _earpieceWidth = DesignTokens.spacingLg;
const _earpieceHeight = DesignTokens.spacingXs;
const _earpieceTop = 10.0;
const _showcaseGlyphSize = DesignTokens.spacingXxxl;

/// 只表示设备身份，不作为远端手机当前画面的预览。
///
/// 默认为 52 点设备块加状态点；[showcase] 为工作台概览中的手机轮廓。
class DeviceIdentity extends StatelessWidget {
  const DeviceIdentity({
    super.key,
    required this.device,
    this.compact = false,
    this.showcase = false,
    this.pane = false,
  });
  final DeviceSnapshot device;

  /// 保留给窄布局的调用方；设备块只有一种尺寸。
  final bool compact;
  final bool showcase;

  /// 保留给窗格布局的调用方；手机轮廓只有一种尺寸。
  final bool pane;

  @override
  Widget build(BuildContext context) {
    final state = deviceBlockState(device);
    return ExcludeSemantics(
      child: showcase
          ? _Showcase(state: state)
          : DeviceBlock(state: state, tablet: isTabletModel(device)),
    );
  }
}

// ADB provides model names for saved records. Known tablet families can
// use the tablet glyph while unknown models retain the handset glyph.
final _tabletModel = RegExp(
  r'\b(tablet|pad|tab)\b|\bSM-[TX]\d',
  caseSensitive: false,
);

bool isTabletModel(DeviceSnapshot device) =>
    _tabletModel.hasMatch(device.model ?? device.name ?? '');

/// 设备块（Ardot 37:710）：52 点圆角 16 方块与右下状态点，状态点向外超出 2 点。
///
/// 已连接、连接中、需处理用 `primary-container` 底，离线与失败用 `block` 底。
class DeviceBlock extends StatelessWidget {
  const DeviceBlock({super.key, required this.state, this.tablet = false});
  final DeviceBlockState state;
  final bool tablet;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final active = switch (state) {
      DeviceBlockState.connected ||
      DeviceBlockState.connecting ||
      DeviceBlockState.needsAction => true,
      DeviceBlockState.offline || DeviceBlockState.failed => false,
    };
    const dot = _statusDotSize;
    final Widget status = switch (state) {
      DeviceBlockState.connecting => Container(
        width: _connectingDotSize,
        height: _connectingDotSize,
        decoration: BoxDecoration(color: colors.card, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: ContentLoadingIndicator(
          size: _connectingArcSize,
          color: colors.primary,
        ),
      ),
      DeviceBlockState.offline => Container(
        width: dot,
        height: dot,
        decoration: BoxDecoration(
          color: colors.card,
          shape: BoxShape.circle,
          border: Border.all(color: colors.outline, width: _offlineRing),
        ),
      ),
      _ => Container(
        width: dot + 2 * _statusRing,
        height: dot + 2 * _statusRing,
        decoration: BoxDecoration(color: colors.card, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (state) {
              DeviceBlockState.connected => colors.success,
              DeviceBlockState.needsAction => colors.warning,
              _ => colors.destructive,
            },
          ),
        ),
      ),
    };
    final statusExtent = switch (state) {
      DeviceBlockState.connecting => _connectingDotSize,
      DeviceBlockState.offline => dot,
      _ => dot + 2 * _statusRing,
    };
    // 状态点中心对齐 Ardot 位置（43,43），即距设备块右下 9 点。
    const center =
        DesignTokens.componentDeviceTileSize -
        _statusDotOverhang -
        _statusDotSize / 2;
    return SizedBox.square(
      dimension: DesignTokens.componentDeviceTileSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: active ? colors.primaryContainer : colors.block,
                shape: const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(DesignTokens.componentDeviceTileRounded),
                  ),
                ),
              ),
              child: Icon(
                tablet ? LucideIcons.tablet : LucideIcons.smartphone,
                size: _deviceGlyphSize,
                color: active
                    ? colors.onPrimaryContainer
                    : colors.textSecondary,
              ),
            ),
          ),
          PositionedDirectional(
            start: center - statusExtent / 2,
            top: center - statusExtent / 2,
            child: status,
          ),
        ],
      ),
    );
  }
}

class _Showcase extends StatelessWidget {
  const _Showcase({required this.state});
  final DeviceBlockState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final glyph = switch (state) {
      DeviceBlockState.connecting => ContentLoadingIndicator(
        size: _showcaseGlyphSize,
        color: colors.primary,
      ),
      DeviceBlockState.connected => const Icon(
        LucideIcons.check,
        size: _showcaseGlyphSize,
        color: DesignTokens.colorAccentGreen,
      ),
      DeviceBlockState.failed => Icon(
        LucideIcons.circleX,
        size: _showcaseGlyphSize,
        color: colors.destructive,
      ),
      DeviceBlockState.needsAction => const Icon(
        LucideIcons.shieldAlert,
        size: _showcaseGlyphSize,
        color: DesignTokens.colorAccentAmber,
      ),
      DeviceBlockState.offline => const Icon(
        LucideIcons.unplug,
        size: _showcaseGlyphSize,
        color: DesignTokens.colorAccentGray,
      ),
    };
    return Container(
      width: _showcaseWidth,
      height: _showcaseHeight,
      decoration: ShapeDecoration(
        color: DesignTokens.colorDeviceScreen,
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(DesignTokens.roundedMd),
          ),
          side: BorderSide(color: colors.outline, width: _showcaseRim),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          glyph,
          Positioned(
            top: _earpieceTop,
            child: Container(
              width: _earpieceWidth,
              height: _earpieceHeight,
              decoration: ShapeDecoration(
                color: colors.outline,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String deviceConnectionLabel(DeviceSnapshot device) {
  if (device.status != .offline) return deviceStatusText(device);
  final seconds = device.lastSeen;
  if (seconds == null || seconds <= 0) return '离线 · 暂无最近连接时间';
  final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '离线 · 上次连接 ${time.year}/${two(time.month)}/${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
