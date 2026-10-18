import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as liquid;

import 'src/design_tokens.g.dart';

export 'src/design_tokens.g.dart';

/// Semantic values mapped directly from designs/design.md.
abstract final class ConnectTokens {
  static const primary = DesignTokens.colorPrimary;
  static const blue = DesignTokens.colorAccentBlue;
  static const ink = DesignTokens.colorText;
  static const secondary = DesignTokens.colorSecondary;
  static const canvas = DesignTokens.colorCanvas;
  static const tint = DesignTokens.colorTint;
  static const coral = DesignTokens.colorAccentCoral;
  static const amber = DesignTokens.colorAccentAmber;
  static const mint = DesignTokens.colorAccentMint;
  static const danger = DesignTokens.colorDanger;
  static const radius = DesignTokens.roundedLg;
  static const glass = DesignTokens.colorGlass;
  static const glassDark = DesignTokens.colorGlassDark;
  static const glassBlur = DesignTokens.componentGlassBlur;
  static const glassRefractionIndex =
      DesignTokens.componentGlassRefractionIndex;
  static const glassRefractionWidth =
      DesignTokens.componentGlassRefractionWidth;
  static const glassDispersion = DesignTokens.componentGlassDispersion;
  static const glassMagnification = DesignTokens.componentGlassMagnification;
  static const glassSaturation = DesignTokens.componentGlassSaturation;
  static const glassPanel = DesignTokens.colorGlassPanel;
  static const glassPanelDark = DesignTokens.colorGlassPanelDark;
  static const glassReflection = DesignTokens.colorGlassReflection;
  static const glassReflectionDark = DesignTokens.colorGlassReflectionDark;
  static const glassEdge = DesignTokens.colorGlassEdge;
  static const glassEdgeDark = DesignTokens.colorGlassEdgeDark;
  static const shadow = DesignTokens.colorShadow;
  static const shadowDark = DesignTokens.colorShadowDark;
  static const shadowBlur = DesignTokens.componentGlassShadowBlur;
  static const shadowOffset = DesignTokens.componentGlassShadowOffset;

