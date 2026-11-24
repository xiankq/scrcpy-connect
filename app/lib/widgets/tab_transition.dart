import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/motion.dart';

/// Crossfades full-size tab panes while retaining their scroll and route state.
class TabPaneStack extends StatelessWidget {
  const TabPaneStack({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotionOf(context)
        ? Duration.zero
        : shortTransitionDuration;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final (position, child) in children.indexed)
          TweenAnimationBuilder<double>(
            tween: Tween(end: position == index ? 1.0 : 0.0),
            duration: duration,
            curve: shortTransitionCurve,
            builder: (context, opacity, child) => Offstage(
              offstage: opacity == 0 && position != index,
              child: Opacity(opacity: opacity, child: child),
            ),
            child: _ActiveTab(
              active: position == index,
              child: TickerMode(enabled: position == index, child: child),
            ),
          ),
      ],
    );
  }
}

/// Crossfades a variable-height tab body in a shared scroll view.
class TabContent extends StatelessWidget {
  const TabContent({super.key, required this.child});

  /// Give each tab body a distinct key.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotionOf(context)
        ? Duration.zero
        : shortTransitionDuration;
    return ClipRect(
      child: AnimatedSize(
        duration: duration,
        curve: shortTransitionCurve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: shortTransitionCurve,
          switchOutCurve: shortTransitionCurve,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              for (final child in [
                if (duration != Duration.zero) ...previous,
                ?current,
              ])
                Positioned(
                  key: child.key,
                  top: child == current ? null : 0,
                  left: child == current ? null : 0,
                  right: child == current ? null : 0,
                  child: _ActiveTab(
                    active: child == current,
                    child: TickerMode(enabled: child == current, child: child),
                  ),
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: !active,
    child: ExcludeSemantics(
      excluding: !active,
      child: IgnorePointer(ignoring: !active, child: child),
    ),
  );
}
