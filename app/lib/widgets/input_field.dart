import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 输入框内的上下内距（Ardot 输入框 37:677：13 + 22 行高 + 13 = 48）。
const _inputVerticalPadding =
    (DesignTokens.componentInputHeight -
        DesignTokens.typographyBodyFontSize *
            DesignTokens.typographyBodyLineHeight) /
    2;

/// 输入框（Ardot 37:677）：标签在框上方（footnote + text-secondary，间距 8），
/// `inset` 底圆角 16、高至少 48 并随文字增高；聚焦 2 点 primary 内描边，
/// 错误时 2 点 error 内描边并在框下方显示 footnote + error 提示。
///
/// 提供 [validator] 时接入所在 [Form]：校验结果优先于 [errorText] 显示；
/// 同时提供 [focusNode] 时表单字段的键为 `ValueKey(focusNode)`，
/// 调用方可从 `FormState.validateGranularly()` 的结果把焦点移到第一处错误。
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.controller,
    this.focusNode,
    this.hintText,
    this.errorText,
    this.helperText,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.obscureText = false,
    this.autofocus = false,
    this.autocorrect = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.suffix,
    this.autofillHints,
    this.validator,
    this.sensitive = false,
  });

  final String? label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? errorText;

  /// 框下方的说明（footnote + text-secondary）；有 [errorText] 时被错误提示替换。
  final String? helperText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool obscureText;
  final bool autofocus;
  final bool autocorrect;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;

  /// 框内尾部的附加控件，如显示密码或扫码按钮。
  final Widget? suffix;
  final Iterable<String>? autofillHints;

  /// 校验 [controller] 当前文字（无 controller 时为最近一次输入）。
  final FormFieldValidator<String>? validator;

  /// 密钥等敏感文本：关闭自动更正、输入建议、个性化学习与智能标点。
  final bool sensitive;

  @override
  Widget build(BuildContext context) {
    final validator = this.validator;
    if (validator == null) return _build(context, errorText, onChanged);
    return FormField<String>(
      key: switch (focusNode) {
        final node? => ValueKey<FocusNode>(node),
        null => null,
      },
      enabled: enabled,
      initialValue: controller?.text,
      validator: (value) => validator(controller?.text ?? value),
      builder: (field) =>
          _build(context, field.errorText ?? errorText, (value) {
            field.didChange(value);
            onChanged?.call(value);
          }),
    );
  }

  Widget _build(
    BuildContext context,
    String? errorText,
    ValueChanged<String>? onChanged,
  ) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    const radius = BorderRadius.all(
      Radius.circular(DesignTokens.componentInputRounded),
    );
    OutlineInputBorder border([BorderSide side = BorderSide.none]) =>
        OutlineInputBorder(borderRadius: radius, borderSide: side);
    final focus = BorderSide(
      color: colors.primary,
      width: DesignTokens.componentControlFocusSize,
    );
    final error = BorderSide(
      color: colors.error,
      width: DesignTokens.componentControlFocusSize,
    );
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      autofocus: autofocus,
      autocorrect: autocorrect && !sensitive,
      enableSuggestions: !sensitive,
      enableIMEPersonalizedLearning: !sensitive,
      smartDashesType: sensitive ? SmartDashesType.disabled : null,
      smartQuotesType: sensitive ? SmartQuotesType.disabled : null,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      maxLength: maxLength,
      autofillHints: autofillHints,
      style: type.body.copyWith(color: enabled ? colors.text : colors.disabled),
      cursorColor: colors.primary,
      decoration: InputDecoration(
        filled: true,
        fillColor: enabled ? colors.inset : colors.disabledContainer,
        hintText: hintText,
        hintStyle: type.body.copyWith(color: colors.textSecondary),
        errorText: errorText,
        errorStyle: type.footnote.copyWith(color: colors.error),
        errorMaxLines: 3,
        helperText: helperText,
        helperStyle: type.footnote.copyWith(color: colors.textSecondary),
        helperMaxLines: 3,
        counterText: '',
        isDense: true,
        constraints: const BoxConstraints(
          minHeight: DesignTokens.componentInputHeight,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentInputPadding,
          vertical: _inputVerticalPadding,
        ),
        suffixIcon: suffix,
        border: border(),
        enabledBorder: border(),
        disabledBorder: border(),
        focusedBorder: border(focus),
        errorBorder: border(error),
        focusedErrorBorder: border(error),
      ),
    );
    if (label == null) return field;
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label!,
            style: type.footnote.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          field,
        ],
      ),
    );
  }
}
