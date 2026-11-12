import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'remote_clipboard.dart';

final remoteClipboardProvider = Provider<RemoteClipboard>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
