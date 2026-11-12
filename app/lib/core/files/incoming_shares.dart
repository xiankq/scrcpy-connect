import 'package:scrcpy_connect/core/files/models/incoming_share.dart';

export 'package:scrcpy_connect/core/files/models/incoming_share.dart';

abstract interface class IncomingShares {
  Future<List<IncomingShare>> readIncomingShares();

  /// 排空此分享的复制工作后归还页面持有权；在途发布租约继续保护来源。
  Future<void> consumeShare(String id);
}
