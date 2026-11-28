import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';

/// 随明暗切换的颜色角色，取值来自 designs/design.md「颜色」。
///
/// 明暗相同的颜色（功能色、媒体、通话舞台等）直接使用 [DesignTokens]。
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.page,
    required this.card,
    required this.block,
    required this.inset,
    required this.text,
    required this.textSecondary,
    required this.separator,
    required this.outline,
    required this.disabled,
    required this.disabledContainer,
    required this.pressed,
    required this.scrim,
    required this.error,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.destructive,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.glassRegular,
    required this.glassPill,
    required this.glassMenu,
    required this.glassFill,
    required this.dockPlatter,
    required this.shadow,
    required this.shadowDock,
  });

  static const light = AppColors(
    primary: DesignTokens.colorPrimary,
    onPrimary: DesignTokens.colorOnPrimary,
    primaryContainer: DesignTokens.colorPrimaryContainer,
    onPrimaryContainer: DesignTokens.colorOnPrimaryContainer,
    page: DesignTokens.colorPage,
    card: DesignTokens.colorCard,
    block: DesignTokens.colorBlock,
    inset: DesignTokens.colorInset,
    text: DesignTokens.colorText,
    textSecondary: DesignTokens.colorTextSecondary,
    separator: DesignTokens.colorSeparator,
    outline: DesignTokens.colorOutline,
    disabled: DesignTokens.colorDisabled,
    disabledContainer: DesignTokens.colorDisabledContainer,
    pressed: DesignTokens.colorPressed,
    scrim: DesignTokens.colorScrim,
    error: DesignTokens.colorError,
    errorContainer: DesignTokens.colorErrorContainer,
    onErrorContainer: DesignTokens.colorOnErrorContainer,
    destructive: DesignTokens.colorDestructive,
    success: DesignTokens.colorSuccess,
    successContainer: DesignTokens.colorSuccessContainer,
    onSuccessContainer: DesignTokens.colorOnSuccessContainer,
    warning: DesignTokens.colorWarning,
    warningContainer: DesignTokens.colorWarningContainer,
    onWarningContainer: DesignTokens.colorOnWarningContainer,
    glassRegular: DesignTokens.colorGlassRegular,
    glassPill: DesignTokens.colorGlassPill,
    glassMenu: DesignTokens.colorGlassMenu,
    glassFill: DesignTokens.colorGlassFill,
    dockPlatter: DesignTokens.colorDockPlatter,
    shadow: DesignTokens.colorShadow,
    shadowDock: DesignTokens.colorShadowDock,
  );

  static const dark = AppColors(
    primary: DesignTokens.colorPrimaryDark,
    onPrimary: DesignTokens.colorOnPrimaryDark,
    primaryContainer: DesignTokens.colorPrimaryContainerDark,
    onPrimaryContainer: DesignTokens.colorOnPrimaryContainerDark,
    page: DesignTokens.colorPageDark,
    card: DesignTokens.colorCardDark,
    block: DesignTokens.colorBlockDark,
    inset: DesignTokens.colorInsetDark,
    text: DesignTokens.colorTextDark,
    textSecondary: DesignTokens.colorTextSecondaryDark,
    separator: DesignTokens.colorSeparatorDark,
    outline: DesignTokens.colorOutlineDark,
    disabled: DesignTokens.colorDisabledDark,
    disabledContainer: DesignTokens.colorDisabledContainerDark,
    pressed: DesignTokens.colorPressedDark,
    scrim: DesignTokens.colorScrimDark,
    error: DesignTokens.colorErrorDark,
    errorContainer: DesignTokens.colorErrorContainerDark,
    onErrorContainer: DesignTokens.colorOnErrorContainerDark,
    destructive: DesignTokens.colorDestructiveDark,
    success: DesignTokens.colorSuccessDark,
    successContainer: DesignTokens.colorSuccessContainerDark,
    onSuccessContainer: DesignTokens.colorOnSuccessContainerDark,
    warning: DesignTokens.colorWarningDark,
    warningContainer: DesignTokens.colorWarningContainerDark,
    onWarningContainer: DesignTokens.colorOnWarningContainerDark,
    glassRegular: DesignTokens.colorGlassRegularDark,
    glassPill: DesignTokens.colorGlassPillDark,
    glassMenu: DesignTokens.colorGlassMenuDark,
    glassFill: DesignTokens.colorGlassFillDark,
    dockPlatter: DesignTokens.colorDockPlatterDark,
    shadow: DesignTokens.colorShadowDark,
    shadowDock: DesignTokens.colorShadowDockDark,
  );

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  /// 表面层级：page → card → block → inset，每升一层用下一级。
  final Color page;
  final Color card;
  final Color block;
  final Color inset;

  final Color text;
  final Color textSecondary;
  final Color separator;
  final Color outline;
  final Color disabled;
  final Color disabledContainer;
  final Color pressed;
  final Color scrim;
  final Color error;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color destructive;
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color glassRegular;
  final Color glassPill;
  final Color glassMenu;
  final Color glassFill;
  final Color dockPlatter;
  final Color shadow;
  final Color shadowDock;

  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      primaryContainer: c(primaryContainer, other.primaryContainer),
      onPrimaryContainer: c(onPrimaryContainer, other.onPrimaryContainer),
      page: c(page, other.page),
      card: c(card, other.card),
      block: c(block, other.block),
      inset: c(inset, other.inset),
      text: c(text, other.text),
      textSecondary: c(textSecondary, other.textSecondary),
      separator: c(separator, other.separator),
      outline: c(outline, other.outline),
      disabled: c(disabled, other.disabled),
      disabledContainer: c(disabledContainer, other.disabledContainer),
      pressed: c(pressed, other.pressed),
      scrim: c(scrim, other.scrim),
      error: c(error, other.error),
      errorContainer: c(errorContainer, other.errorContainer),
      onErrorContainer: c(onErrorContainer, other.onErrorContainer),
      destructive: c(destructive, other.destructive),
      success: c(success, other.success),
      successContainer: c(successContainer, other.successContainer),
      onSuccessContainer: c(onSuccessContainer, other.onSuccessContainer),
      warning: c(warning, other.warning),
      warningContainer: c(warningContainer, other.warningContainer),
      onWarningContainer: c(onWarningContainer, other.onWarningContainer),
      glassRegular: c(glassRegular, other.glassRegular),
      glassPill: c(glassPill, other.glassPill),
      glassMenu: c(glassMenu, other.glassMenu),
      glassFill: c(glassFill, other.glassFill),
      dockPlatter: c(dockPlatter, other.dockPlatter),
      shadow: c(shadow, other.shadow),
      shadowDock: c(shadowDock, other.shadowDock),
    );
  }
}

