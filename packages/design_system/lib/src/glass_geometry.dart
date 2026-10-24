import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_tokens.g.dart';

// 先给合成器明确的矩形范围，再执行后端形状及模糊。
// 保留光学边缘和按压空间，避免采样无界祖先表面。
Widget boundGlassSampling(
  Widget child, {
  EdgeInsets expansion = const EdgeInsets.all(
    DesignTokens.componentGlassRefractionWidth,
  ),
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
    horizontal: math.max(
      DesignTokens.componentGlassRefractionWidth,
      size.width * fraction,
    ),
    vertical: math.max(
      DesignTokens.componentGlassRefractionWidth,
      size.height * fraction,
    ),
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
