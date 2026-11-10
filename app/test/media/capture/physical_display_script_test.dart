import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/physical_display_script.dart';

const _owner = '0123456789abcdef0123456789abcdef';
const _nextOwner = 'fedcba9876543210fedcba9876543210';

void main() {
  if (!Platform.isLinux) {
    test('主机脚本夹具需要 Linux 的 /proc 进程身份', () {}, skip: true);
    return;
  }
  late _ShellFixture f;
  setUp(() async => f = await _ShellFixture.open());
  tearDown(() async => f.close());

  test('扫描无租约明确 empty，不创建远端根', () async {
    final scan = await f.recoverCurrent();
    expect(await scan.line(), '__DISPLAY_CURRENT__$_nextOwner:empty');
    expect(await scan.exit(), 0);
    expect(await f.lease.exists(), isFalse);
  });

  test('扫描坏格式和匿名 gate 不能伪报 empty', () async {
    await f.lease.create();
    await f.file('format').writeAsString('future-format\n');
    final corrupt = await f.recoverCurrent();
    expect(await corrupt.exit(), 43);
    expect(await corrupt.output.moveNext(), isFalse);
    await f.file('format').writeAsString('interop-display-v1\n');
    await Directory('${f.lease.path}/owners').create();
    await Directory('${f.lease.path}/gate').create();
    final anonymous = await f.recoverCurrent();
    expect(await anonymous.exit(), 41);
    expect(await anonymous.output.moveNext(), isFalse);
  });

  test('发现旧 owner 后未授权不恢复，精确重试持久 DONE 后才 ACK', () async {
    final old = await f.started();
    old.process.kill(ProcessSignal.sigkill);
    await old.exit();
    final discovery = await f.recoverCurrent();
    expect(await discovery.line(), '__DISPLAY_CURRENT__$_nextOwner:$_owner');
    expect(await f.override.readAsString(), '640x960\n');
    await discovery.input.close();
    expect(await discovery.exit(), 43);
    expect(await f.file('owners/$_owner/done').exists(), isFalse);
    final retry = await f.recoverCurrent();
    expect(await retry.line(), '__DISPLAY_CURRENT__$_nextOwner:$_owner');
    await retry.send('RECOVER:$_nextOwner:$_owner');
    expect(await retry.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await retry.exit(), 0);
    expect(await f.override.exists(), isFalse);
    expect(await f.read('owners/$_owner/done'), 'restored');
    final ack = await f.acknowledge(_owner);
    expect(await ack.line(), '__DISPLAY_ACK__$_owner');
    expect(await ack.exit(), 0);
    expect(await f.file('current').exists(), isFalse);
  });

  test('current 尾随数据及损坏 DONE 不能降格为有效身份', () async {
    final old = await f.started();
    await old.send('STOP:$_owner');
    await old.line();
    await old.exit();
    await f.file('current').writeAsString('$_owner\nextra\n');
    final badCurrent = await f.recoverCurrent();
    expect(await badCurrent.exit(), 43);
    expect(await badCurrent.output.moveNext(), isFalse);
    await f.file('current').writeAsString('$_owner\n');
    await f.file('owners/$_owner/done').writeAsString('restored\nextra\n');
    final badDone = await f.recoverCurrent();
    expect(await badDone.exit(), 43);
    expect(await badDone.output.moveNext(), isFalse);
  });

  test('扫描不能恢复仍存活的当前窗口', () async {
    final old = await f.started();
    final scan = await f.recoverCurrent();
    expect(await scan.exit(), 41);
    expect(await scan.output.moveNext(), isFalse);
    expect(await f.override.readAsString(), '640x960\n');
    await old.send('STOP:$_owner');
    await old.line();
    await old.exit();
  });

  test('短启动命令完整收取脚本，未收到 START 不建立租约', () async {
    expect(utf8.encode(physicalDisplayBootstrap).length, lessThan(4000));
    final process = await f.program();
    await process.input.close();
    expect(await process.exit(), 40);
    expect(await f.lease.exists(), isFalse);
    expect(await f.mutations(), isEmpty);
  });

  test('先交付精确身份，RUN 之前不改变覆盖，STOP 可结束未启动租约', () async {
    final process = await f.program();
    await process.send('START:$_owner');
    final identity = await process.line();
    expect(
      identity,
      matches('^__DISPLAY_OWNER__$_owner:[1-9][0-9]*:[1-9][0-9]*\$'),
    );
    expect(await f.mutations(), isEmpty);
    expect(await f.read('owners/$_owner/original'), 'reset');
    await process.send('STOP:$_owner');
    expect(await process.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await process.exit(), 0);
    expect(await f.mutations(), isEmpty);
  });

  test('START 与 RUN 之间的外部修改不得被首次覆盖', () async {
    final process = await f.program();
    await process.send('START:$_owner');
    await process.line();
    await f.override.writeAsString('800x1600\n');
    await process.send('RUN:$_owner');
    expect(await process.line(), '__DISPLAY_DONE__$_owner:preserved');
    expect(await process.exit(), 43);
    expect(await f.override.readAsString(), '800x1600\n');
    expect(await f.mutations(), isEmpty);
  });

  test('原覆盖与旋转保持，序号匹配调整回执，停止恢复原覆盖', () async {
    await f.override.writeAsString('800x1600\n');
    final process = await f.started();
    expect(await f.override.readAsString(), '640x960\n');
    await f.rotation.writeAsString('1\n');
    await process.send('RESIZE:$_owner:7:960:640');
    expect(await process.line(), '__DISPLAY_SIZE__$_owner:7:960:640');
    expect(await f.override.readAsString(), '640x960\n');
    await process.send('STOP:$_owner');
    expect(await process.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await process.exit(), 0);
    expect(await f.override.readAsString(), '800x1600\n');
    expect(await f.rotation.readAsString(), '1\n');
    expect(await f.mutations(), ['640x960', '640x960', '800x1600']);
  });

  test('无原覆盖时 EOF 恢复 reset，重复恢复读取持久 DONE', () async {
    final process = await f.started();
    await process.input.close();
    expect(await process.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await process.exit(), 0);
    expect(await f.override.exists(), isFalse);
    final recovered = await f.recover(_owner);
    expect(await recovered.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await recovered.exit(), 0);
    expect(await f.mutations(), ['640x960', 'reset']);
  });

  test('运行期间外部覆盖被保留，不改旋转和密度', () async {
    final process = await f.started();
    await f.override.writeAsString('777x1333\n');
    await process.send('STOP:$_owner');
    expect(await process.line(), '__DISPLAY_DONE__$_owner:preserved');
    expect(await process.exit(), 0);
    expect(await f.override.readAsString(), '777x1333\n');
    expect(await f.mutations(), ['640x960']);
    expect(await f.read('owners/$_owner/done'), 'preserved');
  });

  test('恢复调用失败不发布 DONE，原记录可在失败解除后重试', () async {
    final process = await f.started();
    await f.failRestore.writeAsString('1');
    await process.send('STOP:$_owner');
    expect(await process.exit(), 43);
    expect(await f.file('owners/$_owner/done').exists(), isFalse);
    expect(await f.read('owners/$_owner/original'), 'reset');
    expect(await f.override.readAsString(), '640x960\n');
    await f.failRestore.delete();
    final recovered = await f.recover(_owner);
    expect(await recovered.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await recovered.exit(), 0);
    expect(await f.override.exists(), isFalse);
  });

  test('setter 返回零但没有实际应用时不确认 READY 或恢复成功', () async {
    await f.ignoreWrites.writeAsString('1');
    final process = await f.program();
    await process.send('START:$_owner');
    await process.line();
    await process.send('RUN:$_owner');
    expect(await process.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await process.exit(), 43);
    expect(await f.override.exists(), isFalse);
  });

  test('系统写入非请求值不能假装外部修改已保留，未知责任必须留下', () async {
    await f.rewriteTarget.writeAsString('600x900\n');
    final process = await f.program();
    await process.send('START:$_owner');
    await process.line();
    await process.send('RUN:$_owner');
    expect(await process.exit(), 43);
    expect(await process.output.moveNext(), isFalse);
    expect(await f.override.readAsString(), '600x900\n');
    expect(await f.file('owners/$_owner/done').exists(), isFalse);
    expect(await f.read('owners/$_owner/original'), 'reset');
    expect(await f.read('owners/$_owner/pending'), '640x960');
    final retry = await f.recover(_owner);
    expect(await retry.exit(), 43);
    expect(await f.override.readAsString(), '600x900\n');
    final ack = await f.acknowledge(_owner);
    expect(await ack.exit(), 43);
    expect(await f.file('owners/$_owner/original').exists(), isTrue);
  });

  test('物理每轴两倍之外的尺寸在 wm 写入前拒绝', () async {
    final process = await f.program(width: 4096, height: 4096);
    await process.send('START:$_owner');
    await process.line();
    await process.send('RUN:$_owner');
    expect(await process.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await process.exit(), 43);
    expect(await f.mutations(), isEmpty);
    expect(await f.override.exists(), isFalse);
  });

  test('主 shell 死亡后恢复须先等已受理 worker，迟到修改不能越过恢复', () async {
    final process = await f.started();
    await f.holdTarget.writeAsString('920x1920\n');
    await process.send('RESIZE:$_owner:1:920:1920');
    await f.waitFor(f.workerEntered);
    expect(process.process.kill(ProcessSignal.sigkill), isTrue);
    await process.exit();
    final recovered = await f.recover(_owner);
    await f.waitFor(f.file('owners/$_owner/closing'));
    expect(await f.file('owners/$_owner/done').exists(), isFalse);
    expect(await f.override.readAsString(), '640x960\n');
    await f.releaseWorker.writeAsString('1');
    expect(await recovered.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await recovered.exit(), 0);
    expect(await f.override.exists(), isFalse);
    expect(await f.mutations(), ['640x960', '920x1920', 'reset']);
  });

  test('后继启动可恢复死亡原所有者，旧 DONE 不影响新租约', () async {
    final first = await f.started();
    expect(first.process.kill(ProcessSignal.sigkill), isTrue);
    await first.exit();
    final successor = await f.started(owner: _nextOwner);
    expect(await f.read('owners/$_owner/done'), 'restored');
    final oldRecovery = await f.recover(_owner);
    expect(await oldRecovery.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await oldRecovery.exit(), 0);
    expect(await f.override.readAsString(), '640x960\n');
    expect(await f.read('current'), _nextOwner);
    await successor.send('STOP:$_nextOwner');
    expect(await successor.line(), '__DISPLAY_DONE__$_nextOwner:restored');
    expect(await successor.exit(), 0);
    expect(await f.override.exists(), isFalse);
  });

  test('活所有者拒绝后继，匿名租约与缺失终态均不假装恢复成功', () async {
    final first = await f.started();
    final successor = await f.program(owner: _nextOwner);
    await successor.send('START:$_nextOwner');
    expect(await successor.exit(), 41);
    expect(await f.read('current'), _owner);
    final missing = await f.recover(_nextOwner);
    expect(await missing.exit(), 43);
    await first.send('STOP:$_owner');
    await first.line();
    await first.exit();
    await f.lease.delete(recursive: true);
    await f.lease.create();
    final anonymous = await f.program(owner: _nextOwner);
    await anonymous.send('START:$_nextOwner');
    expect(await anonymous.exit(), 43);
    expect(await f.lease.exists(), isTrue);
    expect(await f.file('current').exists(), isFalse);
  });

  test('旧调整序号拒绝重放，不发第二次 wm', () async {
    final process = await f.started();
    await process.send('RESIZE:$_owner:2:960:640');
    expect(await process.line(), '__DISPLAY_SIZE__$_owner:2:960:640');
    await process.send('RESIZE:$_owner:2:960:640');
    expect(await process.line(), '__DISPLAY_DONE__$_owner:restored');
    expect(await process.exit(), 40);
    expect(await f.mutations(), ['640x960', '960x640', 'reset']);
  });

  test('已接收 DONE 才确认回收，重复 ACK 不增长历史也不重放恢复', () async {
    for (var index = 1; index <= 3; index++) {
      final owner = index.toRadixString(16).padLeft(32, '0');
      final process = await f.started(owner: owner);
      final premature = await f.acknowledge(owner);
      expect(await premature.exit(), 41);
      await process.send('STOP:$owner');
      expect(await process.line(), '__DISPLAY_DONE__$owner:restored');
      expect(await process.exit(), 0);
      for (var repeat = 0; repeat < 2; repeat++) {
        final ack = await f.acknowledge(owner);
        expect(await ack.line(), '__DISPLAY_ACK__$owner');
        expect(await ack.exit(), 0);
      }
      expect(
        await Directory('${f.lease.path}/owners').list().toList(),
        isEmpty,
      );
      expect(await f.file('current').exists(), isFalse);
    }
    expect(await f.mutations(), [
      '640x960',
      'reset',
      '640x960',
      'reset',
      '640x960',
      'reset',
    ]);
    final recovery = await f.recover('1'.padLeft(32, '0'));
    expect(await recovery.exit(), 43);
  });

  test('旧 ACK 不能关闭后继，后继退出后只清理明确的旧 DONE', () async {
    final first = await f.started();
    await first.send('STOP:$_owner');
    await first.line();
    await first.exit();
    final successor = await f.started(owner: _nextOwner);
    final busy = await f.acknowledge(_owner);
    expect(await busy.exit(), 41);
    expect(await f.read('current'), _nextOwner);
    expect(await f.override.readAsString(), '640x960\n');
    await successor.send('STOP:$_nextOwner');
    await successor.line();
    await successor.exit();
    final ack = await f.acknowledge(_owner);
    expect(await ack.line(), '__DISPLAY_ACK__$_owner');
    expect(await ack.exit(), 0);
    expect(await f.file('owners/$_owner/done').exists(), isFalse);
    expect(await f.read('owners/$_nextOwner/done'), 'restored');
    expect(await f.read('current'), _nextOwner);
  });
}

