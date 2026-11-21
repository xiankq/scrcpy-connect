import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

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
