import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 搜索图形大小（design.md「输入与选择」：起始 20 点搜索图形）。
const _searchGlyphSize = DesignTokens.componentSectionGlyphSize;

/// 清除按钮的尾内距（Ardot 搜索框 37:678：右内距 4，清除按钮 36 正圆）。
const _clearEndPadding = DesignTokens.spacingXs;

/// 搜索框（Ardot 37:678）：高 44 胶囊，`inset` 底，起始搜索图形，有内容时显示清除按钮。
///
/// [readOnly] 时是打开搜索页的入口：外观不变，整框作为一个按钮，点按调用 [onTap]，
/// 读屏名称为 [hintText]；[onTap] 为空时呈禁用。
class AppSearchField extends HookWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hintText = '搜索',
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction = TextInputAction.search,
    this.readOnly = false,
    this.onTap,
  }) : assert(controller != null || readOnly);

  /// 可编辑时必填；只读入口不需要。
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 清除按钮清空文字后调用；未提供时以空字符串调用 [onChanged]。
  final VoidCallback? onCleared;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final TextInputAction textInputAction;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final ownController = useTextEditingController();
    final controller = this.controller ?? ownController;
    final value = useValueListenable(controller);
    final enabled = this.enabled && (!readOnly || onTap != null);
    const radius = BorderRadius.all(
      Radius.circular(DesignTokens.componentSearchFieldRounded),
    );
    OutlineInputBorder border([BorderSide side = BorderSide.none]) =>
        OutlineInputBorder(borderRadius: radius, borderSide: side);
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      style: type.body,
      cursorColor: colors.primary,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: colors.inset,
        hintText: hintText,
        hintStyle: type.body.copyWith(color: colors.textSecondary),
        constraints: const BoxConstraints(
          minHeight: DesignTokens.componentSearchFieldHeight,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical:
              (DesignTokens.componentSearchFieldHeight -
                  DesignTokens.typographyBodyFontSize *
                      DesignTokens.typographyBodyLineHeight) /
              2,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: DesignTokens.componentSearchFieldPadding,
            end: DesignTokens.spacingSm,
          ),
          child: Icon(
            AppIcons.search,
            size: _searchGlyphSize,
            color: enabled ? colors.textSecondary : colors.disabled,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(),
        suffixIcon: value.text.isEmpty || !enabled || readOnly
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: _clearEndPadding,
                ),
                child: IconButton(
                  tooltip: '清除',
                  onPressed: () {
                    controller.clear();
                    if (onCleared != null) {
                      onCleared!();
                    } else {
                      onChanged?.call('');
                    }
                  },
                  icon: const Icon(AppIcons.close),
                  iconSize: _searchGlyphSize,
                  color: colors.textSecondary,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(
                      DesignTokens.componentSectionButtonSize,
                    ),
                    fixedSize: const Size.square(
                      DesignTokens.componentSectionButtonSize,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
        suffixIconConstraints: const BoxConstraints(),
        border: border(),
        enabledBorder: border(),
        disabledBorder: border(),
        focusedBorder: border(),
      ),
    );
    if (!readOnly) return field;
    return Semantics(
      button: true,
      enabled: enabled,
      label: hintText,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: ExcludeSemantics(child: IgnorePointer(child: field)),
      ),
    );
  }
}