final class _ShellFixture {
  _ShellFixture(this.root);
  final Directory root;
  final programs = <_Program>[];
  Directory get lease => Directory('${root.path}/lease');
  File file(String path) => File('${lease.path}/$path');
  File get override => File('${root.path}/override');
  File get rotation => File('${root.path}/rotation');
  File get failRestore => File('${root.path}/fail-restore');
  File get ignoreWrites => File('${root.path}/ignore-writes');
  File get rewriteTarget => File('${root.path}/rewrite-target');
  File get holdTarget => File('${root.path}/hold-target');
  File get workerEntered => File('${root.path}/worker-entered');
  File get releaseWorker => File('${root.path}/release-worker');

  static Future<_ShellFixture> open() async {
    final fixture = _ShellFixture(
      await Directory.systemTemp.createTemp('display-script-'),
    );
    final bin = await Directory('${fixture.root.path}/bin').create();
    await fixture.rotation.writeAsString('0\n');
    final prefix = "#!/bin/sh\nroot=${_quote(fixture.root.path)}\n";
    await File('${bin.path}/wm').writeAsString('''$prefix
$_fakeWm''');
    await File('${bin.path}/dumpsys')
        .writeAsString('''${prefix}printf 'Viewport: displayId=0, orientation='
value=\$(cat "\$root/rotation")
printf '%s, logicalFrame=[0, 0, 1080, 1920]\\n' "\$value"
''');
    final chmod = await Process.run('/bin/chmod', [
      '700',
      '${bin.path}/wm',
      '${bin.path}/dumpsys',
    ]);
    if (chmod.exitCode != 0) throw StateError('无法准备主机 shell 夹具。');
    return fixture;
  }

