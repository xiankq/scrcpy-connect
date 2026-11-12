import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';

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
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
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
            if (index > 0)
              Icon(
                LucideIcons.chevronRight,
                size: DesignTokens.componentIconSmallSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            _FileBreadcrumbButton(
              crumb: crumbs[index],
              selected: index == crumbs.length - 1,
              onPressed: onSelected == null
                  ? null
                  : () => onSelected!(crumbs[index].path),
            ),
          ],
        ],
      ),
    );
  }
}

class _FileBreadcrumbButton extends StatelessWidget {
  const _FileBreadcrumbButton({
    required this.crumb,
    required this.selected,
    required this.onPressed,
  });

  final FileBreadcrumb crumb;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? ConnectTokens.accent(
              context,
              ConnectTokens.amber,
            ).withValues(alpha: 0.12)
          : theme.colorScheme.surfaceContainerLow,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selected ? null : onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DesignTokens.componentChipHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(
                    LucideIcons.folder,
                    size: DesignTokens.componentIconSmallSize,
                    color: ConnectTokens.amber,
                  ),
                  const SizedBox(width: DesignTokens.spacingXs),
                ],
                Text(
                  crumb.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
