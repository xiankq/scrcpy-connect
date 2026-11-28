import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

Future<T?> showChoicePicker<T>({
  required BuildContext context,
  required String title,
  required Iterable<T> options,
  required String Function(T) label,
  required bool Function(T) isSelected,
  String? Function(T)? disabledReason,
  Offset? anchorPoint,
}) {
  final window = windowEnvironmentOf(context);
  final width = window.width - window.insets.left - window.insets.right;
  final centered =
      window.isDesktopWindow ||
      WindowEnvironment.sizeClassFor(width) != WindowSizeClass.compact;
  final object = context.findRenderObject();
  final position =
      anchorPoint ??
      (object is RenderBox && object.hasSize
          ? object.localToGlobal(object.size.center(Offset.zero))
          : null);
  final rows = options.map((option) {
    final reason = disabledReason?.call(option);
    return Builder(
      builder: (context) => ChoiceRow<T>(
        value: option,
        title: Text(label(option)),
        selected: isSelected(option),
        disabledReason: reason,
        onChanged: reason == null
            ? (value) => Navigator.pop(context, value)
            : null,
      ),
    );
  }).toList();
  // 单选弹层：标题栏 + 一张分组卡片，当前项行尾为 primary 对勾（Ardot 37:1361 / 37:1398）。
  Widget content(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: title,
            trailing: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                DesignTokens.componentSheetPadding,
                DesignTokens.spacingSm,
                DesignTokens.componentSheetPadding,
                centered ? DesignTokens.spacingLg : _sheetBottomPadding,
              ),
              child: SettingsGroup(
                separatorIndent: DesignTokens.componentListRowPadding,
                children: rows,
              ),
            ),
          ),
        ],
      ),
    );
  }

  return centered
      ? showAppDialog<T>(
          context: context,
          anchorPoint: position,
          builder: (context) => Dialog(
            backgroundColor: AppColors.of(context).page,
            elevation: 0,
            insetPadding: const EdgeInsets.all(DesignTokens.spacingXxl),
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.componentFormSheetWidth,
            ),
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(DesignTokens.componentFormSheetRounded),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
              child: content(context),
            ),
          ),
        )
      : showAppModalSheet<T>(
          context: context,
          anchorPoint: position,
          builder: content,
        );
}

/// Ardot「单选弹层 / 抽屉」37:1361 下内距 40。
const _sheetBottomPadding = DesignTokens.spacingJumbo;

/// The trigger stays in its form while the selection gets a modal route.
class ChoiceField extends StatefulWidget {
  const ChoiceField({
    super.key,
    required this.value,
    required this.onPressed,
    this.label,
    this.errorText,
  });

  final String value;
  final String? label;
  final String? errorText;
  final Future<void> Function(Offset anchor)? onPressed;

  @override
  State<ChoiceField> createState() => _ChoiceFieldState();
}

class _ChoiceFieldState extends State<ChoiceField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    const radius = BorderRadius.all(
      Radius.circular(DesignTokens.componentInputRounded),
    );
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      child: InkWell(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onTap: widget.onPressed == null
            ? null
            : () {
                final box = context.findRenderObject()! as RenderBox;
                widget.onPressed!(
                  box.localToGlobal(box.size.center(Offset.zero)),
                );
              },
        borderRadius: radius,
        child: InputDecorator(
          isFocused: _focused,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: widget.errorText,
            enabled: enabled,
            filled: true,
            fillColor: colors.inset,
            constraints: const BoxConstraints(
              minHeight: DesignTokens.componentInputHeight,
            ),
            contentPadding: const EdgeInsetsDirectional.fromSTEB(
              DesignTokens.componentInputPadding,
              DesignTokens.spacingMd,
              DesignTokens.spacingXs,
              DesignTokens.spacingMd,
            ),
            border: const OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(
                color: colors.primary,
                width: DesignTokens.componentControlFocusSize,
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: DesignTokens.componentBarButtonSize,
              minHeight: DesignTokens.componentBarButtonSize,
            ),
            suffixIcon: Icon(
              LucideIcons.chevronDown,
              size: DesignTokens.componentChevronSize,
              color: enabled ? colors.textSecondary : colors.disabled,
            ),
          ),
          isEmpty: false,
          child: Text(
            widget.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.body.copyWith(
              color: enabled ? colors.text : colors.disabled,
            ),
          ),
        ),
      ),
    );
  }
}