  static Color accent(BuildContext context, Color color) {
    if (Theme.of(context).brightness != Brightness.dark) return color;
    return switch (color) {
      primary => DesignTokens.colorPrimaryDark,
      blue => DesignTokens.colorAccentBlueDark,
      ink => DesignTokens.colorTextDark,
      coral => DesignTokens.colorAccentCoralDark,
      amber => DesignTokens.colorAccentAmberDark,
      mint => DesignTokens.colorAccentMintDark,
      danger => DesignTokens.colorDangerDark,
      _ => color,
    };
  }

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final foreground = dark ? DesignTokens.colorTextDark : ink;
    final surface = dark
        ? DesignTokens.colorSurfaceDark
        : DesignTokens.colorSurface;
    final container = dark ? DesignTokens.colorTintDark : tint;
    final colors = ColorScheme(
      brightness: brightness,
      primary: dark ? DesignTokens.colorPrimaryDark : DesignTokens.colorPrimary,
      onPrimary: dark
          ? DesignTokens.colorOnPrimaryDark
          : DesignTokens.colorOnPrimary,
      primaryContainer: container,
      onPrimaryContainer: foreground,
      primaryFixed: tint,
      primaryFixedDim: DesignTokens.colorMuted,
      onPrimaryFixed: ink,
      onPrimaryFixedVariant: secondary,
      secondary: dark ? DesignTokens.colorSecondaryDark : secondary,
      onSecondary: dark
          ? DesignTokens.colorOnPrimaryDark
          : DesignTokens.colorWhite,
      secondaryContainer: container,
      onSecondaryContainer: foreground,
      secondaryFixed: tint,
      secondaryFixedDim: DesignTokens.colorMuted,
      onSecondaryFixed: ink,
      onSecondaryFixedVariant: secondary,
      tertiary: dark ? DesignTokens.colorSecondaryDark : secondary,
      onTertiary: dark
          ? DesignTokens.colorOnPrimaryDark
          : DesignTokens.colorWhite,
      tertiaryContainer: container,
      onTertiaryContainer: foreground,
      tertiaryFixed: tint,
      tertiaryFixedDim: DesignTokens.colorMuted,
      onTertiaryFixed: ink,
      onTertiaryFixedVariant: secondary,
      error: dark ? DesignTokens.colorDangerDark : danger,
      onError: dark ? DesignTokens.colorOnDangerDark : DesignTokens.colorWhite,
      errorContainer: dark
          ? DesignTokens.colorDangerContainerDark
          : DesignTokens.colorDangerContainer,
      onErrorContainer: dark
          ? DesignTokens.colorOnDangerContainerDark
          : DesignTokens.colorOnDangerContainer,
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: dark ? DesignTokens.colorSecondaryDark : secondary,
      surfaceDim: dark ? DesignTokens.colorCanvasDark : DesignTokens.colorMuted,
      surfaceBright: dark
          ? DesignTokens.colorMutedDark
          : DesignTokens.colorWhite,
      surfaceContainerLowest: dark
          ? DesignTokens.colorCanvasDark
          : DesignTokens.colorWhite,
      surfaceContainerLow: dark
          ? DesignTokens.colorSurfaceLowDark
          : DesignTokens.colorSurfaceLow,
      surfaceContainer: dark ? DesignTokens.colorSurfaceDark : canvas,
      surfaceContainerHigh: dark
          ? DesignTokens.colorSurfaceHighDark
          : DesignTokens.colorSurfaceHigh,
      surfaceContainerHighest: container,
      outline: dark ? DesignTokens.colorOutlineDark : DesignTokens.colorOutline,
      outlineVariant: dark
          ? DesignTokens.colorMutedDark
          : DesignTokens.colorMuted,
      shadow: DesignTokens.colorBlack,
      scrim: DesignTokens.colorBlack,
      inverseSurface: dark
          ? DesignTokens.colorTextDark
          : DesignTokens.colorSurfaceDark,
      onInverseSurface: dark ? ink : DesignTokens.colorTextDark,
      inversePrimary: dark
          ? DesignTokens.colorPrimary
          : DesignTokens.colorPrimaryDark,
      surfaceTint: DesignTokens.colorTransparent,
    );
    final text = dark ? DesignTokens.colorTextDark : ink;
    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
      colorScheme: colors,
      scaffoldBackgroundColor: dark ? DesignTokens.colorCanvasDark : canvas,
      splashFactory: NoSplash.splashFactory,
      splashColor: DesignTokens.colorTransparent,
      highlightColor: DesignTokens.colorTransparent,
      hoverColor: foreground.withValues(
        alpha: DesignTokens.componentControlFeedbackOpacity,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: colors.primary,
        scaffoldBackgroundColor: dark ? DesignTokens.colorCanvasDark : canvas,
        barBackgroundColor: surface,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : DesignTokens.colorTransparent,
        ),
        checkColor: WidgetStatePropertyAll(colors.onPrimary),
        overlayColor: const WidgetStatePropertyAll(
          DesignTokens.colorTransparent,
        ),
        side: BorderSide(color: colors.outline),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.outline,
        ),
        overlayColor: const WidgetStatePropertyAll(
          DesignTokens.colorTransparent,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: const WidgetStatePropertyAll(null),
        thumbColor: const WidgetStatePropertyAll(DesignTokens.colorWhite),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.outlineVariant,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(
          DesignTokens.colorTransparent,
        ),
        overlayColor: const WidgetStatePropertyAll(
          DesignTokens.colorTransparent,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: DesignTokens.colorTransparent,
        elevation: DesignTokens.spacingZero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.roundedXl),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: DesignTokens.colorTransparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
        ),
      ),
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: DesignTokens.typographyDisplayFontSize,
          fontWeight: DesignTokens.typographyDisplayFontWeight,
          height: DesignTokens.typographyDisplayLineHeight,
          letterSpacing: DesignTokens.typographyDisplayLetterSpacing,
          color: text,
        ),
        headlineMedium: TextStyle(
          fontSize: DesignTokens.typographyTitleFontSize,
          fontWeight: DesignTokens.typographyTitleFontWeight,
          height: DesignTokens.typographyTitleLineHeight,
          letterSpacing: DesignTokens.typographyTitleLetterSpacing,
          color: text,
        ),
        titleLarge: TextStyle(
          fontSize: DesignTokens.typographyHeadingFontSize,
          fontWeight: DesignTokens.typographyHeadingFontWeight,
          height: DesignTokens.typographyHeadingLineHeight,
          letterSpacing: DesignTokens.typographyHeadingLetterSpacing,
          color: text,
        ),
        titleMedium: TextStyle(
          fontSize: DesignTokens.typographyBodyEmphasisFontSize,
          fontWeight: DesignTokens.typographyBodyEmphasisFontWeight,
          height: DesignTokens.typographyBodyEmphasisLineHeight,
          letterSpacing: DesignTokens.typographyBodyEmphasisLetterSpacing,
          color: text,
        ),
        bodyLarge: TextStyle(
          fontSize: DesignTokens.typographyBodyFontSize,
          fontWeight: DesignTokens.typographyBodyFontWeight,
          height: DesignTokens.typographyBodyLineHeight,
          letterSpacing: DesignTokens.typographyBodyLetterSpacing,
          color: text,
        ),
        bodyMedium: TextStyle(
          fontSize: DesignTokens.typographyBodyCompactFontSize,
          fontWeight: DesignTokens.typographyBodyCompactFontWeight,
          height: DesignTokens.typographyBodyCompactLineHeight,
          letterSpacing: DesignTokens.typographyBodyCompactLetterSpacing,
          color: text,
        ),
        bodySmall: TextStyle(
          fontSize: DesignTokens.typographyCaptionFontSize,
          fontWeight: DesignTokens.typographyCaptionFontWeight,
          height: DesignTokens.typographyCaptionLineHeight,
          letterSpacing: DesignTokens.typographyCaptionLetterSpacing,
          color: dark ? DesignTokens.colorSecondaryDark : secondary,
        ),
        labelLarge: TextStyle(
          fontSize: DesignTokens.typographyLabelFontSize,
          fontWeight: DesignTokens.typographyLabelFontWeight,
          height: DesignTokens.typographyLabelLineHeight,
          letterSpacing: DesignTokens.typographyLabelLetterSpacing,
          color: text,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: DesignTokens.colorTransparent,
        foregroundColor: text,
        surfaceTintColor: DesignTokens.colorTransparent,
        elevation: DesignTokens.spacingZero,
        scrolledUnderElevation: DesignTokens.spacingZero,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: DesignTokens.colorTransparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: DesignTokens.colorTransparent,
              ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            DesignTokens.componentButtonPrimaryHeight,
            DesignTokens.componentButtonPrimaryHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
          ),
          foregroundColor: colors.onPrimary,
          backgroundColor: dark
              ? DesignTokens.colorPrimaryActionDark
              : DesignTokens.colorPrimaryAction,
          textStyle: const TextStyle(
            fontSize: DesignTokens.typographyBodyFontSize,
            fontWeight: DesignTokens.typographyBodyEmphasisFontWeight,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            DesignTokens.componentButtonPrimaryHeight,
            DesignTokens.componentButtonPrimaryHeight,
          ),
          foregroundColor: colors.primary,
          side: BorderSide.none,
          backgroundColor: colors.surfaceContainerHigh,
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            DesignTokens.componentIconButtonSize,
            DesignTokens.componentIconButtonSize,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            DesignTokens.componentIconButtonSize,
            DesignTokens.componentIconButtonSize,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: DesignTokens.componentRowHeight,
        horizontalTitleGap: DesignTokens.componentRowGap,
        minVerticalPadding: DesignTokens.componentRowVerticalPadding,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(DesignTokens.spacingMd),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DesignTokens.componentSheetRounded),
          ),
        ),
      ),
      dividerColor: dark
          ? DesignTokens.colorMutedDark
          : DesignTokens.colorMuted,
    );
  }
}

