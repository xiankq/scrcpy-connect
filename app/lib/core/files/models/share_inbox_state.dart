import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/incoming_share.dart';

part 'share_inbox_state.freezed.dart';

@freezed
class ShareInboxState with _$ShareInboxState {
  ShareInboxState({List<IncomingShare> shares = const []})
    : shares = List.unmodifiable(shares);
  final List<IncomingShare> shares;
}
