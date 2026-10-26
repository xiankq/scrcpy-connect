import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/stores/application_host.dart';
import 'package:scrcpy_connect/services/application_host_record.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/services/platform/bundled_servers.dart';
import 'package:scrcpy_connect/stores/usb_lease_recovery.dart';

const _policy = ConnectionPolicy(
  tcp: AdbTcpOptions(keepalive: null, userTimeout: null),
);
final _payload = Uint8List.fromList([1, 2, 3]);

void main() {
  test('USB begin封印返回前不附着SDK，冷进程complete后才交付host', () async {
    final fixture = await _fixture();
    final platform = fixture.usbRecovery();
    platform.beginGate = Completer<void>();
    var delivered = false;
    final opening = fixture.attach().then((host) {
      delivered = true;
      return host;
    });
    await platform.beginStarted.future;
    expect(delivered, isFalse);
    expect(
      fixture.api.calls.any((call) => call.startsWith('attach:')),
      isFalse,
    );
    expect(fixture.api.calls, isNot(contains('assets')));
    expect(platform.oldFdOpen, isTrue);
    platform.completeGate = Completer<void>();
    platform.beginGate!.complete();
    await platform.completeStarted.future;
    expect(delivered, isFalse);
    expect(fixture.api.scopes, isNotEmpty);
    expect(platform.oldFdOpen, isTrue);
    platform.completeGate!.complete();
    final host = await opening;
    expect(delivered, isTrue);
    expect(host.usbOwnerLeaseId, platform.owner);
    expect(platform.ready, isTrue);
    expect(platform.oldFdOpen, isFalse);
    expect(platform.fdCloses, 1);
    expect(fixture.dependencies.recoveryFactoryCalls, 1);
    await host.close();
  });

  test('USB原FD须等待旧SDK域真实排空，attach进入不代表已经释放', () async {
    final fixture = await _fixture();
    await _seedMobile(fixture);
    final platform = fixture.usbRecovery();
    fixture.api.attachGate = Completer<void>();
    final opening = fixture.attach();
    await fixture.api.attachStarted.future;
    expect(platform.ready, isFalse);
    expect(platform.oldFdOpen, isTrue);
    expect(platform.completeRequests, isEmpty);
    fixture.api.attachGate!.complete();
    final host = await opening;
    expect(platform.oldFdOpen, isFalse);
    expect(
      fixture.api.calls,
      containsAllInOrder([
        'usb.beginRecovery',
        'attach:${p.join(fixture.directory.path, 'application-host')}',
        'claim:old-mobile',
        'drain:claimed-1',
        'disconnect:claimed-1',
        'handshake.close:handshake-1',
        'usb.completeRecovery',
        'usb.fd.close',
      ]),
    );
    await host.close();
  });

  for (final stage in ['capture', 'disconnect', 'handshake']) {
    test('USB $stage排空阻塞或失败均保留平台原FD，退休host可原对象重试', () async {
      final fixture = await _fixture();
      await _seedMobile(fixture);
      fixture.api.addConnection(
        'foreign',
        scopeKey: '/foreign',
        serial: 'same',
      );
      final platform = _UsbPlatform(fixture.api.calls);
      final recovery = UsbLeaseRecovery(platform: platform.request);
      fixture.dependencies.recovery = recovery;
      final blocked = Completer<void>();
      late Future<void> started;
      switch (stage) {
        case 'capture':
          fixture.api.drainGate = blocked;
          fixture.api.drainFailures = 100;
          started = fixture.api.drainStarted.future;
        case 'disconnect':
          fixture.api.disconnectGate = blocked;
          fixture.api.disconnectFailures = 100;
          started = fixture.api.disconnectStarted.future;
        case 'handshake':
          fixture.api.handshakeCloseGate = blocked;
          fixture.api.handshakeCloseFailures = 100;
          started = fixture.api.handshakeCloseStarted.future;
      }
      final rejected = expectLater(
        fixture.attach(),
        throwsA(_code('application_host_cleanup_unconfirmed')),
      );
      await started;
      expect(platform.completeRequests, isEmpty);
      expect(platform.oldFdOpen, isTrue);
      expect(platform.ready, isFalse);
      blocked.complete();
      await rejected;
      expect(platform.oldFdOpen, isTrue);
      expect(platform.completeRequests, isEmpty);
      fixture.api.drainFailures = 0;
      fixture.api.disconnectFailures = 0;
      fixture.api.handshakeCloseFailures = 0;
      await ApplicationHost.closeRetiredHosts();
      expect(platform.oldFdOpen, isFalse);
      expect(platform.fdCloses, 1);
      expect(platform.ready, isTrue);
      expect(fixture.api.connections.keys, ['foreign']);
      expect(fixture.api.handshakes, isEmpty);
      expect(fixture.api.claimed, hasLength(1));
      expect(fixture.dependencies.recoveryFactoryCalls, 1);
      expect(recovery.ownerLeaseId, platform.owner);
    });
  }

  test('USB begin丢回执保留同candidate，重试先SDK排空再complete', () async {
    final fixture = await _fixture();
    await _seedMobile(fixture);
    fixture.api.addConnection('foreign', scopeKey: '/foreign', serial: 'same');
    final platform = fixture.usbRecovery()..beginReplyFailures = 2;
    await expectLater(
      fixture.attach(),
      throwsA(_code('application_host_cleanup_unconfirmed')),
    );
    expect(platform.oldFdOpen, isTrue);
    expect(platform.completeRequests, isEmpty);
    expect(fixture.api.claimed, isEmpty);
    expect(fixture.api.scopes.values.single.scopeId, 'old-mobile-scope');
    final candidate = platform.owner;
    platform.beginReplyFailures = 0;
    await ApplicationHost.closeRetiredHosts();
    expect(
      platform.beginRequests.map((request) => request['ownerLeaseId']).toSet(),
      {candidate},
    );
    expect(
      platform.beginRequests.every(
        (request) => request['expectedOwnerLeaseId'] == 'old-usb-owner',
      ),
      isTrue,
    );
    expect(platform.completeRequests.single['ownerLeaseId'], candidate);
    expect(fixture.api.claimed, hasLength(1));
    expect(fixture.api.connections.keys, ['foreign']);
    expect(platform.oldFdOpen, isFalse);
    expect(fixture.dependencies.recoveryFactoryCalls, 1);
  });

  test('USB complete已关闭原FD却丢回执，原candidate重试不重复关闭或重认领', () async {
    final fixture = await _fixture();
    await _seedMobile(fixture);
    final platform = fixture.usbRecovery()..completeReplyFailures = 2;
    await expectLater(
      fixture.attach(),
      throwsA(_code('application_host_cleanup_unconfirmed')),
    );
    final candidate = platform.owner;
    expect(platform.ready, isTrue);
    expect(platform.fdCloses, 1);
    expect(fixture.api.connections, isEmpty);
    expect(fixture.api.handshakes, isEmpty);
    platform.completeReplyFailures = 0;
    await ApplicationHost.closeRetiredHosts();
    expect(
      platform.completeRequests
          .map((request) => request['ownerLeaseId'])
          .toSet(),
      {candidate},
    );
    expect(platform.fdCloses, 1);
    expect(fixture.api.claimed, hasLength(1));
    expect(fixture.dependencies.recoveryFactoryCalls, 1);
  });

  test('USB SDK接管失败不得complete，恢复后只回收本scope的同serial连接', () async {
    final fixture = await _fixture();
    await _seedMobile(fixture);
    fixture.api.addConnection('foreign', scopeKey: '/foreign', serial: 'same');
    fixture.api.addConnection('unscoped', serial: 'same');
    final platform = fixture.usbRecovery();
    fixture.api.attachFailures = 100;
    await expectLater(
      fixture.attach(),
      throwsA(_code('application_host_cleanup_unconfirmed')),
    );
    expect(platform.oldFdOpen, isTrue);
    expect(platform.completeRequests, isEmpty);
    fixture.api.attachFailures = 0;
    await ApplicationHost.closeRetiredHosts();
    expect(
      fixture.api.connections.keys,
      unorderedEquals(['foreign', 'unscoped']),
    );
    expect(fixture.api.claimed, hasLength(1));
    expect(platform.fdCloses, 1);
  });

  test('真实登记存在时核验原策略，拒绝发生在任何接管和文件操作之前', () async {
    final fixture = await _fixture(desktop: true);
    final key = p.join(fixture.directory.path, 'application-host');
    fixture.api.scopes[key] = AdbAdmissionScopeInfo(
      scopeKey: key,
      scopeId: 'old-scope',
      accepting: true,
    );
    await ApplicationHostRecord(policy: _policy.toJson()).write(
      Directory(p.join(fixture.directory.path, 'process_hosts')),
      'old-scope',
    );
    await expectLater(
      fixture.attach(
        policy: const ConnectionPolicy(requestAuthorization: false),
      ),
      throwsA(_code('runtime_connection_policy_mismatch')),
    );
    expect(fixture.api.calls, isEmpty);
    expect(fixture.api.scopes[key]?.scopeId, 'old-scope');
    final host = await fixture.attach();
    expect(fixture.api.scopes[key]?.scopeId, isNot('old-scope'));
    await host.close();
  });

  test('桌面恢复同时核对命名域和已认领serverId，不回收同域其他服务器的连接', () async {
    final fixture = await _fixture(desktop: true);
    await _seedServer(fixture);
    final key = p.join(fixture.directory.path, 'application-host');
    fixture.api.addConnection(
      'owned',
      scopeKey: key,
      serverId: 'original-server',
      serial: 'same',
    );
    fixture.api.addConnection(
      'foreign-server',
      scopeKey: key,
      serverId: 'other-server',
      serial: 'same',
    );
    fixture.api.addConnection(
      'foreign-scope',
      scopeKey: '/other',
      serverId: 'original-server',
      serial: 'same',
    );
    fixture.api.addConnection(
      'unscoped',
      serverId: 'original-server',
      serial: 'same',
    );
    final host = await fixture.attach();
    expect(fixture.api.calls.where((call) => call.startsWith('claim:')), [
      'claim:owned',
    ]);
    final claimed = fixture.api.claimed.single;
    expect(
      fixture.api.calls,
      containsAllInOrder([
        'confirm:$claimed',
        'drain:$claimed',
        'display:$claimed',
        'disconnect:$claimed',
      ]),
    );
    expect(
      fixture.api.connections.keys,
      unorderedEquals(['foreign-server', 'foreign-scope', 'unscoped']),
    );
    await host.recoverConnections();
    expect(fixture.api.claimed, hasLength(1));
    await host.close();
    expect(fixture.dependencies.restored.single.closeCount, 1);
    expect(
      fixture.api.connections.keys,
      unorderedEquals(['foreign-server', 'foreign-scope', 'unscoped']),
    );
  });

  test('关闭等待在途桌面显示恢复，未完成时保留服务器与scope', () async {
    final fixture = await _fixture(desktop: true);
    await _seedServer(fixture);
    final host = await fixture.attach();
    fixture.addDesktopConnection('late-owned');
    final release = fixture.api.displayGate = Completer<void>();
    final draining = expectLater(host.drainConnections(), throwsStateError);
    await fixture.api.displayStarted.future;
    var closed = false;
    final closing = host.close().then((_) => closed = true);
    try {
      expect(closed, isFalse);
      expect(
        fixture.api.calls.any((call) => call.startsWith('disconnect:')),
        isFalse,
      );
      expect(fixture.dependencies.restored.single.closeCount, 0);
      expect(fixture.api.scopes, isNotEmpty);
      expect(fixture.api.servers, hasLength(1));
    } finally {
      release.complete();
    }
    await draining;
    await closing;
    expect(closed, isTrue);
    expect(fixture.api.connections, isEmpty);
    expect(fixture.dependencies.restored.single.closeCount, 1);
    expect(fixture.api.servers, isEmpty);
    expect(fixture.api.scopes, isEmpty);
  });

  test('桌面显示恢复持续失败保留精确已认领连接，退休宿主重试不重新claim', () async {
    final fixture = await _fixture(desktop: true);
    await _seedServer(fixture);
    fixture.addDesktopConnection('owned');
    fixture.api.displayFailures = 100;
    try {
      await expectLater(
        fixture.attach(),
        throwsA(_code('application_host_cleanup_unconfirmed')),
      );
      final claimed = fixture.api.claimed.single;
      expect(fixture.api.connections.keys, [claimed]);
      expect(
        fixture.api.calls.where((call) => call == 'drain:$claimed'),
        hasLength(1),
      );
      expect(fixture.api.calls, isNot(contains('disconnect:$claimed')));
      expect(fixture.dependencies.restored.single.closeCount, 0);
      expect(fixture.api.servers, hasLength(1));
      expect(fixture.api.scopes, isNotEmpty);
    } finally {
      fixture.api.displayFailures = 0;
    }
    final claimed = fixture.api.claimed.single;
    await ApplicationHost.closeRetiredHosts();
    expect(fixture.api.claimed, [claimed]);
    expect(
      fixture.api.calls.where((call) => call == 'drain:$claimed'),
      hasLength(1),
    );
    expect(
      fixture.api.calls.where((call) => call == 'disconnect:$claimed'),
      hasLength(1),
    );
    expect(fixture.api.connections, isEmpty);
    expect(fixture.api.handshakes, isEmpty);
    expect(fixture.dependencies.restored.single.closeCount, 1);
    expect(fixture.api.servers, isEmpty);
    expect(fixture.api.scopes, isEmpty);
  });

  test('桌面restore初始失败后仍保存扫描责任，重试先恢复旧连接再关闭服务器', () async {
    final fixture = await _fixture(desktop: true);
    await _seedServer(fixture);
    fixture.addDesktopConnection('owned');
    fixture.dependencies.restoreFailure = StateError('尚未取得服务器租约');
    try {
      await expectLater(
        fixture.attach(),
        throwsA(_code('application_host_cleanup_unconfirmed')),
      );
      expect(fixture.api.connections.keys, ['owned']);
      expect(fixture.api.claimed, isEmpty);
      expect(
        fixture.api.calls.any(
          (call) => call.startsWith('drain:') || call.startsWith('display:'),
        ),
        isFalse,
      );
      expect(fixture.api.servers, hasLength(1));
      expect(fixture.api.scopes, isNotEmpty);
    } finally {
      fixture.dependencies.restoreFailure = null;
    }
    await ApplicationHost.closeRetiredHosts();
    final claimed = fixture.api.claimed.single;
    expect(
      fixture.api.calls,
      containsAllInOrder([
        'claim:owned',
        'drain:$claimed',
        'display:$claimed',
        'disconnect:$claimed',
        'server.close:original-server',
      ]),
    );
    expect(fixture.api.connections, isEmpty);
    expect(fixture.dependencies.restored.single.closeCount, 1);
    expect(fixture.api.servers, isEmpty);
    expect(fixture.api.scopes, isEmpty);
  });

  test('显示恢复失败期间精确连接真实closed，只排空本机流后允许宿主收尾', () async {
    final fixture = await _fixture(desktop: true);
    await _seedServer(fixture);
    fixture.addDesktopConnection('owned');
    fixture.api.displayFailures = 1;
    fixture.api.closeDuringDisplayFailure = true;
    final host = await fixture.attach();
    final claimed = fixture.api.claimed.single;
    expect(
      fixture.api.calls,
      containsAllInOrder([
        'drain:$claimed',
        'display:$claimed',
        'display.close:$claimed',
        'disconnect:$claimed',
      ]),
    );
    expect(fixture.api.calls.where((call) => call.startsWith('display:')), [
      'display:$claimed',
    ]);
    expect(fixture.api.connections, isEmpty);
    await host.close();
    expect(fixture.dependencies.restored.single.closeCount, 1);
    expect(fixture.api.scopes, isEmpty);
  });

  test('移动恢复按 scope 精确认领并排空捕获和连接，隔离同 serial 的其他域', () async {
    final fixture = await _fixture();
    await _seedMobile(fixture);
    fixture.api.addConnection('foreign', scopeKey: '/other', serial: 'same');
    fixture.api.addConnection('unscoped', serial: 'same');
    final host = await fixture.attach();
    expect(host.scrcpyBytes, orderedEquals(_payload));
    expect(fixture.api.calls.where((call) => call.startsWith('claim:')), [
      'claim:old-mobile',
    ]);
    final claimed = fixture.api.claimed.single;
    final calls = fixture.api.calls;
    expect(
      calls.indexOf('confirm:$claimed'),
      lessThan(calls.indexOf('drain:$claimed')),
    );
    expect(
      calls.indexOf('drain:$claimed'),
      lessThan(calls.indexOf('disconnect:$claimed')),
    );
    expect(
      fixture.api.connections.keys,
      unorderedEquals(['foreign', 'unscoped']),
    );
    await host.recoverConnections();
    expect(fixture.api.claimed, hasLength(1));
    await host.close();
    expect(fixture.api.scopes, isEmpty);
    expect(
      fixture.api.connections.keys,
      unorderedEquals(['foreign', 'unscoped']),
    );
  });
  test('身份初始化前的移动排空取得真实新句柄，捕获失败保留同对象重试', () async {
    final fixture = await _fixture();
    final host = await fixture.attach();
    final key = p.join(fixture.directory.path, 'application-host');
    fixture.api.addConnection('live-before-identities', scopeKey: key);
    fixture.api.addConnection('foreign', scopeKey: '/other');
    fixture.api.drainFailures = 1;
    await expectLater(host.drainConnections(), throwsStateError);
    final claimed = fixture.api.claimed.single;
    expect(fixture.api.connections, contains(claimed));
    expect(fixture.api.calls, isNot(contains('disconnect:$claimed')));
    await host.drainConnections();
    expect(fixture.api.claimed, hasLength(1));
    expect(fixture.api.connections.keys, ['foreign']);
    expect(
      fixture.api.calls.where((call) => call == 'drain:$claimed'),
      hasLength(2),
    );
    await host.close();
  });
  test('关闭等待在途移动排空，真实捕获结束前不撤全局标记或断连接', () async {
    final fixture = await _fixture();
    final host = await fixture.attach();
    fixture.addScopedConnection('in-flight');
    fixture.api.drainGate = Completer<void>();
    final draining = expectLater(host.drainConnections(), throwsStateError);
    await fixture.api.drainStarted.future;
    var closed = false;
    final closing = host.close().then((_) => closed = true);
    expect(closed, isFalse);
    expect(fixture.api.scopes, isNotEmpty);
    expect(
      fixture.api.calls.any((call) => call.startsWith('disconnect:')),
      isFalse,
    );
    fixture.api.drainGate!.complete();
    await draining;
    await closing;
    expect(closed, isTrue);
    expect(fixture.api.connections, isEmpty);
    expect(fixture.api.scopes, isEmpty);
  });
  test('握手结束失败保留精确登记，重试不把已经关闭的连接重新认领', () async {
    final fixture = await _fixture();
    final host = await fixture.attach();
    fixture.addScopedConnection('before-identities');
    fixture.api.handshakeCloseFailures = 1;
    await expectLater(host.drainConnections(), throwsStateError);
    final claimed = fixture.api.claimed.single;
    expect(fixture.api.connections, isEmpty);
    expect(fixture.api.handshakes, hasLength(1));
    await host.recoverConnections();
    expect(fixture.api.claimed, hasLength(1));
    expect(fixture.api.handshakes, isEmpty);
    expect(
      fixture.api.calls.where((call) => call == 'drain:$claimed'),
      hasLength(1),
    );
    expect(
      fixture.api.calls.where((call) => call == 'disconnect:$claimed'),
      hasLength(1),
    );
    await host.close();
  });
  test('认领结果已取得但确认失败，原新句柄保留给真实捕获和连接清理', () async {
    final fixture = await _fixture();
    final host = await fixture.attach();
    fixture.addScopedConnection('before-identities');
    fixture.api.confirmFailures = 1;
    await expectLater(host.drainConnections(), throwsStateError);
    final claimed = fixture.api.claimed.single;
    expect(fixture.api.connections, contains(claimed));
    expect(fixture.api.calls, isNot(contains('drain:$claimed')));
    await host.close();
    expect(fixture.api.claimed, hasLength(1));
    expect(
      fixture.api.calls,
      containsAllInOrder(['drain:$claimed', 'disconnect:$claimed']),
    );
    expect(fixture.api.connections, isEmpty);
    expect(fixture.api.handshakes, isEmpty);
  });
  test('旧宿主迟到 claim 经原生 scoped fence 拒绝，不断开后继连接', () async {
    final fixture = await _fixture();
    final host = await fixture.attach();
    final key = p.join(fixture.directory.path, 'application-host');
    fixture.api.addConnection('old', scopeKey: key);
    fixture.api.claimGate = Completer<void>();
    final draining = expectLater(
      host.drainConnections(),
      throwsA(isA<AdbException>()),
    );
    await fixture.api.claimStarted.future;
    final old = fixture.api.scopes[key]!;
    final successor = await fixture.api.attachAdmissionScope(
      key,
      expectedScopeId: old.scopeId,
    );
    fixture.api.addConnection('successor', scopeKey: key);
    fixture.api.claimGate!.complete();
    await draining;
    await host.close();
    expect(fixture.api.claimed, isEmpty);
    expect(
      fixture.api.calls.any((call) => call.startsWith('disconnect:')),
      isFalse,
    );
    expect(fixture.api.connections.keys, unorderedEquals(['old', 'successor']));
    expect(fixture.api.scopes[key]?.scopeId, successor.scopeId);
    fixture.api.scopes.clear();
  });
  test('自然关闭连接仍排空精确捕获，不对已关闭 Client 发起不可完成的认领', () async {
    final fixture = await _fixture();
    final host = await fixture.attach();
    fixture.addScopedConnection('closed', closed: true);
    await host.drainConnections();
    expect(fixture.api.claimed, isEmpty);
    expect(
      fixture.api.calls,
      containsAllInOrder(['drain:closed', 'disconnect:closed']),
    );
    await host.close();
  });
  test('文件域关闭失败保留进程标记及精确句柄，客户端关闭保持粘性并可重试', () async {
    final fixture = await _fixture();
    final host = await fixture.attach();
    fixture.api.fileCloseFailures = 1;
    await expectLater(host.close(), throwsStateError);
    expect(fixture.api.scopes, isNotEmpty);
    expect(
      () => host.clientForIdentity(identityPath: '/other', fingerprint: 'x'),
      throwsStateError,
    );
    await host.close();
    expect(
      fixture.api.calls.where((call) => call == 'files.close:files-1').length,
      2,
    );
    expect(fixture.api.scopes, isEmpty);
  });
  test('初始化异常与关闭失败保留宿主，后续附着必须先完成精确清理', () async {
    final fixture = await _fixture();
    fixture.dependencies.failAssets = true;
    fixture.api.fileCloseFailures = 1;
    await expectLater(
      fixture.attach(),
      throwsA(_code('application_host_cleanup_unconfirmed')),
    );
    expect(fixture.api.scopes, isNotEmpty);
    fixture.dependencies.failAssets = false;
    final host = await fixture.attach();
    final cleanup = fixture.api.calls.lastIndexOf('files.close:files-1');
    final secondAttach = fixture.api.calls.indexOf(
      'files.attach',
      fixture.api.calls.indexOf('files.attach') + 1,
    );
    expect(cleanup, lessThan(secondAttach));
    await host.close();
  });
  test('clientForIdentity 迟到创建期间关闭，等待创建并精确关闭，不交付客户端', () async {
    final fixture = await _fixture(desktop: true);
    final host = await fixture.attach();
    final path = p.join(fixture.directory.path, 'key');
    fixture.api.fingerprints[path] = 'first';
    fixture.dependencies.preparing = Completer<AdbHost>();
    final rejected = expectLater(
      host.clientForIdentity(identityPath: path, fingerprint: 'first'),
      throwsStateError,
    );
    await fixture.dependencies.prepareStarted.future;
    var finished = false;
    final closing = host.close().then((_) => finished = true);
    expect(finished, isFalse);
    final owner = _Server('late-server');
    fixture.dependencies.preparing!.complete(owner);
    await rejected;
    await closing;
    expect(owner.closeCount, 1);
  });
  test('等待原子服务器登记期间换代，旧准备不能产生迟到 Child', () async {
    final fixture = await _fixture(desktop: true);
    final host = await fixture.attach();
    final path = p.join(fixture.directory.path, 'key');
    fixture.api.fingerprints[path] = 'first';
    fixture.dependencies.preparing = Completer<AdbHost>();
    final rejected = expectLater(
      host.clientForIdentity(identityPath: path, fingerprint: 'first'),
      throwsA(
        isA<AdbException>().having(
          (error) => error.code,
          'code',
          'adb_admission_scope_stale',
        ),
      ),
    );
    await fixture.dependencies.prepareStarted.future;
    final key = p.join(fixture.directory.path, 'application-host');
    final old = fixture.api.scopes[key]!;
    final successor = await fixture.api.attachAdmissionScope(
      key,
      expectedScopeId: old.scopeId,
    );
    fixture.dependencies.preparing!.complete(_Server('forbidden-late-server'));
    await rejected;
    expect(fixture.dependencies.registeredServers, isEmpty);
    await host.close();
    expect(fixture.api.scopes[key]?.scopeId, successor.scopeId);
    fixture.api.scopes.clear();
  });
  test('并行附着等待结束后仍核验二进制选择，不复用不同请求', () async {
    final fixture = await _fixture();
    fixture.dependencies.assetsGate = Completer<void>();
    final opening = fixture.attach();
    await fixture.dependencies.assetsStarted.future;
    final otherBinary = await Directory(
      p.join(fixture.directory.path, 'other-binary'),
    ).create();
    final rejected = expectLater(
      ApplicationHost.attach(
        dataDirectory: fixture.directory.path,
        connectionPolicy: _policy,
        adbBinaryDirectory: otherBinary,
        dependencies: fixture.dependencies,
      ),
      throwsA(_code('host_executable_mismatch')),
    );
    fixture.dependencies.assetsGate!.complete();
    final host = await opening;
    await rejected;
    await host.close();
  });
  test('初始化等待期间已被后继接管时拒绝交付，不关闭后继权限', () async {
    final fixture = await _fixture();
    fixture.dependencies.assetsGate = Completer<void>();
    final rejected = expectLater(
      fixture.attach(),
      throwsA(_code('application_host_stale')),
    );
    await fixture.dependencies.assetsStarted.future;
    final key = p.join(fixture.directory.path, 'application-host');
    final previous = fixture.api.scopes[key]!;
    final next = await fixture.api.attachAdmissionScope(
      key,
      expectedScopeId: previous.scopeId,
    );
    fixture.dependencies.assetsGate!.complete();
    await rejected;
    expect(fixture.api.scopes[key]?.scopeId, next.scopeId);
    fixture.api.scopes.clear();
  });
  test('恢复先取得精确关闭权再核验身份，换钥失败不交付且关闭原 Child', () async {
    final fixture = await _fixture(desktop: true);
    await _seedServer(fixture);
    fixture.api.fingerprints[p.join(fixture.directory.path, 'key')] = 'changed';
    await expectLater(
      fixture.attach(),
      throwsA(_code('host_identity_mismatch')),
    );
    expect(fixture.dependencies.restored.single.closeCount, 1);
    expect(fixture.api.servers, isEmpty);
    expect(fixture.api.scopes, isEmpty);
    expect(fixture.dependencies.prepareStarted.isCompleted, isFalse);
  });
  test('SDK在claim前失败保留全局标记和原Child，失败清理可在同对象重试', () async {
    final fixture = await _fixture(desktop: true);
    await _seedServer(fixture);
    fixture.dependencies.restoreFailure = StateError(
      'identity file missing before claim',
    );
    await expectLater(
      fixture.attach(),
      throwsA(_code('application_host_cleanup_unconfirmed')),
    );
    expect(fixture.api.scopes, isNotEmpty);
    expect(fixture.api.servers.single.serverId, 'original-server');
    expect(fixture.dependencies.prepareStarted.isCompleted, isFalse);
    fixture.dependencies.restoreFailure = null;
    await ApplicationHost.closeRetiredHosts();
    expect(fixture.api.scopes, isEmpty);
    expect(fixture.api.servers, isEmpty);
    expect(fixture.dependencies.restored.single.closeCount, 1);
  });
}

