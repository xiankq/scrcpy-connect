import 'dart:ui';

import 'package:flutter/material.dart';

/// Semantic values mapped directly from designs/design.md.
abstract final class ConnectTokens {
  static const ink = Color(0xff171719);
  static const secondary = Color(0xff67676e);
  static const canvas = Color(0xfff5f5f7);
  static const tint = Color(0xffe9e9ee);
  static const violet = Color(0xff7754c8);
  static const coral = Color(0xffc95646);
  static const amber = Color(0xff9f6719);
  static const mint = Color(0xff25745c);
  static const danger = Color(0xffd34f60);
  static const radius = 26.0;
  static const glassPanel = Color(0xb8ffffff);
  static const glassPanelDark = Color(0xe8202023);
  static const glassShine = Color(0x66ffffff);
  static const glassShineDark = Color(0x1fffffff);
  static const glassReflection = Color(0x1a918aa3);
  static const glassReflectionDark = Color(0x0fffffff);

  static Color accent(BuildContext context, Color color) {
    if (Theme.of(context).brightness != Brightness.dark) return color;
    return switch (color) {
      violet => const Color(0xffc2a7ff),
      coral => const Color(0xffffaa93),
      amber => const Color(0xffeac17b),
      mint => const Color(0xff9be5c9),
      danger => const Color(0xffff9aa8),
      _ => color,
    };
  }

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff1b1b1f),
      brightness: brightness,
      primary: dark ? const Color(0xfff2f2f4) : const Color(0xff1b1b1f),
      onPrimary: dark ? const Color(0xff18181a) : Colors.white,
      surface: dark ? const Color(0xff202023) : Colors.white,
      error: dark ? const Color(0xffff9aa8) : danger,
    );
    final text = dark ? const Color(0xfff5f5f7) : ink;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: dark ? const Color(0xff111113) : canvas,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -.6,
          color: text,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          height: 1.25,
          color: text,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          height: 1.35,
          color: text,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.45,
          color: text,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: text),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: text),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: dark ? const Color(0xffababb2) : secondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: text,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        ),
      ),
      dividerColor: dark ? const Color(0xff3b3b41) : const Color(0xffdedee3),
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

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.solid = false,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool solid;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque =
        solid ||
        GlassPreferences.reduced(context) ||
        MediaQuery.highContrastOf(context);
    final base = dark ? ConnectTokens.glassPanelDark : ConnectTokens.glassPanel;
    final shine = dark
        ? ConnectTokens.glassShineDark
        : ConnectTokens.glassShine;
    final reflection = dark
        ? ConnectTokens.glassReflectionDark
        : ConnectTokens.glassReflection;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x66000000) : const Color(0x2137303e),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: opaque ? 0 : 20,
            sigmaY: opaque ? 0 : 20,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: opaque ? Theme.of(context).colorScheme.surface : null,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: dark ? const Color(0x73ffffff) : const Color(0xf2ffffff),
              ),
              gradient: opaque
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      // A decoration gradient replaces its color fill. Blend
                      // each reflection onto the mapped panel first so the
                      // material keeps its intended opacity over live media.
                      colors: [
                        Color.alphaBlend(shine, base),
                        Color.alphaBlend(reflection, base),
                      ],
                    ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(padding: padding, child: child),
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
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(26),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class FeatureIcon extends StatelessWidget {
  const FeatureIcon(
    this.icon, {
    super.key,
    this.color = ConnectTokens.violet,
    this.size = 48,
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
        color: resolved.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: resolved, size: 23),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FeatureIcon(icon, size: 72),
              const SizedBox(height: 24),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    ),
  );
}
