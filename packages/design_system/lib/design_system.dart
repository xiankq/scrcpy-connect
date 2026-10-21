import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

import 'src/design_tokens.g.dart';

// Re-export the official controls unchanged; pages use their public API.
export 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassIconButton, GlassTabBar, GlassTab;

export 'src/design_tokens.g.dart';
export 'src/list_icon_badge.dart';

part 'src/glass_overlays.dart';

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
        border: UnderlineInputBorder(
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

/// Bridges the application preference to the official accessibility scope.
class GlassPreferences extends StatelessWidget {
  const GlassPreferences({
    super.key,
    required this.reduceTransparency,
    required this.child,
  });
  final bool reduceTransparency;
  final Widget child;
  static bool reduced(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GlassPreferences>()
          ?.reduceTransparency ??
      false;
  @override
  Widget build(BuildContext context) => _GlassPreferences(
    reduceTransparency: reduceTransparency,
    child: liquid.GlassAccessibilityScope(
      reduceTransparency:
          reduceTransparency ||
          MediaQuery.highContrastOf(context) ||
          liquid.GlassAccessibilityData.of(context).reduceTransparency,
      child: child,
    ),
  );
}

class _GlassPreferences extends InheritedWidget {
  const _GlassPreferences({
    required this.reduceTransparency,
    required super.child,
  });
  final bool reduceTransparency;
  @override
  bool updateShouldNotify(_GlassPreferences oldWidget) =>
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
    this.readOnly = false,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget icon;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
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
    );
    if (readOnly) {
      final selected = items.where((item) => item.value == value).firstOrNull;
      return Semantics(
        enabled: false,
        child: InputDecorator(
          decoration: decoration.copyWith(enabled: false),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyLarge!
                .copyWith(color: Theme.of(context).disabledColor),
            child: selected?.child ?? const SizedBox.shrink(),
          ),
        ),
      );
    }
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      // Menu options grow independently from the compact selected-value field.
      itemHeight: null,
      style: Theme.of(context).textTheme.bodyLarge,
      icon: icon,
      decoration: decoration,
      items: items,
      onChanged: onChanged,
    );
  }
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
  static const samplingBounds = 'surface-rect-with-optical-headroom';
  static const composition =
      'component-owned-navigation-and-local-surface-groups';

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

  // Pure configuration for official components; these methods build no widgets
  // and do not replace the library's gestures, focus or component lifecycle.
  static bool opaque(BuildContext context) => _opaqueGlass(context);

  static bool reduceMotion(BuildContext context) =>
      liquid.GlassAccessibilityData.of(context).reduceMotion;

  static liquid.GlassThemeData theme(BuildContext context) {
    final theme = liquid.GlassThemeData.of(context);
    return theme.copyWith(
      interaction: theme.interaction.copyWith(
        stretch: reduceMotion(context)
            ? 0
            : DesignTokens.componentGlassInteractionStretch,
      ),
    );
  }

  static liquid.GlassQuality quality(BuildContext context) =>
      opaque(context) || !ImageFilter.isShaderFilterSupported
      ? liquid.GlassQuality.minimal
      : liquid.GlassQuality.premium;

  static liquid.LiquidGlassSettings settings(
    BuildContext context, {
    GlassVariant variant = GlassVariant.regular,
  }) {
    final settings = Glass.optics(
      brightness: Theme.of(context).brightness,
      variant: variant,
    );
    return quality(context) == liquid.GlassQuality.minimal
        ? settings.copyWith(
            blur: 0,
            glassColor: Theme.of(context).colorScheme.surface,
            bodyMode: liquid.GlassBodyMode.clear,
          )
        : settings;
  }

  static double navigationHeight(BuildContext context) {
    final label = Theme.of(context).textTheme.labelLarge!;
    return math.max(
      DesignTokens.componentNavigationHeight,
      DesignTokens.componentIconSize +
          DesignTokens.spacingMicro +
          MediaQuery.textScalerOf(context).scale(label.fontSize!) *
              label.height! +
          2 * DesignTokens.componentNavigationPadding,
    );
  }

  /// The tab bar's local clear lens, separate from its regular glass track.
  static liquid.LiquidGlassSettings navigationLensSettings(
    BuildContext context,
  ) => opaque(context)
      ? settings(context).copyWith(glassColor: DesignTokens.colorTransparent)
      : liquid.AnimatedGlassIndicator.baseIndicatorSettings;

  static bool restingNavigationLens(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light &&
      quality(context) == liquid.GlassQuality.premium;

  /// The sole regular navigation track. It paints before the selection lens
  /// and glyphs so the settled lens never reads its own foreground labels.
  static liquid.LiquidGlassSettings navigationTrackSettings(
    BuildContext context,
  ) => settings(context).copyWith(
    shadow: !opaque(context) && Theme.of(context).brightness == Brightness.light
        ? const [
            BoxShadow(
              color: ConnectTokens.shadow,
              blurRadius: ConnectTokens.shadowBlur,
              offset: Offset(0, ConnectTokens.shadowOffset),
            ),
          ]
        : const [],
  );

  /// Foreground bar retains the library's gestures and moving lens. On the
  /// premium three-layer path, zero depth AND blur select the renderer's
  /// no-optics fast path; transparency alone would still paint a glass track.
  static liquid.LiquidGlassSettings navigationBarSettings(
    BuildContext context,
  ) => restingNavigationLens(context)
      ? settings(context).copyWith(
          thickness: 0,
          blur: 0,
          glassColor: DesignTokens.colorTransparent,
          backerColor: DesignTokens.colorTransparent,
          bodyMode: liquid.GlassBodyMode.clear,
          shadow: const [],
        )
      : navigationTrackSettings(context);

  /// Registers Material brightness and system accessibility with the backend.
  /// Backdrop groups belong to local control groups, never the root Navigator.
  static Widget wrap({required Widget child}) => liquid.LiquidGlassWidgets.wrap(
    child: child,
    brightnessResolver: Theme.maybeBrightnessOf,
  );
}