Future<void> _seedServer(_Fixture fixture) async {
  final path = p.join(fixture.directory.path, 'key');
  const fingerprint = 'original';
  final id = sha256.convert(utf8.encode('$path\u0000$fingerprint')).toString();
  final root = p.join(
    fixture.directory.path,
    'process_hosts',
    'identities',
    id,
  );
  final key = p.join(fixture.directory.path, 'application-host');
  fixture.api.scopes[key] = AdbAdmissionScopeInfo(
    scopeKey: key,
    scopeId: 'old-scope',
    accepting: true,
  );
  fixture.api.fingerprints[path] = fingerprint;
  fixture.api.servers.add(
    AdbServerInfo(
      serverId: 'original-server',
      leaseId: 'old-lease',
      launch: AdbServerLaunchSpec(
        executable: '/controlled/adb',
        arguments: [],
        environment: {
          'ANDROID_USER_HOME': p.join(
            root,
            'official_adb',
            'scope-1',
            'global',
          ),
          'ADB_VENDOR_KEYS': path,
        },
        endpoint: '127.0.0.1:41001',
      ),
      phase: AdbServerPhase.ready,
      transportStateUnknown: false,
    ),
  );
  await ApplicationHostRecord(
    policy: _policy.toJson(),
    identities: {
      id: ApplicationIdentityHost(
        identityPath: path,
        fingerprint: fingerprint,
        directory: root,
        serverId: 'original-server',
      ),
    },
  ).write(
    Directory(p.join(fixture.directory.path, 'process_hosts')),
    'old-scope',
  );
}

