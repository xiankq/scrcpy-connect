import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/page_loader.dart';
import 'package:scrcpy_connect/widgets/soft_glow.dart';

/// 打开手机屏幕的阶段（Ardot R1 2:1065、9:858「阶段」卡片）。
enum RemoteOpeningStepState { done, current, pending, failed }

typedef RemoteOpeningStep = ({String label, RemoteOpeningStepState state});

/// 按呈现状态推出阶段：已连接 → 启动画面服务 → 接收首帧。
///
/// 只用呈现已有的区分：启动请求未返回（`connecting`）时停在画面服务；已绑定纹理后等待首帧。
/// 进入远控即已持有设备连接，第一步恒为完成。
List<RemoteOpeningStep> remoteOpeningSteps(
  RemotePresentation presentation, {
  required String deviceLabel,
  required bool failed,
}) {
  final serviceReady =
      presentation.session?.textureId != null &&
      (failed || !presentation.connecting);
  return [
    (label: '已连接 $deviceLabel', state: RemoteOpeningStepState.done),
    serviceReady
        ? (label: '已启动画面服务', state: RemoteOpeningStepState.done)
        : failed
        ? (label: '未能启动画面服务', state: RemoteOpeningStepState.failed)
        : (label: '正在启动画面服务…', state: RemoteOpeningStepState.current),
    !serviceReady
        ? (label: '接收首帧画面', state: RemoteOpeningStepState.pending)
        : failed
        ? (label: '未收到首帧画面', state: RemoteOpeningStepState.failed)
        : (label: '正在接收首帧画面…', state: RemoteOpeningStepState.current),
  ];
}

/// 首帧等待面：`page` 底，手机示意内为整页加载形状，下方为标题、设备与阶段卡片。
///
/// 形状等待超过 400 毫秒才出现；[animating] 为假时形状停在原相位并降到 38%，再次开始时
/// 从原相位继续。[failure] 不为空时原位换成失败内容，加载相位仍保留。
class RemoteOpeningView extends HookWidget {
  const RemoteOpeningView({
    super.key,
    required this.semanticsLabel,
    required this.title,
    required this.detail,
    required this.steps,
    this.animating = true,
    this.failure,
  });

  final String semanticsLabel;
  final String title;
  final String detail;
  final List<RemoteOpeningStep> steps;
  final bool animating;
  final Widget? failure;

  @override
  Widget build(BuildContext context) {
    final revealed = useState(false);
    useEffect(() {
      final timer = Timer(pageLoaderDelay, () => revealed.value = true);
      return timer.cancel;
    }, const []);
    final lifecycle = useAppLifecycleState();
    final reduceMotion = reduceMotionOf(context);
    final running =
        revealed.value &&
        animating &&
        failure == null &&
        !reduceMotion &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.isCurrentOf(context) != false &&
        TickerMode.valuesOf(context).enabled;
    final phase = useAnimationController(duration: pageLoaderCycle);
    useEffect(() {
      // repeat 从当前相位继续，停止时保留相位。
      if (running) {
        phase.repeat();
      } else {
        phase.stop();
      }
      return null;
    }, [phase, running]);
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.page),
        if (failure case final failure?)
          failure
        else
          Semantics(
            container: true,
            label: semanticsLabel,
            liveRegion: true,
            child: ExcludeSemantics(
              child: RemoteOpeningLayout(
                phone: RemotePhoneMock(
                  glow: true,
                  child: SizedBox.fromSize(
                    size: _loaderSize,
                    child: revealed.value
                        ? LoaderShapes(progress: phase, stopped: !animating)
                        : null,
                  ),
                ),
                title: title,
                detail: Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: type.subheadline.copyWith(color: colors.textSecondary),
                ),
                steps: steps,
              ),
            ),
          ),
      ],
    );
  }
}

/// 手机示意中的加载形状按 160×96 等比缩到示意屏内。
const _loaderSize = Size(140, 84);

/// 手机示意（Ardot 44:43）：168×332、圆角 34、`device-screen` 底与 `accent-gray` 描边，
/// 顶部 40×6 听筒；[glow] 时身后为 220×300、模糊 90 的主色光晕（44:42）。
class RemotePhoneMock extends StatelessWidget {
  const RemotePhoneMock({super.key, required this.child, this.glow = false});

