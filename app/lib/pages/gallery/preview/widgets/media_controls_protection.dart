import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

enum MediaControlsEdge { top, bottom }

/// 媒体保护（design.md「材质」media-protection）：先以 `media-scrim` 托住媒体上的控件，
/// 再在 64 点内向内容区淡出。
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
                child: ColoredBox(
                  color: DesignTokens.componentMediaProtectionBackgroundColor,
                ),
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
                      ? [_scrim, _scrim.withAlpha(0)]
                      : [_scrim.withAlpha(0), _scrim],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _scrim = DesignTokens.componentMediaProtectionBackgroundColor;
