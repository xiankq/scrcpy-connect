import 'package:scrcpy_connect/router/navigation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions,
    this.bottom,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading:
          GoRouter.maybeOf(context) != null &&
              (GoRouter.of(context).canPop() ||
                  !['/devices', '/transfers', '/settings'].contains(
                    GoRouter.of(context)
                        .routeInformationProvider
                        .value
                        .uri
                        .path,
                  ))
          ? BackButton(onPressed: () => closePage<void>(context))
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (subtitle != null)
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: actions,
    ),
    body: SafeArea(top: false, child: child),
    bottomNavigationBar: bottom == null
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: bottom,
            ),
          ),
  );
}