class GlassPreferences extends InheritedWidget {
  const GlassPreferences({
    super.key,
    required this.reduceTransparency,
    required super.child,
  });
  final bool reduceTransparency;
  static bool reduced(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassPreferences>()
          ?.reduceTransparency ??
      false;
  @override
  bool updateShouldNotify(GlassPreferences oldWidget) =>
      reduceTransparency != oldWidget.reduceTransparency;
}

/// Regular separates floating controls from content; clear belongs over media.
enum GlassVariant { regular, clear }

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = DesignTokens.roundedLg,
    this.padding = EdgeInsets.zero,
    this.solid = false,
    this.variant = GlassVariant.regular,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool solid;
  final GlassVariant variant;

  /// The package's standalone shader consumes this one optical profile.
  static liquid.LiquidGlassStyle optics({
    required Brightness brightness,
    GlassVariant variant = GlassVariant.regular,
    double radius = DesignTokens.roundedLg,
  }) {
    final dark = brightness == Brightness.dark;
    final clear = variant == GlassVariant.clear;
    return liquid.LiquidGlassStyle(
      shape: liquid.LiquidGlassShape.roundedRectangle(cornerRadius: radius),
      refractionIndex: ConnectTokens.glassRefractionIndex,
      refractionWidth: ConnectTokens.glassRefractionWidth,
      dispersion: ConnectTokens.glassDispersion,
      magnification: ConnectTokens.glassMagnification,
      saturation: ConnectTokens.glassSaturation,
      blur: clear
          ? DesignTokens.componentGlassClearBlur
          : ConnectTokens.glassBlur,
      color: clear
          ? (dark
                ? DesignTokens.colorGlassClearDark
                : DesignTokens.colorGlassClear)
          : (dark ? ConnectTokens.glassDark : ConnectTokens.glass),
      specular: const liquid.LiquidGlassLight.specular(
        thickness: DesignTokens.componentGlassSpecularThickness,
        sharpness: DesignTokens.componentGlassSpecularSharpness,
        angle: DesignTokens.componentGlassAngle,
        spread: DesignTokens.componentGlassSpecularSpread,
        intensity: DesignTokens.componentGlassSpecularIntensity,
        oppositeIntensity: DesignTokens.componentGlassSpecularOppositeIntensity,
      ),
      glow: const liquid.LiquidGlassLight.glow(
        thickness: DesignTokens.componentGlassGlowThickness,
        angle: DesignTokens.componentGlassGlowAngle,
        spread: DesignTokens.componentGlassGlowSpread,
        intensity: DesignTokens.componentGlassGlowIntensity,
        oppositeIntensity: DesignTokens.componentGlassGlowOppositeIntensity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque =
        solid ||
        GlassPreferences.reduced(context) ||
        MediaQuery.highContrastOf(context);
    final style = optics(
      brightness: Theme.of(context).brightness,
      variant: variant,
      radius: radius,
    );
    final base = style.color;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque ? Theme.of(context).colorScheme.surface : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: opaque
              ? Theme.of(context).colorScheme.outline
              : (dark ? ConnectTokens.glassEdgeDark : ConnectTokens.glassEdge),
        ),
        gradient: opaque
            ? null
            : RadialGradient(
                radius: 1,
                transform: const _GlassProtectionTransform(),
                // A shallow, neutral falloff keeps labels readable without
                // painting a gray reflective band around the control.
                colors: [
                  if (variant == GlassVariant.clear)
                    dark
                        ? DesignTokens.colorGlassClearPanelDark
                        : DesignTokens.colorGlassClearPanel
                  else
                    dark
                        ? ConnectTokens.glassPanelDark
                        : ConnectTokens.glassPanel,
                  dark
                      ? ConnectTokens.glassReflectionDark
                      : ConnectTokens.glassReflection,
                ],
              ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    final Widget surface;
    if (opaque) {
      // Accessibility preferences remove the optical work, rather than only
      // hiding a running shader behind an opaque decoration.
      surface = content;
    } else if (ImageFilter.isShaderFilterSupported) {
      surface = liquid.LiquidGlassLens(
        // No capture view, background screenshots or second optical engine.
        style: style,
        child: content,
      );
    } else {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: style.blur, sigmaY: style.blur),
        child: ColoredBox(color: base, child: content),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: dark ? ConnectTokens.shadowDark : ConnectTokens.shadow,
            blurRadius: ConnectTokens.shadowBlur,
            offset: const Offset(0, ConnectTokens.shadowOffset),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: surface,
      ),
    );
  }
}

