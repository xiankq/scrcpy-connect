import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'live_video/live_video_benchmark.dart';
import 'live_video/live_video_page.dart';

// Deliberately no flutter_test or integration_test binding. The driver binding
// has normal scheduler/render/widget mixins and no Live frame-policy loop.
void main() {
  late final LiveVideoBenchmark benchmark;
  // This constructs the binding, so it must precede ensureInitialized/runApp.
  enableFlutterDriverExtension(
    enableTextEntryEmulation: false,
    handler: (message) => benchmark.handle(message),
  );
  benchmark = LiveVideoBenchmark();
  runApp(ProviderScope(child: LiveVideoPage(benchmark: benchmark)));
}