/// Composes one regular track, a settled lens, then the official foreground bar.
/// The bar retains gestures, focus and semantics with navigationBarSettings;
/// its own moving lens takes over during a pointer gesture. No rim is painted.
class NavigationSelectionLens extends StatefulWidget {
  const NavigationSelectionLens({
    super.key,
    required this.selectedIndex,
    required this.itemCount,
    required this.child,
  });

  final int selectedIndex;
  final int itemCount;
  final Widget child;

  @override
  State<NavigationSelectionLens> createState() =>
      _NavigationSelectionLensState();
}

class _NavigationSelectionLensState extends State<NavigationSelectionLens> {
  // 1.13.0 keeps the moving lens alive for its 420 ms press window and
  // alignment/thickness spring tails. Its public bar has no settle callback.
  // Leave that complete release interval to the original lens before mounting
  // the settled lens, so two optical surfaces do not overlap during release.
  static const _releaseInterval = Duration(milliseconds: 1100);
  final _pointers = <int>{};
  Timer? _settle;
  bool _interacting = false;

  void _start(PointerDownEvent event) {
    if (!GlassMaterial.restingNavigationLens(context)) return;
    _settle?.cancel();
    _pointers.add(event.pointer);
    if (!_interacting) setState(() => _interacting = true);
  }

