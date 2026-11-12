import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/widgets/system_notification_sink.dart';

part 'system_notification_sink_provider.g.dart';

@Riverpod(keepAlive: true)
SystemNotificationSink systemNotificationSink(Ref ref) =>
    const NoopSystemNotificationSink();
