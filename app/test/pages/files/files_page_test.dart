import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_changes_provider.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/models/preferences_state.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/files/files_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

const _device = DeviceSnapshot(id: 'phone', name: '测试手机');

void main() {
  testWidgets('从多级子目录返回时复用父目录列表和滚动位置', (tester) async {
    final directories = _Directories({
      '/sdcard': [_folder('/sdcard/相机')],
      '/sdcard/相机': [
        for (var index = 0; index < 35; index++)
          _folder('/sdcard/相机/folder${index.toString().padLeft(2, '0')}'),
        _folder('/sdcard/相机/相册'),
      ],
      '/sdcard/相机/相册': [_folder('/sdcard/相机/相册/子目录')],
      '/sdcard/相机/相册/子目录': [
        const FileCatalogEntry(
          name: 'photo.jpg',
          path: '/sdcard/相机/相册/子目录/photo.jpg',
        ),
      ],
    });
    await _showFiles(tester, directories);
    await tester.tap(find.text('相机'));
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('相册'),
      320,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    double scrollOffset() =>
        tester.state<ScrollableState>(scrollable).position.pixels;
    final before = scrollOffset();
    expect(before, greaterThan(0));

    await tester.tap(find.text('相册').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('子目录').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('photo.jpg').hitTestable(), findsOneWidget);

    for (final label in ['子目录', '相册', '相机']) {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(label).hitTestable(), findsOneWidget);
      if (label == '相册') expect(scrollOffset(), closeTo(before, 1));
    }
    expect(directories.reads, [
      '/sdcard',
      '/sdcard/相机',
      '/sdcard/相机/相册',
      '/sdcard/相机/相册/子目录',
    ]);
  });

  testWidgets('后台核验时显示旧目录，新结果原位合并到现有列表', (tester) async {
    const retained = FileCatalogEntry(
      name: 'retained.jpg',
      path: '/sdcard/retained.jpg',
    );
    const removed = FileCatalogEntry(
      name: 'zz-removed.jpg',
      path: '/sdcard/zz-removed.jpg',
    );
    final folder = _folder('/sdcard/相机');
    final directories = _Directories({
      '/sdcard': [folder, retained, removed],
      '/sdcard/相机': [],
    });
    final changes = StreamController<FileChange>.broadcast(sync: true);
    addTearDown(changes.close);
    await _showFiles(tester, directories, changes: changes.stream);
    final row = find.text('retained.jpg').hitTestable();
    final originalPosition = tester.getTopLeft(row);
    await tester.tap(find.text('相机'));
    await tester.pumpAndSettle();

    changes.add(
      const FileChange(
        FileChangeKind.directory,
        deviceId: 'phone',
        path: '/sdcard',
      ),
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 200));

    expect(row, findsOneWidget);
    expect(find.text('zz-removed.jpg').hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(row), originalPosition);
    final oldElement = tester.element(row);

    directories.pending['/sdcard']!.complete(
      FileDirectorySnapshot(
        deviceId: _device.id,
        path: '/sdcard',
        entries: [
          folder,
          retained,
          const FileCatalogEntry(name: 'new.jpg', path: '/sdcard/new.jpg'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('new.jpg').hitTestable(), findsOneWidget);
    expect(find.text('zz-removed.jpg'), findsNothing);
    expect(tester.element(row), same(oldElement));
    expect(tester.getTopLeft(row).dy, greaterThan(originalPosition.dy));
    expect(directories.reads, ['/sdcard', '/sdcard/相机', '/sdcard']);
  });
}

FileCatalogEntry _folder(String path) => FileCatalogEntry(
  name: path.split('/').last,
  path: path,
  kind: 'directory',
  isDirectory: true,
);

Future<void> _showFiles(
  WidgetTester tester,
  FileDirectories directories, {
  Stream<FileChange> changes = const Stream.empty(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceListProvider.overrideWith(_Devices.new),
        deviceReadinessProvider(_device.id).overrideWith(
          (_) => const DeviceReadiness(
            connectionId: 'connection',
            status: DeviceConnectionStatus.connected,
          ),
        ),
        preferencesProvider.overrideWith(_Preferences.new),
        recoveryStateProvider.overrideWith(_Recovery.new),
        fileChangesProvider.overrideWithValue(changes),
        fileDirectoriesProvider.overrideWithValue(directories),
        fileMutationsProvider.overrideWithValue(_Mutations()),
        fileTransfersProvider.overrideWithValue(_Transfers()),
      ],
      child: MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: const FilesPage(device: _device),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Directories implements FileDirectories {
  _Directories(this.entries);
  final Map<String, List<FileCatalogEntry>> entries;
  final reads = <String>[];
  final pending = <String, Completer<FileDirectorySnapshot>>{};

  @override
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  }) async {
    final path = target.path;
    final repeat = reads.contains(path);
    reads.add(path);
    if (repeat) return (pending[path] = Completer()).future;
    return FileDirectorySnapshot(
      deviceId: target.deviceId,
      path: path,
      entries: entries[path]!,
    );
  }
}

class _Devices extends DeviceListNotifier {
  @override
  DeviceListState build() =>
      DeviceListState(devices: [_device], loading: false);
}

class _Preferences extends PreferencesNotifier {
  @override
  PreferencesState build() =>
      PreferencesState(values: Preferences(fileViewMode: .list));
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}

class _Mutations implements FileMutations {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transfers implements FileTransfers {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