Future<void> _seedMobile(_Fixture fixture) async {
  final key = p.join(fixture.directory.path, 'application-host');
  fixture.api.scopes[key] = AdbAdmissionScopeInfo(
    scopeKey: key,
    scopeId: 'old-mobile-scope',
    accepting: true,
  );
  fixture.api.addConnection('old-mobile', scopeKey: key, serial: 'same');
  await ApplicationHostRecord(policy: _policy.toJson()).write(
    Directory(p.join(fixture.directory.path, 'process_hosts')),
    'old-mobile-scope',
  );
}

Matcher _code(String code) => isA<ApplicationCommandException>().having(
  (error) => error.code,
  'code',
  code,
);

Future<_Fixture> _fixture({bool desktop = false}) async {
  final directory = await Directory.systemTemp.createTemp('application-host-');
  final api = _Api();
  final dependencies = _Dependencies(api, desktop);
  addTearDown(() async {
    await ApplicationHost.closeRetiredHosts();
    await directory.delete(recursive: true);
  });
  return _Fixture(
    Directory(await directory.resolveSymbolicLinks()),
    api,
    dependencies,
  );
}

class _Fixture {
  _Fixture(this.directory, this.api, this.dependencies);
  final Directory directory;
  final _Api api;
  final _Dependencies dependencies;
  _UsbPlatform usbRecovery() {
    final platform = _UsbPlatform(api.calls);
    dependencies.recovery = UsbLeaseRecovery(platform: platform.request);
    return platform;
  }

