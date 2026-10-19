import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The public back action can coexist on entering and leaving page headers.
Finder pageBackButton(WidgetTester tester) => find.byTooltip(
  MaterialLocalizations.of(tester.element(find.byType(Scaffold).last))
      .backButtonTooltip,
);
