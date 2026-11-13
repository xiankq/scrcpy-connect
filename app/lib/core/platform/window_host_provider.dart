import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/platform/platform_window_host.dart';

final platformWindowHostProvider = Provider<PlatformWindowHost>(
  (ref) => const PlatformWindowHost(),
);
