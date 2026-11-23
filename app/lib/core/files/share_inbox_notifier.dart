import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/models/share_inbox_state.dart';
import 'package:scrcpy_connect/core/files/models/share_inbox_event.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

import 'file_capabilities_provider.dart';

part 'share_inbox_notifier.g.dart';

@Riverpod(keepAlive: true)
class ShareInboxNotifier extends _$ShareInboxNotifier {
  _ShareInboxOwner? _owner;

  @override
  ShareInboxState build() {
    final session = ref.watch(stateSubscriptionProvider);
    final previous = _owner;
    final owner = _owner = _ShareInboxOwner(
      session,
      ref.watch(incomingSharesProvider),
    );
    final subscription = session.stateEvents.listen((event) {
      if (!_current(owner)) return;
      if (event.data is RecoveryStarted || event.data is RecoveryFailed) {
        owner.request++;
      } else if (event.data case RecoveryCompleted(:final snapshot)) {
        owner.request++;
        state = ShareInboxState(
          shares: snapshot.shares
              .where((share) => !owner.consumed.contains(share.shareId))
              .toList(),
        );
      } else if (event.data case ShareConsumed(shareId: final id)) {
        if (id.isEmpty) return;
        owner.request++;
        owner.consumed.add(id);
        state = state.copyWith(
          shares: state.shares.where((share) => share.shareId != id).toList(),
        );
      } else if (event.data case ShareReceived(:final share)) {
        state = _withShare(owner, state, share);
      }
    });
    ref.onDispose(() {
      owner.disposed = true;
      unawaited(subscription.cancel());
    });
    if (session.session.initialize) {
      scheduleMicrotask(() {
        if (_current(owner)) unawaited(load());
      });
    }
    return ShareInboxState(
      shares: identical(previous?.session, session)
          ? const []
          : session.session.initialState.pendingShares,
    );
  }

  bool _current(_ShareInboxOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      !owner.session.disposed &&
      identical(ref.read(incomingSharesProvider), owner.source) &&
      identical(_owner, owner);
  ShareInboxState _withShare(
    _ShareInboxOwner owner,
    ShareInboxState source,
    IncomingShare share,
  ) {
    final id = share.shareId;
    if (id.isEmpty || owner.consumed.contains(id)) {
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
    final owner = _owner!;
    final requestId = ++owner.request;
    final result = await owner.source.readIncomingShares();
    if (!_current(owner) || requestId != owner.request) return;
    var next = state;
    for (final share in result) {
      next = _withShare(owner, next, share);
    }
    if (!identical(state, next)) state = next;
  }

  Future<IncomingShare?> find(String id) async {
    final owner = _owner!;
    await load();
    if (!_current(owner)) return null;
    return state.shares.where((share) => share.shareId == id).firstOrNull;
  }

  Future<void> consume(String id) async {
    final owner = _owner!;
    await owner.source.consumeShare(id);
    if (!_current(owner)) return;
    owner.consumed.add(id);
    state = state.copyWith(
      shares: state.shares.where((share) => share.shareId != id).toList(),
    );
  }
}

final class _ShareInboxOwner {
  _ShareInboxOwner(this.session, this.source);
  final StateSubscription session;
  final IncomingShares source;
  final consumed = <String>{};
  int request = 0;
  bool disposed = false;
}