  Future<_Program> program({
    String owner = _owner,
    int width = 640,
    int height = 960,
  }) =>
      _open(physicalDisplayProgram(owner: owner, width: width, height: height));
  Future<_Program> recoverCurrent() =>
      _open(recoverCurrentPhysicalDisplayCommand(_nextOwner));
  Future<_Program> recover(String owner) =>
      _open(recoverPhysicalDisplayCommand(owner));
  Future<_Program> acknowledge(String owner) =>
      _open(acknowledgePhysicalDisplayCommand(owner));
  Future<_Program> _open(String script) async {
    final shell = Platform.environment['INTEROP_MKSH_BINARY'] ?? '/bin/sh';
    final process = await Process.start(
      shell,
      ['-c', physicalDisplayBootstrap],
      environment: {
        'PATH':
            '${root.path}/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
      },
    );
    final program = _Program(process);
    programs.add(program);
    // 只替换宿主路径和解释器；执行的是完整生产协议，而非另写镜像算法。
    process.stdin.write(
      script
          .replaceAll('/data/local/tmp/interop-display-0', lease.path)
          .replaceAll('/system/bin/sh', shell),
    );
    process.stdin.writeln('\n__INTEROP_DISPLAY_PROGRAM_END__');
    await process.stdin.flush();
    return program;
  }

