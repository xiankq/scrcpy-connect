import 'package:hooks_riverpod/hooks_riverpod.dart';

final reconcileStateProvider = Provider<Future<void> Function()>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
