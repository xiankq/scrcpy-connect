import 'package:material_ui/material_ui.dart';

const skeletonDelay = Duration(milliseconds: 150);
const skeletonCycle = Duration(milliseconds: 1800);
const contentArrivalDuration = Duration(milliseconds: 200);
const shortTransitionDuration = Duration(milliseconds: 180);
const shortTransitionCurve = Curves.easeInOut;
const panelOpenDuration = Duration(milliseconds: 260);
const panelCloseDuration = Duration(milliseconds: 200);
const panelCurve = Curves.easeOutCubic;

bool reduceMotionOf(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.reduceMotionOf(context);

/// A short desktop page transition keeps the window's navigation plane stable.
class DesktopPageTransitionsBuilder extends PageTransitionsBuilder {
  const DesktopPageTransitionsBuilder();

  @override
  Duration get transitionDuration => contentArrivalDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotionOf(context)) return child;
    final progress = animation.drive(CurveTween(curve: panelCurve));
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: progress.drive(
          Tween(begin: const Offset(.022, 0), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
