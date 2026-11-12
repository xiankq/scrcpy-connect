import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(
            top: DesignTokens.spacingSectionTitle,
            bottom: DesignTokens.spacingSm,
          ),
          child: Text(title, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
      if (action != null)
        Padding(
          // 保留标题的不对称留白，同时让完整动作热区随较大内容增长。
          padding: const EdgeInsets.only(
            top: DesignTokens.spacingSectionTitle - DesignTokens.spacingSm,
          ),
          child: action,
        ),
    ],
  );
}
