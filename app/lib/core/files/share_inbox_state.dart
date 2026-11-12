import 'package:freezed_annotation/freezed_annotation.dart';

import 'incoming_shares.dart';

part 'share_inbox_state.freezed.dart';

@freezed
class ShareInboxState with _$ShareInboxState {
  ShareInboxState({List<IncomingShare> shares = const []})
    : shares = List.unmodifiable(shares);
  final List<IncomingShare> shares;
}
