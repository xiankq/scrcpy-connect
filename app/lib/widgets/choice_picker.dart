import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
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
  Widget content(BuildContext context) => SafeArea(
    top: false,
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsetsDirectional.fromSTEB(
        DesignTokens.componentPickerPadding,
        DesignTokens.spacingXs,
        DesignTokens.componentPickerPadding,
        DesignTokens.spacingSm,
      ),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: DesignTokens.spacingMd,
            end: DesignTokens.spacingXxs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
        ...rows,
      ],
    ),
  );

  return centered
      ? showAppDialog<T>(
          context: context,
          anchorPoint: position,
          builder: (context) => Dialog(
            backgroundColor: DialogTheme.of(context).backgroundColor,
            elevation: 0,
            constraints: const BoxConstraints.tightFor(
              width: DesignTokens.componentPickerWidth,
            ),
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(DesignTokens.componentPickerRounded),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: content(context),
          ),
        )
      : showAppModalSheet<T>(
          context: context,
          anchorPoint: position,
          builder: content,
        );
}

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
  Widget build(BuildContext context) => Semantics(
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
      borderRadius: BorderRadius.circular(
        DesignTokens.componentSelectionFieldRounded,
      ),
      child: InputDecorator(
        isFocused: _focused,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: widget.errorText,
          enabled: widget.onPressed != null,
          constraints: const BoxConstraints(
            minHeight: DesignTokens.componentSelectionFieldHeight,
          ),
          contentPadding: const EdgeInsetsDirectional.fromSTEB(
            DesignTokens.componentSelectionFieldPadding,
            DesignTokens.componentSelectionFieldVerticalPadding,
            DesignTokens.spacingXs,
            DesignTokens.componentSelectionFieldVerticalPadding,
          ),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(DesignTokens.componentSelectionFieldRounded),
            ),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(
              Radius.circular(DesignTokens.componentSelectionFieldRounded),
            ),
            borderSide: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? DesignTokens.componentControlFocusDarkBorderColor
                  : DesignTokens.componentControlFocusBorderColor,
              width: DesignTokens.componentControlFocusSize,
            ),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: DesignTokens.componentIconButtonSize,
          ),
          suffixIcon: const Icon(
            LucideIcons.chevronDown,
            size: DesignTokens.componentIconSmallSize,
          ),
        ),
        isEmpty: false,
        child: Text(
          widget.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.label == null
              ? Theme.of(context).textTheme.labelLarge
              : null,
        ),
      ),
    ),
  );
}
