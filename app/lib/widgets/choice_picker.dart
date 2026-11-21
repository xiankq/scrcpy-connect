import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
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
    final selected = isSelected(option);
    return Builder(
      builder: (context) => ListTile(
        title: Text(label(option)),
        subtitle: reason == null || reason.isEmpty ? null : Text(reason),
        enabled: reason == null,
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
        ),
        trailing: selected ? const Icon(LucideIcons.check) : null,
        onTap: reason == null ? () => Navigator.pop(context, option) : null,
      ),
    );
  }).toList();
  Widget content(BuildContext context) => SafeArea(
    top: false,
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingSm),
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
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0,
            constraints: const BoxConstraints(maxWidth: 440),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                DesignTokens.componentSheetRounded,
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
class ChoiceField extends StatelessWidget {
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onPressed == null
          ? null
          : () {
              final box = context.findRenderObject()! as RenderBox;
              onPressed!(box.localToGlobal(box.size.center(Offset.zero)));
            },
      borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          enabled: onPressed != null,
          contentPadding: label == null
              ? const EdgeInsetsDirectional.fromSTEB(
                  DesignTokens.spacingSm,
                  DesignTokens.spacingXs,
                  DesignTokens.spacingXs,
                  DesignTokens.spacingXs,
                )
              : null,
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
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: label == null ? Theme.of(context).textTheme.labelLarge : null,
        ),
      ),
    ),
  );
}
