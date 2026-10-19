import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

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
    final platformLabelFamily = ThemeData(brightness: brightness)
        .textTheme
        .labelLarge
        ?.fontFamily;
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
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          textStyle: TextStyle(
            // Match the platform family used by the rest of ThemeData.
            fontFamily: platformLabelFamily,
            fontSize: DesignTokens.componentButtonPrimaryTypography.fontSize,
            fontWeight:
                DesignTokens.componentButtonPrimaryTypography.fontWeight,
            height: DesignTokens.componentButtonPrimaryTypography.height,
            letterSpacing:
                DesignTokens.componentButtonPrimaryTypography.letterSpacing,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(
            DesignTokens.componentButtonSecondaryHeight,
            DesignTokens.componentButtonSecondaryHeight,
          ),
          foregroundColor: dark
              ? DesignTokens.componentButtonSecondaryDarkTextColor
              : DesignTokens.componentButtonSecondaryTextColor,
          side: BorderSide.none,
          backgroundColor: dark
              ? DesignTokens.componentButtonSecondaryDarkBackgroundColor
              : DesignTokens.componentButtonSecondaryBackgroundColor,
          textStyle: DesignTokens.componentButtonSecondaryTypography.copyWith(
            fontFamily: platformLabelFamily,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(
            DesignTokens.componentIconButtonSize,
            DesignTokens.componentIconButtonSize,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: DesignTokens.componentButtonPrimaryTypography.copyWith(
            fontFamily: platformLabelFamily,
          ),
          minimumSize: const Size(
            DesignTokens.componentIconButtonSize,
            DesignTokens.componentIconButtonSize,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
        ),
        minTileHeight: DesignTokens.componentRowHeight,
        minLeadingWidth: DesignTokens.componentIconSize,
        horizontalTitleGap: DesignTokens.componentRowGap,
        minVerticalPadding: DesignTokens.componentRowVerticalPadding,
        titleTextStyle: TextStyle(
          fontSize: DesignTokens.typographyBodyFontSize,
          fontWeight: DesignTokens.typographyBodyFontWeight,
          height: DesignTokens.typographyBodyLineHeight,
          letterSpacing: DesignTokens.typographyBodyLetterSpacing,
          color: text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        constraints: const BoxConstraints(
          minHeight: DesignTokens.componentConnectionFieldHeight,
        ),
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            DesignTokens.componentConnectionFieldRounded,
          ),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(
          DesignTokens.componentConnectionFieldPadding,
        ),
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

/// A filled choice field keeps its label and selected value on one surface.
class ConnectSelectionField<T> extends StatelessWidget {
  const ConnectSelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget icon;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    // Menu options grow independently from the compact selected-value field.
    itemHeight: null,
    style: Theme.of(context).textTheme.bodyLarge,
    icon: icon,
    decoration: InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      constraints: const BoxConstraints(
        minHeight: DesignTokens.componentSelectionFieldHeight,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.componentSelectionFieldPadding,
        vertical: DesignTokens.componentSelectionFieldVerticalPadding,
      ),
      // InputDecorator scales floating labels by 0.75. Keep their visible
      // typography at caption size rather than inheriting a Material default.
      floatingLabelStyle: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontSize: DesignTokens.typographyCaptionFontSize / 0.75),
      border: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(
          DesignTokens.componentSelectionFieldRounded,
        ),
        borderSide: BorderSide.none,
      ),
    ),
    items: items,
    onChanged: onChanged,
  );
}

/// Regular separates floating controls from content; clear belongs over media.
enum GlassVariant { regular, clear }

/// Initializes the production shader backend inside the startup error boundary.
abstract final class GlassMaterial {
  static Future<void>? _initialization;
  static bool _initialized = false;

  static bool get isInitialized => _initialized;
  static const backend = 'liquid_glass_widgets';
  static const backendVersion = '1.13.0';

  static Future<void> initialize() {
    if (!ImageFilter.isShaderFilterSupported) return Future<void>.value();
    return _initialization ??=
        liquid.LiquidGlassWidgets.initialize(
              enablePerformanceMonitor: false,
              warmUpMode: liquid.GlassWarmUpMode.always,
            )
            .then((_) {
              _initialized = true;
            })
            .catchError((Object error, StackTrace stack) {
              _initialization = null;
              Error.throwWithStackTrace(error, stack);
            });
  }

