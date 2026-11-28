import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// 边缘折射带宽度，见 designs/design.md「玻璃配方」：约 min(20, 高/4)。
const glassRefractionWidth = DesignTokens.componentGlassRegularRefractionWidth;

// 先给合成器明确的矩形范围，再执行后端形状及模糊。
// 保留光学边缘和按压空间，避免采样无界祖先表面。
Widget boundGlassSampling(
  Widget child, {
  EdgeInsets expansion = const EdgeInsets.all(glassRefractionWidth),
}) => ClipRect(
  clipBehavior: Clip.hardEdge,
  clipper: _GlassSamplingClipper(expansion),
  child: child,
);

EdgeInsets glassMotionExpansion(
  Size size,
  double maximumScale, {
  bool centered = false,
}) {
  final fraction = (maximumScale - 1) / (centered ? 2 : 1);
  return EdgeInsets.symmetric(
    horizontal: math.max(glassRefractionWidth, size.width * fraction),
    vertical: math.max(glassRefractionWidth, size.height * fraction),
  );
}

class _GlassSamplingClipper extends CustomClipper<Rect> {
  const _GlassSamplingClipper(this.expansion);
  final EdgeInsets expansion;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -expansion.left,
    -expansion.top,
    size.width + expansion.right,
    size.height + expansion.bottom,
  );
  @override
  bool shouldReclip(_GlassSamplingClipper oldClipper) =>
      oldClipper.expansion != expansion;
}
