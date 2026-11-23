import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/motion.dart';

/// Fades a newly arrived state in place, preserving the viewport and its input.
class ContentArrival extends HookWidget {
  const ContentArrival({
    super.key,
    required this.state,
    required this.child,
    this.waiting = false,
    this.sliver = false,
  });

  final Object state;
  final Widget child;
  final bool waiting, sliver;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotionOf(context);
    final previous = usePrevious(state);
    final animation = useAnimationController(
      initialValue: 1,
      duration: contentArrivalDuration,
    );
    useEffect(() {
      if (reduced || waiting) {
        animation.value = 1;
      } else if (previous != null && previous != state) {
        animation.forward(from: 0.28);
      }
      return null;
    }, [state, waiting, reduced]);
    return sliver
        ? SliverFadeTransition(opacity: animation, sliver: child)
        : FadeTransition(opacity: animation, child: child);
  }
}
