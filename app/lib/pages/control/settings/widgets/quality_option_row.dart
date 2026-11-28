import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 画面选项行：`media` 功能色块，行尾显示当前值和箭头，点按打开单选弹层
/// （design.md「手机屏幕与应用」：选择类设置在行尾显示当前值和 `chevron`）。
class QualityOptionRow extends StatelessWidget implements GroupedRow {
  const QualityOptionRow({
    super.key,
    required this.title,
    required this.icon,
    required this.currentValue,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final String currentValue;
  final VoidCallback? onTap;

  @override
  double get separatorIndent => tileRowSeparatorIndent;

  @override
  Widget build(BuildContext context) => ActionRow(
    icon: icon,
    color: FunctionTone.media,
    title: title,
    value: currentValue,
    enabled: onTap != null,
    onTap: onTap,
  );
}