  Future<_Program> started({String owner = _owner}) async {
    final process = await program(owner: owner);
    await process.send('START:$owner');
    expect(await process.line(), startsWith('__DISPLAY_OWNER__$owner:'));
    await process.send('RUN:$owner');
    expect(await process.line(), '__DISPLAY_READY__$owner:640:960');
    return process;
  }

  Future<String> read(String path) async =>
      (await file(path).readAsString()).trim();
  Future<List<String>> mutations() async {
    final calls = File('${root.path}/calls');
    return await calls.exists() ? calls.readAsLines() : <String>[];
  }

  Future<void> waitFor(File file) async {
    final limit = DateTime.now().add(const Duration(seconds: 3));
    while (!await file.exists()) {
      if (DateTime.now().isAfter(limit)) {
        throw StateError('未收到文件门闩：${file.path}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> close() async {
    await releaseWorker.writeAsString('1');
    for (final program in programs) {
      if (!program.exited) {
        program.process.kill(ProcessSignal.sigkill);
      }
      await program.exit();
      await program.errorsDone.timeout(const Duration(seconds: 3));
      await program.output.cancel();
    }
    await root.delete(recursive: true);
  }
}

final class _Program {
  _Program(this.process)
    : output = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ) {
    errorsDone = process.stderr.transform(utf8.decoder).forEach(errors.write);
    unawaited(errorsDone);
  }
  final Process process;
  final StreamIterator<String> output;
  final errors = StringBuffer();
  late final Future<void> errorsDone;
  bool exited = false;
  IOSink get input => process.stdin;
  Future<void> send(String line) async {
    input.writeln(line);
    await input.flush();
  }

  Future<String> line() async {
    if (!await output.moveNext().timeout(const Duration(seconds: 8))) {
      throw StateError('协议提前结束：$errors');
    }
    return output.current;
  }

  Future<int> exit() async {
    final code = await process.exitCode.timeout(const Duration(seconds: 10));
    exited = true;
    return code;
  }
}

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

const _fakeWm = r'''[ "$1" = size ] || exit 3
if [ "$#" = 1 ]; then
    printf 'Physical size: 1080x1920\n'
    if [ -f "$root/override" ]; then printf 'Override size: '; cat "$root/override"; fi
    exit 0
fi
if [ -f "$root/hold-target" ] && [ "$2" = "$(cat "$root/hold-target")" ]; then
    printf '%s\n' "$$" > "$root/worker-entered"
    while [ ! -f "$root/release-worker" ]; do sleep .01; done
fi
printf '%s\n' "$2" >> "$root/calls"
if [ "$2" = reset ] && [ -f "$root/fail-restore" ]; then exit 9; fi
if [ -f "$root/ignore-writes" ]; then exit 0; fi
if [ -f "$root/rewrite-target" ]; then cat "$root/rewrite-target" > "$root/override"; exit 0; fi
if [ "$2" = reset ]; then rm -f "$root/override"; else printf '%s\n' "$2" > "$root/override"; fi
''';
