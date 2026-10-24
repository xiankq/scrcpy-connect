import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 进入与退出页面的标题栏可能同时显示公共返回动作。
Finder pageBackButton(WidgetTester tester) => find.byTooltip(
  MaterialLocalizations.of(tester.element(find.byType(Scaffold).last))
      .backButtonTooltip,
);
