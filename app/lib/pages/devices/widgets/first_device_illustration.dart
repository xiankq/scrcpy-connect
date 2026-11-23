import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class FirstDeviceIllustration extends HookWidget {
  const FirstDeviceIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.reduceMotionOf(context) ||
        MediaQuery.disableAnimationsOf(context);
    final motion = useAnimationController(
      duration: const Duration(milliseconds: 320),
      initialValue: reduced ? 1 : 0,
    );
    useEffect(() {
      if (reduced) {
        motion.value = 1;
      } else {
        motion.forward();
      }
      return null;
    }, [motion, reduced]);

    // The artwork is arranged in the coordinates of Ardot node 12:1.
    const artWidth = 342.0;
    const artHeight = DesignTokens.componentEmptyDeviceIntroHeight;
    final background = Theme.of(context).brightness == Brightness.dark
        ? DesignTokens.colorAccentBlueSoftDark
        : DesignTokens.colorAccentBlueSoft;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          DesignTokens.componentEmptyDeviceIntroRounded,
        ),
        child: ColoredBox(
          color: background,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: artHeight),
            child: FittedBox(
              child: SizedBox(
                width: artWidth,
                height: artHeight,
                child: AnimatedBuilder(
                  animation: motion,
                  builder: (context, _) {
                    final t = reduced
                        ? 1.0
                        : Curves.easeOutCubic.transform(motion.value);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: lerpDouble(29, 39, t),
                          top: lerpDouble(219, 211, t),
                          child: Opacity(
                            opacity: lerpDouble(.17 / .23, 1, t)!,
                            child: Image.asset(
                              'assets/device/intro-card-shadow.png',
                              width: 157,
                            ),
                          ),
                        ),
                        Positioned(
                          left: lerpDouble(194, 191, t),
                          top: lerpDouble(220, 222, t),
                          child: Opacity(
                            opacity: lerpDouble(.20 / .28, 1, t)!,
                            child: Image.asset(
                              'assets/device/intro-phone-shadow.png',
                              width: 107,
                            ),
                          ),
                        ),
                        Positioned(
                          left: lerpDouble(36, 46, t),
                          top: lerpDouble(112, 104, t),
                          child: Transform.rotate(
                            alignment: Alignment.topLeft,
                            angle: (1 - t) * 2 * math.pi / 180,
                            child: Transform.translate(
                              offset: const Offset(-12.9181, 0),
                              child: Image.asset(
                                'assets/device/intro-card.png',
                                width: 159.8148,
                              ),
                            ),
                          ),
                        ),
                        for (final (x, y, size, color) in const [
                          (
                            168.0,
                            100.0,
                            5.0,
                            DesignTokens
                                .componentIntroSignalNearBackgroundColor,
                          ),
                          (
                            182.0,
                            104.0,
                            7.0,
                            DesignTokens
                                .componentIntroSignalMiddleBackgroundColor,
                          ),
                          (
                            197.0,
                            111.0,
                            8.0,
                            DesignTokens.colorConnectionSignal,
                          ),
                        ])
                          Positioned(
                            left: x,
                            top: y,
                            child: SizedBox.square(
                              dimension: size,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: lerpDouble(214, 213, t),
                          top: lerpDouble(28, 38, t),
                          child: Transform.rotate(
                            alignment: Alignment.topLeft,
                            angle: -(1 - t) * math.pi / 180,
                            child: Transform.translate(
                              offset: const Offset(0, -14.2355),
                              child: Image.asset(
                                'assets/device/intro-phone.png',
                                width: 117.7251,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
