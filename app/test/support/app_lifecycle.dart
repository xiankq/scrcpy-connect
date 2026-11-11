import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

extension TestAppLifecycle on WidgetTester {
  void pauseApp() {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  void resumeApp() {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }
}
