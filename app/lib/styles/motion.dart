import 'package:material_ui/material_ui.dart';

// 数值见 designs/interaction-motion.md「时长与曲线」「等待与状态切换」。
const skeletonDelay = Duration(milliseconds: 150);
const skeletonCycle = Duration(milliseconds: 1600);
const pageLoaderDelay = Duration(milliseconds: 400);
const contentArrivalDuration = Duration(milliseconds: 200);
const shortTransitionDuration = Duration(milliseconds: 200);
const regularTransitionDuration = Duration(milliseconds: 300);
const pressReleaseDuration = Duration(milliseconds: 250);
const pressDelay = Duration(milliseconds: 150);

/// 标准曲线 (0.2, 0, 0, 1)。
const standardCurve = Cubic(0.2, 0, 0, 1);

/// 进入曲线 (0.05, 0.7, 0.1, 1)。
const enterCurve = Cubic(0.05, 0.7, 0.1, 1);

const shortTransitionCurve = standardCurve;
const panelOpenDuration = regularTransitionDuration;
const panelCloseDuration = shortTransitionDuration;
const panelCurve = enterCurve;

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