// Keep protection elliptical on wide navigation and narrow handles. Scaling
// from the shortest side makes the falloff relative to the whole surface.
class _GlassProtectionTransform extends GradientTransform {
  const _GlassProtectionTransform();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    if (bounds.shortestSide <= 0) return null;
    final sx = bounds.width / bounds.shortestSide;
    final sy = bounds.height / bounds.shortestSide;
    return Matrix4.diagonal3Values(sx, sy, 1)..setTranslationRaw(
      bounds.center.dx * (1 - sx),
      bounds.center.dy * (1 - sy),
      0,
    );
  }
}

/// One floating control. The visual and semantic hit area are at least 44.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.variant = GlassVariant.regular,
  });
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Glass(
      radius: DesignTokens.roundedFull,
      variant: variant,
      child: CupertinoButton(
        padding: const EdgeInsets.all(DesignTokens.spacingSm),
        minimumSize: const Size.square(DesignTokens.componentIconButtonSize),
        onPressed: onPressed,
        child: IconTheme(
          data: IconThemeData(
            size: DesignTokens.componentIconSize,
            color: onPressed == null
                ? Theme.of(context).disabledColor
                : color ?? Theme.of(context).colorScheme.onSurface,
          ),
          child: icon,
        ),
      ),
    ),
  );
}

