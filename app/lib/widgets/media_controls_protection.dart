import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

enum MediaControlsEdge { top, bottom }

/// 先保护实际媒体控件，再向内容区淡出。
class MediaControlsProtection extends StatelessWidget {
  const MediaControlsProtection({
    super.key,
    required this.child,
    this.edge = MediaControlsEdge.top,
  });

  final Widget child;
  final MediaControlsEdge edge;

  @override
  Widget build(BuildContext context) {
    final top = edge == MediaControlsEdge.top;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      verticalDirection: top ? VerticalDirection.down : VerticalDirection.up,
      children: [
        Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: DesignTokens.colorMediaShade),
              ),
            ),
            child,
          ],
        ),
        IgnorePointer(
          child: SizedBox(
            height: DesignTokens.componentMediaProtectionHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: top
                      ? const [
                          DesignTokens.colorMediaShade,
                          DesignTokens.colorTransparent,
                        ]
                      : const [
                          DesignTokens.colorTransparent,
                          DesignTokens.colorMediaShade,
                        ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