  final Widget child;
  final bool glow;

  static const size = Size(168, 332);
  static const _speaker = Size(40, 6);
  static const _speakerTop = 12.0;
  static const _glowSize = Size(220, 300);
  static const _glowBlur = 90.0;
  static const _glowOpacity = .32;

  /// 光晕中心比示意中心低 18（44:42 位于 y 190，示意位于 y 156）。
  static const _glowOffset = 18.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final phone = DecoratedBox(
      decoration: const ShapeDecoration(
        color: DesignTokens.colorDeviceScreen,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.roundedAlert),
          ),
          side: BorderSide(color: DesignTokens.colorAccentGray),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: _speakerTop,
            child: Container(
              width: _speaker.width,
              height: _speaker.height,
              decoration: const ShapeDecoration(
                color: DesignTokens.colorAccentGray,
                shape: StadiumBorder(),
              ),
            ),
          ),
          child,
        ],
      ),
    );
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (glow)
            Positioned(
              left: (size.width - _glowSize.width) / 2 - _glowBlur,
              top:
                  (size.height - _glowSize.height) / 2 +
                  _glowOffset -
                  _glowBlur,
              width: _glowSize.width + 2 * _glowBlur,
              height: _glowSize.height + 2 * _glowBlur,
              child: SoftGlow(
                color: colors.primary.withValues(alpha: _glowOpacity),
                blur: _glowBlur,
              ),
            ),
          Positioned.fill(child: phone),
        ],
      ),
    );
  }
}

/// 打开手机屏幕的页面结构：手机示意、标题、说明、阶段卡片与底部动作。
///
/// 内容最宽 400 居中；矮而宽的窗口把示意放在起始侧，文字与阶段放在另一侧；
/// 高度不足时示意等比缩小，内容仍可滚动。
class RemoteOpeningLayout extends StatelessWidget {
  const RemoteOpeningLayout({
    super.key,
    required this.phone,
    required this.title,
    required this.detail,
    required this.steps,
    this.footer,
    this.scrollKey,
  });

  final Widget phone;
  final String title;
  final Widget detail;
  final List<RemoteOpeningStep> steps;
  final Widget? footer;
  final Key? scrollKey;

  /// 内容最宽 400（画板 402 宽减边距后约 370）。
  static const _maxWidth = 400.0;

  /// 低于此高度且宽大于高时改为左右排列。
  static const _sideBySideHeight = 560.0;

  /// 竖排时示意以外的内容预留高度，剩余高度决定示意缩放。
  static const _textReserve = 300.0;

  /// 示意最多缩到一半。
  static const _minScale = .5;

  /// 底部动作的预留高度（停靠按钮 48 与上方间距）。
  static const _footerReserve = 64.0;

  @override
  Widget build(BuildContext context) {
    final type = AppTypography.of(context);
    final safe = MediaQuery.paddingOf(context);
    // 首帧等待的页头（关闭 + 标题）在安全区下占 72；侧边工具栏时页头不在顶部。
    final header = liquid.GlassVerticalBar.maybeOf(context) == null
        ? DesignTokens.componentPageBarHeight
        : 0.0;
    final top = safe.top + header + DesignTokens.spacingXl;
    final bottom = safe.bottom + DesignTokens.spacingSm;
    final sides = EdgeInsets.only(
      left: safe.left + DesignTokens.spacingLg,
      right: safe.right + DesignTokens.spacingLg,
    );
    final heading = [
      Text(title, textAlign: TextAlign.center, style: type.title3),
      const SizedBox(height: DesignTokens.spacingXs),
      detail,
      const SizedBox(height: DesignTokens.spacingXl),
      RemoteOpeningSteps(steps: steps),
    ];
    // 底部动作固定在安全区上方，内容在其上滚动，窄窗大字时重试仍可直接点按。
    final dock = footer == null
        ? null
        : Padding(
            padding: EdgeInsets.only(
              top: DesignTokens.spacingLg,
              bottom: bottom,
            ),
            child: footer,
          );
    final contentBottom = dock == null ? bottom : DesignTokens.spacingSm;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight - top - bottom;
        Widget scaled(double available) {
          final scale = (available / RemotePhoneMock.size.height).clamp(
            _minScale,
            1.0,
          );
          return SizedBox.fromSize(
            size: RemotePhoneMock.size * scale,
            child: FittedBox(child: phone),
          );
        }

        if (constraints.maxWidth > constraints.maxHeight &&
            constraints.maxHeight < _sideBySideHeight) {
          return Padding(
            padding: sides.copyWith(top: top),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: DesignTokens.spacingXxxl,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: bottom),
                  child: scaled(height),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
                    child: Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) => SingleChildScrollView(
                              key: scrollKey,
                              padding: EdgeInsets.only(bottom: contentBottom),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: (box.maxHeight - contentBottom)
                                      .clamp(0, double.infinity),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: heading,
                                ),
                              ),
                            ),
                          ),
                        ),
                        ?dock,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        Widget column(Widget child) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: child,
          ),
        );
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: scrollKey,
                padding: sides.copyWith(top: top, bottom: contentBottom),
                child: column(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: scaled(
                          height -
                              _textReserve -
                              (dock == null ? 0 : _footerReserve),
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spacingXxl),
                      ...heading,
                    ],
                  ),
                ),
              ),
            ),
            if (dock != null) Padding(padding: sides, child: column(dock)),
          ],
        );
      },
    );
  }
}