  void _end(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty || !_interacting) return;
    _settle?.cancel();
    _settle = Timer(_releaseInterval, () {
      if (mounted) setState(() => _interacting = false);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = GlassMaterial.restingNavigationLens(context);
    return Listener(
      onPointerDown: _start,
      onPointerUp: _end,
      onPointerCancel: _end,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: liquid.AdaptiveGlass(
                  shape: const liquid.LiquidRoundedRectangle(
                    borderRadius: DesignTokens.componentNavigationRounded,
                  ),
                  settings: GlassMaterial.navigationTrackSettings(context),
                  quality: liquid.GlassQuality.premium,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          if (enabled && !_interacting)
            liquid.AnimatedGlassIndicator(
              key: const ValueKey('resting-navigation-lens'),
              velocity: 0,
              itemCount: widget.itemCount,
              alignment: AlignmentDirectional(
                widget.itemCount == 1
                    ? 0
                    : -1 + 2 * widget.selectedIndex / (widget.itemCount - 1),
                0,
              ),
              thickness: 1,
              quality: liquid.GlassQuality.premium,
              indicatorColor: DesignTokens.colorTransparent,
              isBackgroundIndicator: false,
              paintBackground: false,
              padding: const EdgeInsets.all(DesignTokens.spacingXxs),
              expansion: EdgeInsets.zero,
              pinchStrength: 0,
              settings: GlassMaterial.navigationLensSettings(context).copyWith(
                shadow: const [
                  BoxShadow(
                    color: ConnectTokens.shadow,
                    blurRadius: DesignTokens.spacingXs,
                    offset: Offset(0, DesignTokens.spacingMicro),
                  ),
                ],
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

bool _opaqueGlass(BuildContext context, {bool solid = false}) =>
    solid ||
    GlassPreferences.reduced(context) ||
    liquid.GlassAccessibilityData.of(context).reduceTransparency ||
    MediaQuery.highContrastOf(context);

// An explicit rectangular compositor bound precedes the backend's shape and
// blur passes. Preserve optical edge and press headroom without sampling an
// unconstrained ancestor surface.
Widget _boundGlassSampling(
  Widget child, {
  EdgeInsets expansion = const EdgeInsets.all(
    DesignTokens.componentGlassRefractionWidth,
  ),
}) => ClipRect(
  clipBehavior: Clip.hardEdge,
  clipper: _GlassSamplingClipper(expansion),
  child: child,
);

EdgeInsets _glassMotionExpansion(
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

/// One optical plane sharing a single SDF and refraction pass.
/// Same-variant groups join the enclosing plane; different variants remain
/// separate. Scope this to a current page, never a Navigator or retained tabs.
class GlassSurfaceGroup extends StatelessWidget {
  const GlassSurfaceGroup({
    super.key,
    required this.child,
    this.variant = GlassVariant.regular,
    this.clipExpansion = const EdgeInsets.all(
      DesignTokens.componentGlassRefractionWidth,
    ),
  }) : _isolated = false;

  /// An overlay owns a new sampling plane even when its OverlayPortal retains
  /// the source toolbar's inherited group. It never joins that source plane.
  const GlassSurfaceGroup.isolated({
    super.key,
    required this.child,
    this.variant = GlassVariant.regular,
    this.clipExpansion = const EdgeInsets.all(
      DesignTokens.componentGlassRefractionWidth,
    ),
  }) : _isolated = true;
  final Widget child;
  final GlassVariant variant;
  final EdgeInsets clipExpansion;
  final bool _isolated;

  @override
  Widget build(BuildContext context) {
    if (_opaqueGlass(context) || !ImageFilter.isShaderFilterSupported) {
      return child;
    }
    final enclosing = context.dependOnInheritedWidgetOfExactType<_GlassGroup>();
    if (!_isolated && enclosing?.variant == variant) return child;
    return _boundGlassSampling(
      liquid.GlassBackdropGroup(
        child: liquid.AdaptiveLiquidGlassLayer(
          settings: Glass.optics(
            brightness: Theme.of(context).brightness,
            variant: variant,
          ),
          quality: liquid.GlassQuality.premium,
          // Blend is a geometric distance, from the same optical edge token.
          blendAmount: DesignTokens.componentGlassRefractionWidth,
          clipBehavior: Clip.none,
          clipExpansion: clipExpansion,
          child: _GlassGroup(variant: variant, child: child),
        ),
      ),
      expansion: clipExpansion,
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
    this.clipExpansion = const EdgeInsets.all(
      DesignTokens.componentGlassRefractionWidth,
    ),
  });
  final Widget child;
  final EdgeInsets clipExpansion;
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
      bodyMode: clear
          ? liquid.GlassBodyMode.clear
          : liquid.GlassBodyMode.adaptive,
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
    Widget surface;
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
              clipExpansion: clipExpansion,
              child: content,
            );
      surface = _boundGlassSampling(surface, expansion: clipExpansion);
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

/// Pointer feedback for controls whose gesture recognizer belongs to the app.
/// This observes pointers only; taps, dragging and cancellation stay with child.
class GlassPressFeedback extends StatefulWidget {
  const GlassPressFeedback({
    super.key,
    required this.child,
    this.radius = DesignTokens.roundedFull,
    this.enabled = true,
  });
  final Widget child;
  final double radius;
  final bool enabled;

  @override
  State<GlassPressFeedback> createState() => _GlassPressFeedbackState();
}

class _GlassPressFeedbackState extends State<GlassPressFeedback>
    with WidgetsBindingObserver {
  final Map<int, Offset> _pointers = {};
  Offset _touch = Offset.zero;
  int _lifecycleEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(GlassPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pointers.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _pointers.isNotEmpty) {
      setState(() {
        _pointers.clear();
        _lifecycleEpoch++;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _track(PointerEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return;
    final position = box.globalToLocal(event.position);
    setState(() {
      _pointers[event.pointer] = position;
      _touch = Offset(
        (position.dx / box.size.width * 2 - 1).clamp(-1, 1),
        (position.dy / box.size.height * 2 - 1).clamp(-1, 1),
      );
    });
  }

  void _release(PointerEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      setState(() => _pointers.remove(event.pointer));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback =
        _opaqueGlass(context) || !ImageFilter.isShaderFilterSupported;
    final pressed = widget.enabled && _pointers.isNotEmpty;
    final reducedMotion = liquid.GlassAccessibilityData.of(context)
        .reduceMotion;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.radius),
    );
    Widget content = widget.child;
    if (fallback) {
      content = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape,
          color: pressed
              ? Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: DesignTokens.componentControlFeedbackOpacity,
                )
              : DesignTokens.colorTransparent,
        ),
        child: content,
      );
    } else {
      content = liquid.GlassGlow(
        key: ValueKey(_lifecycleEpoch),
        enabled: widget.enabled,
        clipper: ShapeBorderClipper(shape: shape),
        child: content,
      );
    }
    // Only observe pointers. Child recognizers retain taps, drags and arena
    // cancellation, and transforms never enlarge their layout or hit regions.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled ? _track : null,
      onPointerMove: widget.enabled
          ? (event) {
              if (_pointers.containsKey(event.pointer)) _track(event);
            }
          : null,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: liquid.SpringBuilder(
        value: pressed && !reducedMotion ? 1 : 0,
        spring: liquid.GlassSpring.interactive(),
        builder: (context, press, child) => liquid.SpringBuilder(
          value: pressed && !reducedMotion ? _touch.dx : 0,
          spring: liquid.GlassSpring.interactive(),
          builder: (context, x, child) => liquid.SpringBuilder(
            value: pressed && !reducedMotion ? _touch.dy : 0,
            spring: liquid.GlassSpring.interactive(),
            builder: (context, y, child) {
              final growth = reducedMotion
                  ? 0.0
                  : DesignTokens.componentGlassInteractionScale - 1;
              final stretch =
                  growth * DesignTokens.componentGlassInteractionStretch;
              return Transform(
                alignment: Alignment(
                  -x.clamp(-1, 1).toDouble(),
                  -y.clamp(-1, 1).toDouble(),
                ),
                transformHitTests: false,
                transform: Matrix4.diagonal3Values(
                  1 + growth * press + stretch * (x.abs() - y.abs()),
                  1 + growth * press + stretch * (y.abs() - x.abs()),
                  1,
                ),
                child: child,
              );
            },
            child: child,
          ),
          child: child,
        ),
        child: content,
      ),
    );
  }
}

/// One existing application action, without device or routing knowledge.
@immutable
class GlassMenuAction {
  const GlassMenuAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool destructive;
}

/// A 44-point menu source that morphs using the production glass backend.
class GlassMenuButton extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.actions,
    this.variant = GlassVariant.regular,
    this.enabled = true,
  }) : assert(actions.length > 0);
  final Widget icon;
  final String tooltip;
  final List<GlassMenuAction> actions;
  final GlassVariant variant;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opaque = _opaqueGlass(context);
    final reducedMotion = liquid.GlassAccessibilityData.of(context)
        .reduceMotion;
    final style = theme.textTheme.labelLarge!;
    final itemHeight = math.max(
      DesignTokens.componentIconButtonSize,
      MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height! +
          2 * DesignTokens.spacingSm,
    );
    if (!enabled) {
      return GlassTooltip(
        message: tooltip,
        child: liquid.GlassIconButton(
          icon: icon,
          semanticLabel: tooltip,
          onPressed: null,
          size: DesignTokens.componentIconButtonSize,
          iconSize: DesignTokens.componentIconSize,
          settings: GlassMaterial.settings(context, variant: variant),
          quality: GlassMaterial.quality(context),
          useOwnLayer: true,
          interactionScale: reducedMotion
              ? 1
              : DesignTokens.componentGlassInteractionScale,
          anchorStretch: !reducedMotion,
        ),
      );
    }
    if (reducedMotion || opaque || !ImageFilter.isShaderFilterSupported) {
      // The backend's "instant" morph still uses a spatial spring. Reduced
      // motion uses an unanimated framework lifecycle; fallback renderers use
      // the same keyboard and dismissal semantics with an explicit solid face.
      return MenuAnchor(
        animated: !reducedMotion,
        clipBehavior: Clip.none,
        consumeOutsideTap: true,
        style: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            DesignTokens.colorTransparent,
          ),
          surfaceTintColor: WidgetStatePropertyAll(
            DesignTokens.colorTransparent,
          ),
          elevation: WidgetStatePropertyAll(0),
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        menuChildren: [
          GlassSurfaceGroup.isolated(
            variant: variant,
            child: Glass(
              solid: !ImageFilter.isShaderFilterSupported,
              variant: variant,
              radius: DesignTokens.roundedLg,
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacingXs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in actions)
                    MenuItemButton(
                      style: ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(
                          Size(
                            DesignTokens.componentIconButtonSize,
                            itemHeight,
                          ),
                        ),
                        textStyle: WidgetStatePropertyAll(style),
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.disabled)
                              ? theme.disabledColor
                              : action.destructive
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface,
                        ),
                        iconSize: const WidgetStatePropertyAll(
                          DesignTokens.componentIconSize,
                        ),
                      ),
                      leadingIcon: action.icon,
                      onPressed: action.onPressed,
                      child: Text(action.label),
                    ),
                ],
              ),
            ),
          ),
        ],
        builder: (context, controller, child) => GlassActionIcon(
          style: IconButton.styleFrom(
            minimumSize: const Size.square(
              DesignTokens.componentIconButtonSize,
            ),
            maximumSize: const Size.square(
              DesignTokens.componentIconButtonSize,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: theme.colorScheme.onSurface,
            iconSize: DesignTokens.componentIconSize,
          ),
          icon: icon,
          tooltip: tooltip,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );
    }
    return liquid.GlassAccessibilityScope(
      reduceMotion: reducedMotion,
      child: liquid.GlassMenu(
        autoAdjustToScreen: true,
        menuPadding: const EdgeInsets.all(DesignTokens.spacingMd),
        menuBorderRadius: DesignTokens.roundedLg,
        itemBorderRadius: DesignTokens.roundedMd,
        settings: Glass.optics(brightness: theme.brightness, variant: variant),
        quality: liquid.GlassQuality.premium,
        stretch: reducedMotion
            ? 0
            : DesignTokens.componentGlassInteractionStretch,
        triggerBuilder: (context, toggle) => GlassActionIcon(
          style: IconButton.styleFrom(
            minimumSize: const Size.square(
              DesignTokens.componentIconButtonSize,
            ),
            maximumSize: const Size.square(
              DesignTokens.componentIconButtonSize,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: theme.colorScheme.onSurface,
            iconSize: DesignTokens.componentIconSize,
          ),
          icon: icon,
          tooltip: tooltip,
          onPressed: toggle,
        ),
        items: [
          for (final action in actions)
            liquid.GlassMenuItem(
              title: action.label,
              icon: action.icon,
              onTap: action.onPressed ?? () {},
              enabled: action.onPressed != null,
              isDestructive: action.destructive,
              height: itemHeight,
              titleStyle: style,
              iconColor: action.destructive
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
              iconSize: DesignTokens.componentIconSize,
              enablePressScale: !reducedMotion,
            ),
        ],
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
      child: GlassPressFeedback(
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
