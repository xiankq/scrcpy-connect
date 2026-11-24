import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';

/// 紧凑视觉尺寸与独立的无障碍触摸目标。
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
    final duration = reduceMotionOf(context)
        ? Duration.zero
        : kThemeAnimationDuration;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      onTap: toggle,
      child: SizedBox(
        width: DesignTokens.componentSwitchTrackWidth,
        height: DesignTokens.componentIconButtonSize,
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
                DesignTokens.componentSwitchTrackPadding,
              ),
              decoration: BoxDecoration(
                color: onChanged == null
                    ? colors.brightness == Brightness.dark
                          ? DesignTokens
                                .componentControlDisabledDarkBackgroundColor
                          : DesignTokens.componentControlDisabledBackgroundColor
                    : value
                    ? colors.primary
                    : colors.brightness == Brightness.dark
                    ? DesignTokens.componentSwitchTrackOffDarkBackgroundColor
                    : DesignTokens.componentSwitchTrackOffBackgroundColor,
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
                      color: onChanged == null
                          ? Theme.of(context).disabledColor
                          : value
                          ? colors.onPrimary
                          : DesignTokens.componentSwitchThumbBackgroundColor,
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

class ConnectSegmentedControl<T> extends StatelessWidget {
  const ConnectSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.all(
          DesignTokens.componentSegmentedTrackPadding,
        ),
        child: Row(
          children: [
            for (final (value, label) in options)
              Expanded(
                child: Semantics(
                  selected: selected == value,
                  child: TextButton(
                    onPressed: onSelected == null
                        ? null
                        : () => onSelected!(value),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.standard,
                      animationDuration: reduceMotionOf(context)
                          ? Duration.zero
                          : shortTransitionDuration,
                      minimumSize: const Size(
                        0,
                        DesignTokens.componentSegmentedTrackHeight -
                            2 * DesignTokens.componentSegmentedTrackPadding,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingXxs,
                      ),
                      backgroundColor: selected == value
                          ? colors.primary
                          : null,
                      foregroundColor: selected == value
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                      disabledBackgroundColor: selected == value
                          ? colors.surfaceContainerHigh
                          : null,
                      disabledForegroundColor: theme.disabledColor,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(
                            DesignTokens.componentSegmentedItemRounded,
                          ),
                        ),
                      ),
                      textStyle: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: selected == value
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    child: Text(label, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shape for a single solid action anchored to the content column.
const pagePrimaryButtonStyle = ButtonStyle(
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(DesignTokens.componentButtonPrimaryRounded),
      ),
    ),
  ),
);