  /// Registers Material brightness and system accessibility with the backend.
  /// Backdrop groups belong to local control groups, never the root Navigator.
  static Widget wrap({required Widget child}) => liquid.LiquidGlassWidgets.wrap(
    child: child,
    brightnessResolver: Theme.maybeBrightnessOf,
  );
}

bool _opaqueGlass(BuildContext context, {bool solid = false}) =>
    solid ||
    GlassPreferences.reduced(context) ||
    MediaQuery.highContrastOf(context);

/// A local set of glass shapes sharing one backdrop read and blend geometry.
/// Keep overlapping routes and unrelated content outside this group.
class GlassSurfaceGroup extends StatelessWidget {
  const GlassSurfaceGroup({
    super.key,
    required this.child,
    this.variant = GlassVariant.regular,
  });
  final Widget child;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) {
    if (_opaqueGlass(context) || !ImageFilter.isShaderFilterSupported) {
      return child;
    }
    return liquid.GlassBackdropGroup(
      child: liquid.AdaptiveLiquidGlassLayer(
        settings: Glass.optics(
          brightness: Theme.of(context).brightness,
          variant: variant,
        ),
        quality: liquid.GlassQuality.premium,
        // Blend is a geometric distance, from the same optical edge token.
        blendAmount: DesignTokens.componentGlassRefractionWidth,
        clipBehavior: Clip.none,
        child: _GlassGroup(variant: variant, child: child),
      ),
    );
  }
}

class _GlassGroup extends InheritedWidget {
  const _GlassGroup({required this.variant, required super.child});
  final GlassVariant variant;
  @override
  bool updateShouldNotify(_GlassGroup oldWidget) =>
      variant != oldWidget.variant;
}

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

  /// Backend settings use project optical depth, tint and lighting tokens.
  /// Width of the old backend's refraction band is not a thickness synonym.
  static liquid.LiquidGlassSettings optics({
    required Brightness brightness,
    GlassVariant variant = GlassVariant.regular,
    double radius = DesignTokens.roundedLg,
  }) {
    final dark = brightness == Brightness.dark;
    final clear = variant == GlassVariant.clear;
    return liquid.LiquidGlassSettings(
      thickness: DesignTokens.componentGlassOpticalDepth,
      refractiveIndex: ConnectTokens.glassRefractionIndex,
      chromaticAberration: ConnectTokens.glassDispersion,
      saturation: ConnectTokens.glassSaturation,
      blur: clear
          ? DesignTokens.componentGlassClearBlur
          : ConnectTokens.glassBlur,
      glassColor: clear
          ? (dark
                ? DesignTokens.colorGlassClearDark
                : DesignTokens.colorGlassClear)
          : (dark ? ConnectTokens.glassDark : ConnectTokens.glass),
      lightAngle: DesignTokens.componentGlassAngle * math.pi / 180,
      lightIntensity: DesignTokens.componentGlassSpecularIntensity,
      glowIntensity: DesignTokens.componentGlassGlowIntensity,
      shadow: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque = _opaqueGlass(context, solid: solid);
    final style = optics(
      brightness: Theme.of(context).brightness,
      variant: variant,
    );
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque ? Theme.of(context).colorScheme.surface : null,
        borderRadius: BorderRadius.circular(radius),
        border: opaque
            ? Border.all(color: Theme.of(context).colorScheme.outline)
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    final Widget surface;
    if (opaque) {
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: content,
      );
    } else if (ImageFilter.isShaderFilterSupported) {
      if (!GlassMaterial.isInitialized) {
        throw StateError(
          'Await GlassMaterial.initialize() before mounting glass controls.',
        );
      }
      final shape = liquid.LiquidRoundedSuperellipse(borderRadius: radius);
      final group = context.dependOnInheritedWidgetOfExactType<_GlassGroup>();
      surface = group?.variant == variant
          ? liquid.AdaptiveGlass.grouped(
              shape: shape,
              quality: liquid.GlassQuality.premium,
              child: content,
            )
          : liquid.AdaptiveGlass(
              shape: shape,
              settings: style,
              quality: liquid.GlassQuality.premium,
              allowElevation: false,
              child: content,
            );
    } else {
      // Widget tests and non-shader backends retain a declared frosted fallback.
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: style.blur, sigmaY: style.blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: style.glassColor,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: dark
                    ? ConnectTokens.glassEdgeDark
                    : ConnectTokens.glassEdge,
              ),
            ),
            child: content,
          ),
        ),
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
      child: surface,
    );
  }
}

