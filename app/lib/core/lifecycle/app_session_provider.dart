import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session.dart';

export 'package:scrcpy_connect/core/lifecycle/app_session.dart';

final appSessionProvider = Provider<AppSession>(
  (ref) => throw StateError('应用作用域须由启动入口提供。'),
);
