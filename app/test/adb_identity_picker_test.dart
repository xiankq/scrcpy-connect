import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/settings/adb_identity/settings_adb_identity_page.dart';
import 'package:scrcpy_connect/models/adb_identity_validation.dart';
import 'package:scrcpy_connect/stores/app_store.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

// 合成载荷仅验证界面传输；RSA 有效性由后端负责。
const pem = '-----BEGIN PRIVATE KEY-----\nMAMCAQA=\n-----END PRIVATE KEY-----';
const device = <String, dynamic>{'id': 'phone', 'name': '我的手机'};

final class _MemoryFile extends PlatformFile {
  _MemoryFile(this.bytes, {this.knownLength, this.failure});
  final List<int> bytes;
  final int? knownLength;
  final Object? failure;
  var reads = 0;
  @override
  String get name => 'key.pem';
  @override
  Uri get uri => Uri.file('/private/not-to-be-logged/key.pem');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => knownLength;
  @override
  Future<int?> length() async => knownLength;
  @override
  Future<Uint8List> readAsBytes() => throw StateError('Use bounded stream');
  @override
  Stream<Uint8List> readAsByteStream() async* {
    reads++;
    if (failure != null) throw failure!;
    for (var offset = 0; offset < bytes.length; offset += 1024) {
      yield Uint8List.fromList(
        bytes.sublist(offset, (offset + 1024).clamp(0, bytes.length)),
      );
    }
  }
}

class _Picker extends FilePickerPlatform {
  Future<PlatformFile?> Function() next = () async => null;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => next();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> open(
  WidgetTester tester,
  AppStore controller, {
  bool narrow = false,
}) async {
  tester.view.physicalSize = narrow
      ? const Size(280, 620)
      : const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = narrow ? 2 : 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    RouterTestApp(
      controller: controller,
      devices: [device],
      theme: ConnectTokens.theme(narrow ? Brightness.dark : Brightness.light),
      home: AdbIdentityPage(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
  await reveal(tester, find.widgetWithText(FilledButton, '导入私钥'));
  await tester.tap(find.widgetWithText(FilledButton, '导入私钥'));
  await tester.pumpAndSettle();
}

void main() {
  late _Picker picker;
  setUp(() {
    final previous = FilePickerPlatform.instance;
    picker = _Picker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
  });
  testWidgets(
    'file and text follow the same confirmed import contract without paths or settings writes',
    (tester) async {
      final mutations = <(String, Json)>[];
      for (final scenario in [('global-file', true), ('global-text', false)]) {
        final calls = <String>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          calls.add(command);
          if (command.endsWith('.import')) mutations.add((command, params));
          return command.startsWith('identity.')
              ? {'scope': 'global', 'fingerprint': 'SHA256:public-only'}
              : <String, dynamic>{};
        });
        await open(tester, controller);
        final count = mutations.length;
        if (scenario.$2) {
          picker.next = () async => _MemoryFile(
            utf8.encode('\uFEFF${pem.replaceAll('\n', '\r\n')}\r\n'),
          );
          await reveal(tester, find.text('从文件选择'));
          await tester.tap(find.text('从文件选择'));
          await tester.pumpAndSettle();
        } else {
          await tester.enterText(find.byType(TextFormField), pem);
        }
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          pem,
        );
        expect(mutations, hasLength(count));
        await reveal(tester, find.text('继续'));
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        expect(mutations, hasLength(count));
        await reveal(tester, find.text('导入并更换'));
        await tester.tap(find.text('导入并更换'));
        await tester.pumpAndSettle();
        expect(mutations.last.$1, 'identity.global.import');
        expect(mutations.last.$2, {'privateKeyPem': pem});
        expect(calls.where((c) => c.startsWith('identity.device.')), isEmpty);
        expect(
          calls.where(
            (c) =>
                c.startsWith('settings.') ||
                c.startsWith('files.') ||
                c.startsWith('transfers.'),
          ),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
      expect(mutations[0].$2, mutations[1].$2);
    },
  );
  testWidgets(
    'picker cancellation preserves typed text and malformed text never reaches confirmation',
    (tester) async {
      final calls = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add(command);
        return {'scope': 'global', 'fingerprint': 'SHA256:public-only'};
      });
      addTearDown(controller.dispose);
      await open(tester, controller, narrow: true);
      await tester.enterText(find.byType(TextFormField), 'my draft text');
      await reveal(tester, find.text('从文件选择'));
      await tester.tap(find.text('从文件选择'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'my draft text',
      );
      await reveal(tester, find.text('继续'));
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('PEM 私钥格式无效'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'my draft text',
      );
      await reveal(tester, find.text('继续'));
      expect(find.text('导入并更换'), findsNothing);
      expect(calls.where((c) => c.endsWith('.import')), isEmpty);
    },
  );
  testWidgets(
    'file size read errors and binary failures preserve the draft and redact platform details',
    (tester) async {
      final calls = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add(command);
        return {'scope': 'global', 'fingerprint': 'SHA256:public-only'};
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      await tester.enterText(find.byType(TextFormField), 'keep this draft');
      final knownLarge = _MemoryFile(
        [],
        knownLength: maxAdbPrivateKeyBytes + 1,
      );
      final cases = [
        ('known-large', knownLarge, '私钥文件不能超过 32 KiB。'),
        (
          'stream-large',
          _MemoryFile(List.filled(maxAdbPrivateKeyBytes + 1, 65)),
          '私钥文件不能超过 32 KiB。',
        ),
        ('binary', _MemoryFile([0xff, 0xfe]), '文件不是 UTF-8 文本，请选择 PEM 私钥文件。'),
        ('control', _MemoryFile([0, 1]), '文件不是 UTF-8 文本，请选择 PEM 私钥文件。'),
        (
          'unreadable',
          _MemoryFile(
            [],
            failure: const FormatException(
              '/private/not-to-be-logged/key.pem SECRET',
            ),
          ),
          '无法读取所选文件，请重新选择。',
        ),
      ];
      for (final (_, file, message) in cases) {
        picker.next = () async => file;
        await reveal(tester, find.text('从文件选择'));
        await tester.tap(find.text('从文件选择'));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          'keep this draft',
        );
        expect(find.textContaining('not-to-be-logged'), findsNothing);
        expect(find.textContaining('SECRET'), findsNothing);
      }
      picker.next = () async => _MemoryFile(utf8.encode('not a PEM key'));
      await reveal(tester, find.text('从文件选择'));
      await tester.tap(find.text('从文件选择'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'not a PEM key',
      );
      expect(find.text('PEM 私钥格式无效'), findsOneWidget);
      await reveal(tester, find.text('继续'));
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('导入并更换'), findsNothing);
      expect(knownLarge.reads, 0);
      expect(calls.where((c) => c.endsWith('.import')), isEmpty);
    },
  );
  testWidgets('closing the input discards a late file picker result', (
    tester,
  ) async {
    final calls = <String>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      calls.add(command);
      return {'scope': 'global', 'fingerprint': 'SHA256:public-only'};
    });
    addTearDown(controller.dispose);
    await open(tester, controller);
    final pending = Completer<PlatformFile?>();
    picker.next = () => pending.future;
    await reveal(tester, find.text('从文件选择'));
    await tester.tap(find.text('从文件选择'));
    await tester.pump();
    await reveal(tester, find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    pending.complete(_MemoryFile(utf8.encode(pem)));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(calls.where((c) => c.endsWith('.import')), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