/// One floating control, with a stable 44-point layout and semantic hit area.
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
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final opaque = _opaqueGlass(context);
    final foreground = enabled
        ? color ?? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).disabledColor;
    final content = IconTheme(
      data: IconThemeData(
        size: DesignTokens.componentIconSize,
        color: foreground,
      ),
      child: icon,
    );
    final Widget control;
    if (opaque || !ImageFilter.isShaderFilterSupported || !enabled) {
      control = Glass(
        radius: DesignTokens.roundedFull,
        variant: variant,
        child: CupertinoButton(
          padding: const EdgeInsets.all(DesignTokens.spacingSm),
          minimumSize: const Size.square(DesignTokens.componentIconButtonSize),
          onPressed: onPressed,
          child: content,
        ),
      );
    } else {
      if (!GlassMaterial.isInitialized) {
        throw StateError(
          'Await GlassMaterial.initialize() before mounting glass controls.',
        );
      }
      final reducedMotion = liquid.GlassAccessibilityData.of(context)
          .reduceMotion;
      control = liquid.GlassAccessibilityScope(
        reduceMotion: reducedMotion,
        child: liquid.GlassButton.custom(
          width: DesignTokens.componentIconButtonSize,
          height: DesignTokens.componentIconButtonSize,
          shape: const liquid.LiquidOval(),
          settings: Glass.optics(
            brightness: Theme.of(context).brightness,
            variant: variant,
          ),
          quality: liquid.GlassQuality.premium,
          useOwnLayer: true,
          // Keep press/lighting feedback while removing spatial motion.
          stretch: reducedMotion ? 0 : 0.5,
          interactionScale: reducedMotion ? 1 : null,
          anchorStretch: !reducedMotion,
          label: tooltip,
          onTap: onPressed!,
          child: content,
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: DesignTokens.componentIconButtonSize,
        child: control,
      ),
    );
  }
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
    return GlassSurfaceGroup(
      variant: variant,
      child: Glass(
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
      radius: DesignTokens.componentNavigationRounded,
      padding: const EdgeInsets.all(DesignTokens.componentNavigationPadding),
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
                    ),
                    minimumSize: const Size(
                      DesignTokens.componentIconButtonSize,
                      DesignTokens.componentNavigationHeight -
                          2 * DesignTokens.componentNavigationPadding,
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

/// Compact visual geometry with a separate accessible touch target.
class ConnectSwitch extends StatelessWidget {
  const ConnectSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final toggle = onChanged == null ? null : () => onChanged!(!value);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kThemeAnimationDuration;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      onTap: toggle,
      child: SizedBox.square(
        dimension: DesignTokens.componentIconButtonSize,
        child: InkWell(
          onTap: toggle,
          excludeFromSemantics: true,
          customBorder: const StadiumBorder(),
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              width: DesignTokens.componentSwitchTrackWidth,
              height: DesignTokens.componentSwitchTrackHeight,
              padding: const EdgeInsets.all(
                (DesignTokens.componentSwitchTrackHeight -
                        DesignTokens.componentSwitchThumbSize) /
                    2,
              ),
              decoration: BoxDecoration(
                color: onChanged == null
                    ? colors.outlineVariant
                    : value
                    ? colors.primary
                    : colors.outlineVariant,
                borderRadius: BorderRadius.circular(
                  DesignTokens.componentSwitchTrackRounded,
                ),
              ),
              child: AnimatedAlign(
                duration: duration,
                alignment: value
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: SizedBox.square(
                  dimension: DesignTokens.componentSwitchThumbSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: value && onChanged != null
                          ? colors.onPrimary
                          : colors.brightness == Brightness.dark
                          ? colors.onSurface
                          : colors.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
