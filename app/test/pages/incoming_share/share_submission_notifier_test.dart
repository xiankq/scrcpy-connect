import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_capabilities_provider.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/pages/incoming_share/share_submission_notifier.dart';
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/pages/incoming_share/widgets/share_device_card.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/router/app_router.dart';

const _share = IncomingShare(
  shareId: 'share',
  status: .ready,
  text: 'text',
  files: [IncomingShareFile(name: 'photo.jpg', localPath: '/local', size: 1)],
);

void main() {
  final scope = Object();
  late _Shares incoming;
  late _Directories directories;
  late _Transfers transfers;
  late _Clipboard clipboard;
  late DeviceReadiness readiness;
  late ProviderContainer container;
  late ShareSubmissionNotifier actions;
  late void Function() leave;
  final provider = shareSubmissionProvider('share', scope: scope);
  final dependencies = _Session();
  const events = Stream<Map<String, dynamic>>.empty();
  sourceOverrides() => [
    appSessionProvider.overrideWithValue(dependencies),
    deviceReaderProvider.overrideWithValue(dependencies.devices),
    incomingSharesProvider.overrideWithValue(incoming),
    fileDirectoriesProvider.overrideWithValue(directories),
    fileTransfersProvider.overrideWithValue(transfers),
    remoteClipboardProvider.overrideWithValue(clipboard),
    runtimeEventsProvider.overrideWithValue(events),
    deviceReadinessProvider('device').overrideWithValue(readiness),
  ];
  Future<void> submit() => actions.submit(
    deviceId: 'device',
    directory: '/sdcard/Download/',
    includeFiles: true,
    includeText: true,
  );
  setUp(() {
    incoming = _Shares();
    directories = _Directories();
    transfers = _Transfers();
    clipboard = _Clipboard();
    readiness = const DeviceReadiness(
      connectionId: 'connection',
      status: .connected,
    );
    container = ProviderContainer(overrides: sourceOverrides());
    final subscription = container.listen(provider, (_, _) {});
    leave = subscription.close;
    actions = container.read(provider.notifier);
  });
  tearDown(() => container.dispose());

  test('重复确认只核验一次目录；换源与离页取消原读取，迟到结果不继续发送', () async {
    final first = submit();
    await submit();
    expect(directories.reads, hasLength(1));
    final old = directories;
    directories = _Directories();
    container.updateOverrides(sourceOverrides());
    await container.pump();
    expect(old.reads.single.cancellation!.isCancelled, isTrue);
    old.complete();
    await first;
    expect(transfers.starts, isEmpty);
    expect(clipboard.writes, isEmpty);
    expect(incoming.consumed, isEmpty);
    expect(container.read(provider).busy, isFalse);
    final retired = submit();
    leave();
    await container.pump();
    expect(directories.reads.single.cancellation!.isCancelled, isTrue);
    directories.complete();
    await retired;
    expect(transfers.starts, isEmpty);
  });

  test('文件已登记后剪贴板失败，明确继续只重试未完成步骤', () async {
    final first = submit();
    directories.complete();
    await _flush(container);
    expect(
      transfers.starts.single.plan.items.single.destination,
      '/sdcard/Download/photo.jpg',
    );
    transfers.accept();
    await _flush(container);
    clipboard.writes.single.completeError(StateError('clipboard unavailable'));
    await first;
    expect(container.read(provider).pushed, isTrue);
    expect(container.read(provider).copied, isFalse);
    expect(container.read(provider).error, contains('clipboard unavailable'));
    final retry = submit();
    expect(directories.reads, hasLength(1));
    expect(transfers.starts, hasLength(1));
    expect(clipboard.writes, hasLength(2));
    clipboard.writes.last.complete();
    await _flush(container);
    expect(incoming.consumed.single.id, 'share');
    incoming.consumed.single.result.complete();
    await retry;
    final result = container.read(provider);
    expect(result.completed, isTrue);
    expect(result.showTransfers, isTrue);
    expect(result.copied, isTrue);
    expect(result.busy, isFalse);
    expect(container.read(shareInboxProvider).shares, isEmpty);
    await submit();
    expect(transfers.starts, hasLength(1));
    expect(clipboard.writes, hasLength(2));
  });

  test('离页保留已登记的原传输，不再执行剪贴板或消费分享', () async {
    final sending = submit();
    directories.complete();
    await _flush(container);
    expect(transfers.starts, hasLength(1));
    leave();
    await container.pump();
    transfers.accept();
    await sending;
    expect(transfers.cancelled, isEmpty);
    expect(clipboard.writes, isEmpty);
    expect(incoming.consumed, isEmpty);
  });

  test('部分成功后关闭只结束分享，不自动进入传输中心', () async {
    final sending = submit();
    directories.complete();
    await _flush(container);
    transfers.accept();
    await _flush(container);
    clipboard.writes.single.completeError(StateError('clipboard unavailable'));
    await sending;
    final closing = actions.cancel();
    incoming.consumed.single.result.complete();
    await closing;
    expect(container.read(provider).completed, isTrue);
    expect(container.read(provider).pushed, isTrue);
    expect(container.read(provider).showTransfers, isFalse);
    expect(transfers.cancelled, isEmpty);
  });

  test('消费期间换源，旧完成回执不能关闭新页面或消费新分享', () async {
    final closing = actions.cancel();
    final previous = incoming;
    expect(previous.consumed, hasLength(1));
    incoming = _Shares();
    container.updateOverrides(sourceOverrides());
    await container.pump();
    await container.read(shareInboxProvider.notifier).load();
    previous.consumed.single.result.complete();
    await closing;
    expect(container.read(provider).completed, isFalse);
    expect(container.read(provider).busy, isFalse);
    expect(incoming.consumed, isEmpty);
    expect(container.read(shareInboxProvider).shares.single.shareId, 'share');
  });

  test('目录核验期间连接身份变化，旧确认不能提交到新连接', () async {
    final sending = submit();
    readiness = const DeviceReadiness(
      connectionId: 'replacement',
      status: .connected,
    );
    container.updateOverrides(sourceOverrides());
    await container.pump();
    directories.complete();
    await sending;
    expect(transfers.starts, isEmpty);
    expect(clipboard.writes, isEmpty);
    expect(container.read(provider).error, contains('设备连接已变化'));
    expect(container.read(provider).busy, isFalse);
  });

  test('同路径但异设备的目录回执不能作为发送准入', () async {
    final sending = submit();
    directories.reads.single.result.complete(
      const FileDirectorySnapshot(deviceId: 'other', path: '/sdcard/Download'),
    );
    await sending;
    expect(transfers.starts, isEmpty);
    expect(container.read(provider).error, contains('无法核验'));
  });

  testWidgets('分享页面独立提交，完成后关闭自身并打开传输中心', (tester) async {
    tester.view.physicalSize = const Size(1000, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/devices',
      routes: [
        GoRoute(
          path: '/devices',
          builder: (_, _) => const Scaffold(body: Text('devices')),
        ),
        GoRoute(
          path: '/sharing/share',
          builder: (_, _) => const IncomingSharePage(share: _share),
        ),
        GoRoute(
          path: const TransferCenterRoute().location,
          builder: (_, _) => const Scaffold(body: Text('transfers')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ConnectTokens.theme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final visiting = router.push<void>('/sharing/share');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ShareDeviceCard));
    await tester.pump();
    await tester.tap(find.text('确认提交'));
    await tester.pump();
    directories.complete();
    await tester.pump();
    transfers.accept();
    await tester.pump();
    clipboard.writes.single.complete();
    await tester.pump();
    incoming.consumed.single.result.complete();
    await tester.pumpAndSettle();
    await visiting;
    expect(find.text('transfers'), findsOneWidget);
    expect(find.byType(IncomingSharePage), findsNothing);
    expect(incoming.consumed, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Directories implements FileDirectories {
  final reads =
      <
        ({
          FileCancellation? cancellation,
          Completer<FileDirectorySnapshot> result,
        })
      >[];
  @override
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  }) {
    final result = Completer<FileDirectorySnapshot>();
    reads.add((cancellation: cancellation, result: result));
    return result.future;
  }

  void complete() => reads.last.result.complete(
    const FileDirectorySnapshot(deviceId: 'device', path: '/sdcard/Download'),
  );
}

class _Transfers implements FileTransfers {
  final starts =
      <({FileTransferPlan plan, Completer<FileTransferSubmission> result})>[];
  final cancelled = <FileTransferTarget>[];
  @override
  Future<FileTransferSubmission> startTransfer(
    FileTransferPlan plan, {
    String? shareId,
  }) {
    final result = Completer<FileTransferSubmission>();
    starts.add((plan: plan, result: result));
    return result.future;
  }

  void accept() => starts.last.result.complete(
    const FileTransferSubmission(
      batchId: 'batch',
      transferId: 'task',
      itemCount: 1,
      status: .submitted,
    ),
  );
  @override
  Future<void> cancelTransfer(FileTransferTarget target) async =>
      cancelled.add(target);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Clipboard implements RemoteClipboard {
  final writes = <Completer<void>>[];
  @override
  Future<void> writeClipboard(ClipboardTarget target, String text) {
    final result = Completer<void>();
    writes.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shares implements IncomingShares {
  final consumed = <({String id, Completer<void> result})>[];
  @override
  Future<List<IncomingShare>> readIncomingShares() async => [_share];
  @override
  Future<void> consumeShare(String id) {
    final result = Completer<void>();
    consumed.add((id: id, result: result));
    return result.future;
  }
}

class _Session implements AppSession {
  final DeviceReader devices = _Devices();
  @override
  final initialState = AppState(
    pendingShares: [_share],
    devices: [
      const DeviceSnapshot(
        id: 'device',
        name: 'Phone',
        status: .connected,
        connectionId: 'connection',
      ),
    ],
    loading: false,
  );
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  bool get initialize => false;
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Devices implements DeviceReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}