/// A single material groups related toolbar controls; children stay unglazed.
class GlassToolbarGroup extends StatelessWidget {
  const GlassToolbarGroup({
    super.key,
    required this.children,
    this.variant = GlassVariant.regular,
  });
  final List<Widget> children;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) {
    final compactStyle = IconButton.styleFrom(
      minimumSize: const Size.square(DesignTokens.componentIconButtonSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    return Glass(
      radius: DesignTokens.roundedFull,
      variant: variant,
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style:
              IconButtonTheme.of(context).style?.merge(compactStyle) ??
              compactStyle,
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

@immutable
class GlassDestination {
  const GlassDestination({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Floating navigation with one shallow selection plane and scalable labels.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(destinations.length > 1),
       assert(selectedIndex >= 0 && selectedIndex < destinations.length);
  final List<GlassDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque =
        GlassPreferences.reduced(context) || MediaQuery.highContrastOf(context);
    return Glass(
      radius: DesignTokens.roundedFull,
      padding: const EdgeInsets.all(DesignTokens.spacingXxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < destinations.length; index++)
            Expanded(
              child: Semantics(
                selected: index == selectedIndex,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: index == selectedIndex
                        ? (opaque
                              ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh
                              : dark
                              ? DesignTokens.colorGlassSelectedDark
                              : DesignTokens.colorGlassSelected)
                        : DesignTokens.colorTransparent,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.roundedFull,
                    ),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingXxs,
                      vertical: DesignTokens.spacingXs,
                    ),
                    minimumSize: const Size.square(
                      DesignTokens.componentIconButtonSize,
                    ),
                    onPressed: () => onSelected(index),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          destinations[index].icon,
                          size: DesignTokens.componentIconSize,
                          color: index == selectedIndex
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: DesignTokens.spacingMicro),
                        Text(
                          destinations[index].label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                color: index == selectedIndex
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// iOS switch geometry and feedback with the app's functional tint.
class ConnectSwitch extends StatelessWidget {
  const ConnectSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CupertinoSwitch(
    value: value,
    onChanged: onChanged,
    activeTrackColor: Theme.of(context).colorScheme.primary,
  );
}

class ContentPanel extends StatelessWidget {
  const ContentPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DesignTokens.spacingMd),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(
      DesignTokens.componentContentPanelRounded,
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class FeatureIcon extends StatelessWidget {
  const FeatureIcon(
    this.icon, {
    super.key,
    this.color = ConnectTokens.primary,
    this.size = DesignTokens.componentFeatureIconSize,
  });
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final resolved = ConnectTokens.accent(context, color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: resolved.withValues(
          alpha: DesignTokens.componentFeatureIconOpacity,
        ),
        borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
      ),
      child: Icon(
        icon,
        color: resolved,
        size: DesignTokens.componentIconFeatureSize,
      ),
    );
  }
}

class EmptyContent extends StatelessWidget {
  const EmptyContent({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentEmptyContentPadding,
          vertical: DesignTokens.componentEmptyContentVerticalPadding,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesignTokens.componentEmptyContentWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FeatureIcon(
                icon,
                size: DesignTokens.componentEmptyContentIconSize,
              ),
              const SizedBox(height: DesignTokens.componentEmptyContentGap),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(
                height: DesignTokens.componentEmptyContentMessageGapHeight,
              ),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: DesignTokens.componentEmptyContentGap),
                action!,
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