  void addScopedConnection(String id, {bool closed = false}) =>
      api.addConnection(
        id,
        scopeKey: p.join(directory.path, 'application-host'),
        closed: closed,
      );
  void addDesktopConnection(String id) => api.addConnection(
    id,
    scopeKey: p.join(directory.path, 'application-host'),
    serverId: 'original-server',
  );

  Future<ApplicationHost> attach({ConnectionPolicy policy = _policy}) =>
      ApplicationHost.attach(
        dataDirectory: directory.path,
        connectionPolicy: policy,
        dependencies: dependencies,
      );
}

class _Dependencies extends ApplicationHostDependencies {
  _Dependencies(this.api, this.desktop);
  final _Api api;
  @override
  final bool desktop;
  bool failAssets = false;
  UsbLeaseRecovery? recovery;
  int recoveryFactoryCalls = 0;
  @override
  UsbLeaseRecovery? usbRecovery() {
    recoveryFactoryCalls++;
    return recovery;
  }

  Completer<AdbHost>? preparing;
  final prepareStarted = Completer<void>();
  final registeredServers = <AdbHost>[];
  final restored = <_Server>[];
  Object? restoreFailure;
  Completer<void>? assetsGate;
  final assetsStarted = Completer<void>();
  @override
  Future<NativeAdbApi> bindings() async => api;
  @override
  Future<BundledServerFiles> assets(Directory directory) async {
    api.calls.add('assets');
    if (!assetsStarted.isCompleted) assetsStarted.complete();
    await assetsGate?.future;
    if (failAssets) throw StateError('assets unavailable');
    return BundledServers(bundle: _Bundle()).prepare(directory);
  }

