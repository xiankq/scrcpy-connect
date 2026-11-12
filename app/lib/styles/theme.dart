import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// 直接映射 designs/design.md 的语义值。
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

  static ThemeData theme(
    Brightness brightness, {
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    final platform = defaultTargetPlatform;
    final family = switch (platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => null,
      TargetPlatform.android ||
      TargetPlatform.linux => fontFamily ?? 'sans-serif',
      _ => fontFamily,
    };
    TextStyle systemStyle(TextStyle style) => style.copyWith(
      fontFamily: switch (platform) {
        TargetPlatform.iOS =>
          (style.fontSize ?? DesignTokens.typographyBodyFontSize) >= 20
              ? 'CupertinoSystemDisplay'
              : 'CupertinoSystemText',
        TargetPlatform.macOS => '.AppleSystemUIFont',
        _ => family,
      },
      fontFamilyFallback: fontFamilyFallback,
    );
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
      onError: dark
          ? DesignTokens.colorOnDangerDark
          : DesignTokens.colorOnDanger,
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
      fontFamily: family,
      // 明确的系统字族优先，不继承 Material 的固定 Linux 候选列表。
      fontFamilyFallback: fontFamilyFallback ?? const [],
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
        displaySmall: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyDisplayFontSize,
            fontWeight: DesignTokens.typographyDisplayFontWeight,
            height: DesignTokens.typographyDisplayLineHeight,
            letterSpacing: DesignTokens.typographyDisplayLetterSpacing,
            color: text,
          ),
        ),
        headlineMedium: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyTitleFontSize,
            fontWeight: DesignTokens.typographyTitleFontWeight,
            height: DesignTokens.typographyTitleLineHeight,
            letterSpacing: DesignTokens.typographyTitleLetterSpacing,
            color: text,
          ),
        ),
        titleLarge: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyHeadingFontSize,
            fontWeight: DesignTokens.typographyHeadingFontWeight,
            height: DesignTokens.typographyHeadingLineHeight,
            letterSpacing: DesignTokens.typographyHeadingLetterSpacing,
            color: text,
          ),
        ),
        titleMedium: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyBodyEmphasisFontSize,
            fontWeight: DesignTokens.typographyBodyEmphasisFontWeight,
            height: DesignTokens.typographyBodyEmphasisLineHeight,
            letterSpacing: DesignTokens.typographyBodyEmphasisLetterSpacing,
            color: text,
          ),
        ),
        bodyLarge: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyBodyFontSize,
            fontWeight: DesignTokens.typographyBodyFontWeight,
            height: DesignTokens.typographyBodyLineHeight,
            letterSpacing: DesignTokens.typographyBodyLetterSpacing,
            color: text,
          ),
        ),
        bodyMedium: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyBodyCompactFontSize,
            fontWeight: DesignTokens.typographyBodyCompactFontWeight,
            height: DesignTokens.typographyBodyCompactLineHeight,
            letterSpacing: DesignTokens.typographyBodyCompactLetterSpacing,
            color: text,
          ),
        ),
        bodySmall: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyCaptionFontSize,
            fontWeight: DesignTokens.typographyCaptionFontWeight,
            height: DesignTokens.typographyCaptionLineHeight,
            letterSpacing: DesignTokens.typographyCaptionLetterSpacing,
            color: dark ? DesignTokens.colorSecondaryDark : secondary,
          ),
        ),
        labelLarge: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyLabelFontSize,
            fontWeight: DesignTokens.typographyLabelFontWeight,
            height: DesignTokens.typographyLabelLineHeight,
            letterSpacing: DesignTokens.typographyLabelLetterSpacing,
            color: text,
          ),
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
          textStyle: systemStyle(DesignTokens.componentButtonPrimaryTypography),
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
          textStyle: systemStyle(
            DesignTokens.componentButtonSecondaryTypography,
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
          textStyle: systemStyle(DesignTokens.componentButtonPrimaryTypography),
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
        titleTextStyle: systemStyle(
          TextStyle(
            fontSize: DesignTokens.typographyBodyFontSize,
            fontWeight: DesignTokens.typographyBodyFontWeight,
            height: DesignTokens.typographyBodyLineHeight,
            letterSpacing: DesignTokens.typographyBodyLetterSpacing,
            color: text,
          ),
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