/// 阶段卡片（Ardot 44:48）：`card` 底、圆角 24、内距 16/6；每行至少 44 高，图形 20、间距 12。
/// 完成为 `success` 勾，进行中为旋转的 `primary` 圈与正文色加粗，待开始为虚线圈，失败为 `error`。
class RemoteOpeningSteps extends HookWidget {
  const RemoteOpeningSteps({super.key, required this.steps});

  final List<RemoteOpeningStep> steps;

  static const _rowHeight = 44.0;
  static const _spinCycle = Duration(milliseconds: 1000);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final spinning =
        steps.any((step) => step.state == RemoteOpeningStepState.current) &&
        !reduceMotionOf(context) &&
        TickerMode.valuesOf(context).enabled;
    final spin = useAnimationController(duration: _spinCycle);
    useEffect(() {
      if (spinning) {
        spin.repeat();
      } else {
        spin.stop();
      }
      return null;
    }, [spin, spinning]);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.card,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentListGroupRounded),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingLg,
          vertical: DesignTokens.spacingXs + DesignTokens.spacingXxs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final step in steps)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _rowHeight),
                child: Row(
                  spacing: DesignTokens.spacingMd,
                  children: [
                    switch (step.state) {
                      RemoteOpeningStepState.done => Icon(
                        LucideIcons.circleCheck,
                        size: DesignTokens.componentSectionGlyphSize,
                        color: colors.success,
                      ),
                      RemoteOpeningStepState.current => RotationTransition(
                        turns: spin,
                        child: Icon(
                          LucideIcons.loaderCircle,
                          size: DesignTokens.componentSectionGlyphSize,
                          color: colors.primary,
                        ),
                      ),
                      RemoteOpeningStepState.pending => Icon(
                        LucideIcons.circleDashed,
                        size: DesignTokens.componentSectionGlyphSize,
                        color: colors.textSecondary,
                      ),
                      RemoteOpeningStepState.failed => Icon(
                        LucideIcons.circleX,
                        size: DesignTokens.componentSectionGlyphSize,
                        color: colors.error,
                      ),
                    },
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.spacingSm,
                        ),
                        child: Text(
                          step.label,
                          style: switch (step.state) {
                            RemoteOpeningStepState.current =>
                              type.subheadline.copyWith(
                                color: colors.text,
                                fontWeight: FontWeight.w600,
                              ),
                            RemoteOpeningStepState.failed =>
                              type.subheadline.copyWith(
                                color: colors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            _ => type.subheadline.copyWith(
                              color: colors.textSecondary,
                            ),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 失败标记（Ardot 44:61/44:62）：72 点 `error-container` 圆，`on-error-container` 警示图形 36。
class RemoteOpeningFailureMark extends StatelessWidget {
  const RemoteOpeningFailureMark({super.key});

  static const _size = 72.0;
  static const _glyph = 36.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.errorContainer,
      ),
      child: Icon(
        LucideIcons.circleAlert,
        size: _glyph,
        color: colors.onErrorContainer,
      ),
    );
  }
}