  @override
  Future<ScrcpyClient> createScrcpy(Uint8List bytes) async {
    api.calls.add('scrcpy');
    return ScrcpyClient(_Scrcpy(api), nativeOwner: api);
  }

  @override
  Future<AdbHost> prepareServer({
    required Directory directory,
    required String identityPath,
    required NativeAdbApi bindings,
    required AdbAdmissionScopeInfo admissionScope,
    Directory? binaryDirectory,
  }) async {
    if (!prepareStarted.isCompleted) prepareStarted.complete();
    final server =
        await (preparing?.future ?? Future.value(_Server('new-server')));
    // 对应 SDK createScopedServer 的原子登记 seam；旧权限不能登记晚到 Child。
    if (api.scopes[admissionScope.scopeKey]?.scopeId !=
        admissionScope.scopeId) {
      throw const AdbException('adb_admission_scope_stale');
    }
    registeredServers.add(server);
    return server;
  }

  @override
  Future<AdbHost> restoreServer({
    required Directory directory,
    required String leaseId,
    required NativeAdbApi bindings,
    required AdbAdmissionScopeInfo admissionScope,
    Directory? binaryDirectory,
  }) async {
    if (restoreFailure case final failure?) throw failure;
    if (api.scopes[admissionScope.scopeKey]?.scopeId !=
        admissionScope.scopeId) {
      throw const AdbException('adb_admission_scope_stale');
    }
    final facts = api.servers.singleWhere(
      (server) => server.leaseId == leaseId,
    );
    final owner = _Server(
      facts.serverId,
      onClose: () {
        api.calls.add('server.close:${facts.serverId}');
        api.servers.removeWhere((server) => server.serverId == facts.serverId);
      },
    );
    restored.add(owner);
    return owner;
  }
}