/// designs/design.md「文字」的 13 个角色，已带宿主字族与正文色。
@immutable
final class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.largeTitle,
    required this.title1,
    required this.pageTitle,
    required this.title3,
    required this.headline,
    required this.body,
    required this.subheadline,
    required this.label,
    required this.footnote,
    required this.caption,
    required this.captionEmphasis,
    required this.caption2,
    required this.tabLabel,
  });

  final TextStyle largeTitle;
  final TextStyle title1;
  final TextStyle pageTitle;
  final TextStyle title3;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle subheadline;
  final TextStyle label;
  final TextStyle footnote;
  final TextStyle caption;
  final TextStyle captionEmphasis;
  final TextStyle caption2;
  final TextStyle tabLabel;

  static AppTypography of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppTypography>() ??
        ConnectTokens.theme(theme.brightness).extension<AppTypography>()!;
  }

  @override
  AppTypography copyWith() => this;

  @override
  AppTypography lerp(AppTypography? other, double t) {
    if (other == null) return this;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTypography(
      largeTitle: s(largeTitle, other.largeTitle),
      title1: s(title1, other.title1),
      pageTitle: s(pageTitle, other.pageTitle),
      title3: s(title3, other.title3),
      headline: s(headline, other.headline),
      body: s(body, other.body),
      subheadline: s(subheadline, other.subheadline),
      label: s(label, other.label),
      footnote: s(footnote, other.footnote),
      caption: s(caption, other.caption),
      captionEmphasis: s(captionEmphasis, other.captionEmphasis),
      caption2: s(caption2, other.caption2),
      tabLabel: s(tabLabel, other.tabLabel),
    );
  }
}

