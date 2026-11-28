import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/widgets/chips.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';

/// 路径 chip 之间的间距（Ardot F2 2:1357 路径行：间距 8）。
const _crumbGap = DesignTokens.spacingSm;

/// 路径行（design.md「文件与相册」：路径用 chip 行，当前目录 chip 选中）。
class FileBreadcrumbs extends HookWidget {
  const FileBreadcrumbs({
    super.key,
    required this.path,
    required this.onSelected,
  });

  final String path;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final scroll = useScrollController();
    final reduceMotion = reduceMotionOf(context);
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scroll.hasClients) return;
        final end = scroll.position.maxScrollExtent;
        if (reduceMotion) {
          scroll.jumpTo(end);
        } else {
          scroll.animateTo(
            end,
            duration: shortTransitionDuration,
            curve: standardCurve,
          );
        }
      });
      return null;
    }, [path, scroll]);
    final crumbs = fileBreadcrumbs(path);
    return SingleChildScrollView(
      controller: scroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < crumbs.length; index++) ...[
            if (index > 0) const SizedBox(width: _crumbGap),
            AppChip(
              label: crumbs[index].label,
              selected: index == crumbs.length - 1,
              onPressed: onSelected == null
                  ? null
                  : index == crumbs.length - 1
                  ? () {}
                  : () => onSelected!(crumbs[index].path),
            ),
          ],
        ],
      ),
    );
  }
}