class _Server implements AdbHost {
  _Server(this.id, {this.onClose});
  final String id;
  final void Function()? onClose;
  int closeCount = 0;
  @override
  Map<String, Object?> get nativeConfiguration => {'serverId': id};
  @override
  AdbClient get client => _Client();
  @override
  Future<void> close() async {
    closeCount++;
    onClose?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements AdbClient {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Scrcpy implements NativeScrcpyApi, NativeScrcpyConnectionApi {
  _Scrcpy(this.api);
  final _Api api;
  @override
  Future<void> drainConnection(String connectionId) async {
    api.calls.add('drain:$connectionId');
    if (!api.connections.containsKey(connectionId)) {
      throw StateError('unknown exact connection');
    }
    if (!api.drainStarted.isCompleted) api.drainStarted.complete();
    await api.drainGate?.future;
    if (api.drainFailures-- > 0) {
      throw StateError('capture cleanup unconfirmed');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api
    implements
        NativeAdbApi,
        NativeAdbFileApi,
        NativeAdbAdmissionApi,
        NativeAdbFileScopeApi,
        NativeAdbScopedFileScopeApi,
        NativeAdbServerApi,
        NativeAdbScopedServerApi,
        NativeAdbHandshakeApi,
        AdbIdentities {
  final calls = <String>[];
  List<AdbFileHelper> helpers = [];
  @override
  Future<void> initializeFileHelpers(List<AdbFileHelper> value) async {
    calls.add('file.helpers');
    helpers = List.of(value);
  }

  final scopes = <String, AdbAdmissionScopeInfo>{};
  final fingerprints = <String, String>{};
  final servers = <AdbServerInfo>[];
  final connections = <String, AdbDevice>{};
  final facts = <String, AdbConnectionFacts>{};
  final handshakes = <String, String>{};
  final claimed = <String>[];
  final claimStarted = Completer<void>(), drainStarted = Completer<void>();
  Completer<void>? claimGate,
      drainGate,
      attachGate,
      disconnectGate,
      handshakeCloseGate;
  final attachStarted = Completer<void>();
  final disconnectStarted = Completer<void>();
  final handshakeCloseStarted = Completer<void>();
  final displayStarted = Completer<void>();
  Completer<void>? displayGate;
  int displayFailures = 0;
  bool closeDuringDisplayFailure = false;
  final _displayCommands =
      <String, ({String connection, StringBuffer program})>{};
  final _displayEvents = <String, StreamController<NativeAdbEvent>>{};
  final _displayReaders = <String, StreamIterator<NativeAdbEvent>>{};
  int _displaySequence = 0;
  int attachFailures = 0;
  int drainFailures = 0,
      disconnectFailures = 0,
      handshakeGeneration = 0,
      handshakeCloseFailures = 0,
      confirmFailures = 0;
  void addConnection(
    String id, {
    String? scopeKey,
    String serial = 'device',
    bool closed = false,
    String? serverId,
  }) {
    connections[id] = AdbDevice(id: id, serial: serial, state: 'device');
    facts[id] = AdbConnectionFacts(
      officialServer: false,
      closed: closed,
      features: [],
      connectionId: 'physical-$id',
      admissionScopeKey: scopeKey,
      serverId: serverId,
    );
  }

  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    expect(request.kind, AdbServiceKind.exec);
    final operation = 'display-${++_displaySequence}';
    _displayCommands[operation] = (connection: id, program: StringBuffer());
    final events = _displayEvents[operation] =
        StreamController<NativeAdbEvent>();
    _displayReaders[operation] = StreamIterator(events.stream);
    return operation;
  }

  @override
  Future<void> write(String id, AdbServiceInput input) async {
    final command = _displayCommands[id]!;
    command.program.write(utf8.decode(input.bytes));
    final text = command.program.toString();
    if (!text.endsWith('__INTEROP_DISPLAY_PROGRAM_END__\n')) return;
    calls.add('display:${command.connection}');
    if (!displayStarted.isCompleted) displayStarted.complete();
    await displayGate?.future;
    final nonce = RegExp("expected_owner='([0-9a-f]{32})'")
        .firstMatch(text)![1]!;
    final failed = displayFailures-- > 0;
    if (failed && closeDuringDisplayFailure) {
      final previous = facts[command.connection]!;
      facts[command.connection] = AdbConnectionFacts(
        officialServer: previous.officialServer,
        closed: true,
        features: previous.features,
        connectionId: previous.connectionId,
        admissionScopeKey: previous.admissionScopeKey,
        serverId: previous.serverId,
      );
    }
    _displayEvents[id]!.add(
      NativeAdbEvent(
        kind: 'data',
        bytes: Uint8List.fromList(
          utf8.encode(
            failed
                ? '__DISPLAY_ERROR__$nonce:busy_or_unknown\n'
                : '__DISPLAY_CURRENT__$nonce:empty\n',
          ),
        ),
        done: false,
      ),
    );
    _displayEvents[id]!.add(
      NativeAdbEvent(
        kind: 'done',
        bytes: Uint8List(0),
        done: true,
        exitCode: failed ? 41 : 0,
      ),
    );
    unawaited(_displayEvents[id]!.close());
  }

  @override
  Future<NativeAdbEvent?> next(String id) async {
    final reader = _displayReaders[id]!;
    return await reader.moveNext() ? reader.current : null;
  }

  @override
  Future<void> cancel(String id) async {
    calls.add('display.close:${_displayCommands[id]!.connection}');
    await _displayReaders[id]!.cancel();
    await _displayEvents[id]!.close();
  }

  @override
  Future<List<AdbDevice>> devices() async => connections.values.toList();
  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async =>
      facts[id] ?? (throw const AdbException('adb_connection_closed'));
  @override
  Future<String> createScopedHandshake(String scopeId) async {
    if (!scopes.values.any(
      (scope) => scope.scopeId == scopeId && scope.accepting,
    )) {
      throw const AdbException('adb_admission_scope_stale');
    }
    final id = 'handshake-${++handshakeGeneration}';
    handshakes[id] = scopeId;
    return id;
  }

  @override
  Future<AdbDevice> claimScopedConnection(String id, String handshakeId) async {
    calls.add('claim:$id');
    if (!claimStarted.isCompleted) claimStarted.complete();
    await claimGate?.future;
    if (!scopes.values.any(
      (scope) => scope.scopeId == handshakes[handshakeId] && scope.accepting,
    )) {
      throw const AdbException('adb_admission_scope_stale');
    }
    final old = connections.remove(id)!;
    final oldFacts = facts.remove(id)!;
    final next = 'claimed-${claimed.length + 1}';
    final device = AdbDevice(id: next, serial: old.serial, state: old.state);
    connections[next] = device;
    facts[next] = oldFacts;
    claimed.add(next);
    return device;
  }

  @override
  Future<void> confirmHandshakeConnection(
    String handshakeId,
    String connectionId,
  ) async {
    calls.add('confirm:$connectionId');
    if (confirmFailures-- > 0) throw StateError('confirm failed');
    if (!scopes.values.any(
      (scope) => scope.scopeId == handshakes[handshakeId] && scope.accepting,
    )) {
      throw const AdbException('adb_admission_scope_stale');
    }
  }

  @override
  Future<void> closeHandshake(String id) async {
    calls.add('handshake.close:$id');
    if (!handshakeCloseStarted.isCompleted) handshakeCloseStarted.complete();
    await handshakeCloseGate?.future;
    if (handshakeCloseFailures-- > 0) {
      throw StateError('handshake cleanup unconfirmed');
    }
    handshakes.remove(id);
  }

  @override
  Future<void> disconnect(String id) async {
    calls.add('disconnect:$id');
    if (!disconnectStarted.isCompleted) disconnectStarted.complete();
    await disconnectGate?.future;
    if (disconnectFailures-- > 0) {
      throw StateError('connection cleanup unconfirmed');
    }
    connections.remove(id);
    facts.remove(id);
  }

  int generation = 0, fileGeneration = 0, fileCloseFailures = 0;
  @override
  Future<AdbAdmissionScopeInfo?> inspectAdmissionScope(String key) async =>
      scopes[key];
  @override
  Future<AdbAdmissionScopeInfo> attachAdmissionScope(
    String key, {
    String? expectedScopeId,
    int timeoutMs = 7000,
  }) async {
    if (scopes[key]?.scopeId != expectedScopeId) {
      throw StateError('stale scope');
    }
    calls.add('attach:$key');
    if (!attachStarted.isCompleted) attachStarted.complete();
    await attachGate?.future;
    if (attachFailures-- > 0) throw StateError('SDK old scope not drained');
    return scopes[key] = AdbAdmissionScopeInfo(
      scopeKey: key,
      scopeId: 'scope-${++generation}',
      accepting: true,
    );
  }

  @override
  Future<void> closeAdmissionScope(String id, {int timeoutMs = 7000}) async {
    scopes.removeWhere((key, scope) => scope.scopeId == id);
  }

  @override
  Future<String> fileScopeAttach(String key) async {
    calls.add('files.attach');
    return 'files-${++fileGeneration}';
  }

  @override
  Future<String> fileScopeAttachScoped(
    String key,
    String admissionScopeId,
  ) async {
    if (!scopes.values.any(
      (scope) => scope.scopeId == admissionScopeId && scope.accepting,
    )) {
      throw StateError('stale admission scope');
    }
    return fileScopeAttach(key);
  }

  @override
  Future<void> fileScopeClose(String id) async {
    calls.add('files.close:$id');
    if (fileCloseFailures-- > 0) throw StateError('file cleanup unconfirmed');
  }

  @override
  Future<List<AdbServerInfo>> listServers() async => servers.toList();
  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async {
    final fingerprint = fingerprints[path];
    return fingerprint == null
        ? null
        : AdbIdentityInfo(
            fingerprint: fingerprint,
            fingerprintAlgorithm: 'sha256',
            fingerprintInput: 'canonical',
            bits: 2048,
            exponent: 65537,
          );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bundle extends CachingAssetBundle {
  static const ids = [
    'scrcpy',
    'companion',
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  ];
  @override
  Future<ByteData> load(String key) async {
    final bytes = key.endsWith('manifest.json')
        ? utf8.encode(
            jsonEncode({
              'version': 1,
              'artifacts': [
                for (final id in ids)
                  {
                    'id': id,
                    'file': '$id.zlib',
                    'size': _payload.length,
                    'sha256': sha256.convert(_payload).toString(),
                  },
              ],
            }),
          )
        : ZLibEncoder().convert(_payload);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// 平台协议端只维护真实封印与原FD关闭事实；SDK排空由独立能力fake控制。
final class _UsbPlatform {
  _UsbPlatform(this.calls);
  final List<String> calls;
  String owner = 'old-usb-owner';
  bool ready = false;
  bool oldFdOpen = true;
  int fdCloses = 0;
  int beginReplyFailures = 0, completeReplyFailures = 0;
  Completer<void>? beginGate, completeGate;
  final beginStarted = Completer<void>();
  final completeStarted = Completer<void>();
  final beginRequests = <Map<String, dynamic>>[];
  final completeRequests = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> request(
    String command,
    Map<String, dynamic> params,
  ) async {
    calls.add(command);
    if (command.endsWith('environment')) {
      return {'ownerLeaseId': owner, 'ownerReady': ready};
    }
    if (command == 'usb.beginRecovery') {
      beginRequests.add(Map.of(params));
      if (!beginStarted.isCompleted) beginStarted.complete();
      await beginGate?.future;
      final candidate = params['ownerLeaseId'];
      if (candidate is! String ||
          candidate.isEmpty ||
          (candidate != owner && params['expectedOwnerLeaseId'] != owner)) {
        throw PlatformException(code: 'usb_owner_stale');
      }
      // 同candidate重复begin不撤销已完成的接管，模拟原生CAS幂等回执。
      if (candidate != owner) {
        owner = candidate;
        ready = false;
      }
      if (beginReplyFailures-- > 0) throw PlatformException(code: 'reply_lost');
      return {'begun': true, 'ownerLeaseId': owner, 'ownerReady': ready};
    }
    if (command == 'usb.completeRecovery') {
      completeRequests.add(Map.of(params));
      if (!completeStarted.isCompleted) completeStarted.complete();
      await completeGate?.future;
      if (params['ownerLeaseId'] != owner) {
        throw PlatformException(code: 'usb_owner_stale');
      }
      if (oldFdOpen) {
        calls.add('usb.fd.close');
        oldFdOpen = false;
        fdCloses++;
      }
      ready = true;
      if (completeReplyFailures-- > 0) {
        throw PlatformException(code: 'reply_lost');
      }
      return {'completed': true, 'ownerLeaseId': owner, 'ownerReady': true};
    }
    throw StateError('unexpected USB platform command: $command');
  }
}