abstract final class ConnectTokens {
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
    final dark = brightness == Brightness.dark;
    final palette = dark ? AppColors.dark : AppColors.light;

    TextStyle role(
      double size,
      FontWeight weight,
      double height,
      double? letterSpacing,
    ) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: palette.text,
      fontFamily: switch (platform) {
        TargetPlatform.iOS =>
          size >= 20 ? 'CupertinoSystemDisplay' : 'CupertinoSystemText',
        TargetPlatform.macOS => '.AppleSystemUIFont',
        _ => family,
      },
      fontFamilyFallback: fontFamilyFallback,
    );

    final type = AppTypography(
      largeTitle: role(
        DesignTokens.typographyLargeTitleFontSize,
        DesignTokens.typographyLargeTitleFontWeight,
        DesignTokens.typographyLargeTitleLineHeight,
        DesignTokens.typographyLargeTitleLetterSpacing,
      ),
      title1: role(
        DesignTokens.typographyTitle1FontSize,
        DesignTokens.typographyTitle1FontWeight,
        DesignTokens.typographyTitle1LineHeight,
        DesignTokens.typographyTitle1LetterSpacing,
      ),
      pageTitle: role(
        DesignTokens.typographyPageTitleFontSize,
        DesignTokens.typographyPageTitleFontWeight,
        DesignTokens.typographyPageTitleLineHeight,
        DesignTokens.typographyPageTitleLetterSpacing,
      ),
      title3: role(
        DesignTokens.typographyTitle3FontSize,
        DesignTokens.typographyTitle3FontWeight,
        DesignTokens.typographyTitle3LineHeight,
        DesignTokens.typographyTitle3LetterSpacing,
      ),
      headline: role(
        DesignTokens.typographyHeadlineFontSize,
        DesignTokens.typographyHeadlineFontWeight,
        DesignTokens.typographyHeadlineLineHeight,
        DesignTokens.typographyHeadlineLetterSpacing,
      ),
      body: role(
        DesignTokens.typographyBodyFontSize,
        DesignTokens.typographyBodyFontWeight,
        DesignTokens.typographyBodyLineHeight,
        DesignTokens.typographyBodyLetterSpacing,
      ),
      subheadline: role(
        DesignTokens.typographySubheadlineFontSize,
        DesignTokens.typographySubheadlineFontWeight,
        DesignTokens.typographySubheadlineLineHeight,
        DesignTokens.typographySubheadlineLetterSpacing,
      ),
      label: role(
        DesignTokens.typographyLabelFontSize,
        DesignTokens.typographyLabelFontWeight,
        DesignTokens.typographyLabelLineHeight,
        DesignTokens.typographyLabelLetterSpacing,
      ),
      footnote: role(
        DesignTokens.typographyFootnoteFontSize,
        DesignTokens.typographyFootnoteFontWeight,
        DesignTokens.typographyFootnoteLineHeight,
        DesignTokens.typographyFootnoteLetterSpacing,
      ),
      caption: role(
        DesignTokens.typographyCaptionFontSize,
        DesignTokens.typographyCaptionFontWeight,
        DesignTokens.typographyCaptionLineHeight,
        DesignTokens.typographyCaptionLetterSpacing,
      ),
      captionEmphasis: role(
        DesignTokens.typographyCaptionEmphasisFontSize,
        DesignTokens.typographyCaptionEmphasisFontWeight,
        DesignTokens.typographyCaptionEmphasisLineHeight,
        DesignTokens.typographyCaptionEmphasisLetterSpacing,
      ),
      caption2: role(
        DesignTokens.typographyCaption2FontSize,
        DesignTokens.typographyCaption2FontWeight,
        DesignTokens.typographyCaption2LineHeight,
        DesignTokens.typographyCaption2LetterSpacing,
      ),
      tabLabel: role(
        DesignTokens.typographyTabLabelFontSize,
        DesignTokens.typographyTabLabelFontWeight,
        DesignTokens.typographyTabLabelLineHeight,
        DesignTokens.typographyTabLabelLetterSpacing,
      ),
    );

    final colors = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      primaryContainer: palette.primaryContainer,
      onPrimaryContainer: palette.onPrimaryContainer,
      secondary: palette.textSecondary,
      onSecondary: palette.card,
      secondaryContainer: palette.block,
      onSecondaryContainer: palette.text,
      tertiary: palette.textSecondary,
      onTertiary: palette.card,
      error: palette.error,
      onError: palette.card,
      errorContainer: palette.errorContainer,
      onErrorContainer: palette.onErrorContainer,
      surface: palette.card,
      onSurface: palette.text,
      onSurfaceVariant: palette.textSecondary,
      surfaceDim: palette.page,
      surfaceBright: palette.card,
      surfaceContainerLowest: palette.card,
      surfaceContainerLow: palette.card,
      surfaceContainer: palette.page,
      surfaceContainerHigh: palette.block,
      surfaceContainerHighest: palette.inset,
      outline: palette.outline,
      outlineVariant: palette.separator,
      shadow: palette.shadow,
      scrim: palette.scrim,
      inverseSurface: palette.text,
      onInverseSurface: palette.card,
      inversePrimary: palette.primaryContainer,
      surfaceTint: palette.page.withAlpha(0),
    );

    final clear = palette.page.withAlpha(0);
    const pill = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      fontFamily: family,
      // 明确的系统字族优先，不继承 Material 的固定 Linux 候选列表。
      fontFamilyFallback: fontFamilyFallback ?? const [],
      extensions: [palette, type],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: DesktopPageTransitionsBuilder(),
          TargetPlatform.windows: DesktopPageTransitionsBuilder(),
          TargetPlatform.linux: DesktopPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
      colorScheme: colors,
      disabledColor: palette.disabled,
      scaffoldBackgroundColor: palette.page,
      canvasColor: palette.page,
      cardColor: palette.card,
      dividerColor: palette.separator,
      splashFactory: NoSplash.splashFactory,
      splashColor: clear,
      highlightColor: palette.pressed,
      hoverColor: palette.pressed,
      focusColor: palette.primary.withValues(alpha: .16),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: palette.primary,
        scaffoldBackgroundColor: palette.page,
        barBackgroundColor: palette.card,
      ),
      textTheme: TextTheme(
        displaySmall: type.largeTitle,
        headlineMedium: type.title1,
        headlineSmall: type.pageTitle,
        titleLarge: type.title3,
        titleMedium: type.headline,
        titleSmall: type.label,
        bodyLarge: type.body,
        bodyMedium: type.subheadline,
        bodySmall: type.footnote.copyWith(color: palette.textSecondary),
        labelLarge: type.label,
        labelMedium: type.captionEmphasis,
        labelSmall: type.caption,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: clear,
        foregroundColor: palette.text,
        surfaceTintColor: clear,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: clear)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: clear),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(
            DesignTokens.componentButtonFilledHeight,
            DesignTokens.componentButtonFilledHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.componentButtonFilledPadding,
          ),
          foregroundColor: palette.onPrimary,
          backgroundColor: palette.primary,
          disabledForegroundColor: palette.disabled,
          disabledBackgroundColor: palette.disabledContainer,
          textStyle: type.label,
          shape: pill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(
            DesignTokens.componentButtonTonalHeight,
            DesignTokens.componentButtonTonalHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.componentButtonTonalPadding,
          ),
          foregroundColor: palette.text,
          backgroundColor: palette.block,
          disabledForegroundColor: palette.disabled,
          disabledBackgroundColor: palette.disabledContainer,
          side: BorderSide.none,
          textStyle: type.label,
          shape: pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: palette.primary,
          disabledForegroundColor: palette.disabled,
          textStyle: type.label,
          minimumSize: const Size(
            DesignTokens.componentButtonTextHeight,
            DesignTokens.componentButtonTextHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.componentButtonTextPadding,
          ),
          shape: pill,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          iconSize: DesignTokens.componentBarGlyphSize,
          foregroundColor: palette.text,
          disabledForegroundColor: palette.disabled,
          minimumSize: const Size(
            DesignTokens.componentBarButtonSize,
            DesignTokens.componentBarButtonSize,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: const WidgetStatePropertyAll(null),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.onPrimary
              : palette.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.disabledContainer
              : states.contains(WidgetState.selected)
              ? palette.primary
              : palette.inset,
        ),
        trackOutlineColor: WidgetStatePropertyAll(clear),
        overlayColor: WidgetStatePropertyAll(clear),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => !states.contains(WidgetState.selected)
              ? clear
              : states.contains(WidgetState.disabled)
              ? palette.disabled
              : palette.primary,
        ),
        checkColor: WidgetStatePropertyAll(palette.onPrimary),
        side: BorderSide(color: palette.outline, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.outline,
        ),
        overlayColor: WidgetStatePropertyAll(clear),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.primaryContainer,
        circularTrackColor: clear,
        linearMinHeight: DesignTokens.componentProgressHeight,
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.componentProgressRounded),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: const BorderRadius.all(
            Radius.circular(DesignTokens.roundedSm),
          ),
        ),
        textStyle: type.footnote,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingSm,
          vertical: DesignTokens.spacingXs,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: clear,
        elevation: 0,
        barrierColor: palette.scrim,
        titleTextStyle: type.headline,
        contentTextStyle: type.subheadline,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentAlertRounded),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.card,
        surfaceTintColor: clear,
        textStyle: type.body,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentMenuRounded),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentListRowPadding,
        ),
        minTileHeight: DesignTokens.componentListRowHeight,
        minLeadingWidth: DesignTokens.componentIconTileSize,
        horizontalTitleGap: DesignTokens.componentListRowGap,
        minVerticalPadding: DesignTokens.componentListRowVerticalPadding,
        titleTextStyle: type.body,
        subtitleTextStyle: type.footnote.copyWith(color: palette.textSecondary),
        iconColor: palette.textSecondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        constraints: const BoxConstraints(
          minHeight: DesignTokens.componentInputHeight,
        ),
        filled: true,
        fillColor: palette.inset,
        hintStyle: type.body.copyWith(color: palette.textSecondary),
        errorStyle: type.footnote.copyWith(color: palette.error),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.componentInputRounded),
          ),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(DesignTokens.componentInputRounded),
          ),
          borderSide: BorderSide(
            color: palette.primary,
            width: DesignTokens.componentControlFocusSize,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(DesignTokens.componentInputRounded),
          ),
          borderSide: BorderSide(
            color: palette.error,
            width: DesignTokens.componentControlFocusSize,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentInputPadding,
          vertical: DesignTokens.spacingMd,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.page,
        modalBackgroundColor: palette.page,
        surfaceTintColor: clear,
        modalBarrierColor: palette.scrim,
        dragHandleColor: palette.outline,
        dragHandleSize: const Size(
          DesignTokens.componentSheetHandleWidth,
          DesignTokens.componentSheetHandleHeight,
        ),
        showDragHandle: true,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DesignTokens.componentSheetRounded),
          ),
        ),
      ),
    );
  }
}
