import 'incoming_shares.dart';

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/core/application/application_session.dart';

import 'share_inbox_state.dart';

part 'share_inbox_notifier.g.dart';

@Riverpod(keepAlive: true)
class ShareInboxNotifier extends _$ShareInboxNotifier {
  late ApplicationSession _session;
  final _consumedShareIds = <String>{};
  int _request = 0;

  @override
  ShareInboxState build() {
    final session = _session = ref.watch(applicationSessionProvider);
    _consumedShareIds.clear();
    final subscription = session.stateEvents.listen((event) {
      if (!_current(session)) return;
      final type = event['type'];
      final data = jsonObject(event['data']);
      if (type == 'state.resync' || type == 'state.resync.failed') {
        _request++;
      } else if (type == 'state.resynced') {
        _request++;
        state = ShareInboxState(
          shares: objects(data['shares'])
              .map(IncomingShare.fromJson)
              .where((share) => !_consumedShareIds.contains(share.shareId))
              .toList(),
        );
      } else if (type == 'share.consumed') {
        final id = value(data, 'shareId');
        if (id.isEmpty) return;
        _request++;
        _consumedShareIds.add(id);
        state = state.copyWith(
          shares: state.shares.where((share) => share.shareId != id).toList(),
        );
      } else if (type == 'share.received' && event['data'] is Map) {
        state = _withShare(state, IncomingShare.fromJson(data));
      }
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    if (session.dependencies.initialize) {
      scheduleMicrotask(() {
        if (_current(session)) unawaited(load());
      });
    }
    return ShareInboxState(
      shares: session.dependencies.initialState.pendingShares,
    );
  }

  bool _current(ApplicationSession session) =>
      ref.mounted && !session.disposed && identical(_session, session);
  ShareInboxState _withShare(ShareInboxState source, IncomingShare share) {
    final id = share.shareId;
    if (id.isEmpty || _consumedShareIds.contains(id)) {
      return source;
    }
    final index = source.shares.indexWhere((item) => item.shareId == id);
    if (index >= 0) {
      // 附着快照可能晚于导入终态；保留队列位置并接受更新，不能用旧导入态覆盖已完成回执。
      final current = source.shares[index];
      if ([
            IncomingShareStatus.ready,
            IncomingShareStatus.error,
          ].contains(current.status) &&
          [
            IncomingShareStatus.starting,
            IncomingShareStatus.importing,
          ].contains(share.status)) {
        return source;
      }
      return source.copyWith(
        shares: [
          for (var i = 0; i < source.shares.length; i++)
            i == index ? share : source.shares[i],
        ],
      );
    }
    return source.copyWith(shares: [...source.shares, share]);
  }

  Future<void> load() async {
    final session = _session;
    final requestId = ++_request;
    try {
      final result = await session.dependencies.incomingShares
          .readIncomingShares();
      if (!_current(session) || requestId != _request) return;
      var next = state;
      for (final share in result) {
        next = _withShare(next, share);
      }
      if (!identical(state, next)) state = next;
    } catch (_) {
      // 不支持分享的平台没有队列；内容错误仍保留在对应分享记录上。
    }
  }

  Future<void> consume(String id) async {
    final session = _session;
    await session.dependencies.incomingShares.consumeShare(id);
    if (!_current(session)) return;
    _consumedShareIds.add(id);
    state = state.copyWith(
      shares: state.shares.where((share) => share.shareId != id).toList(),
    );
  }
}
