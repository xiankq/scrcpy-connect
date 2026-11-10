import 'package:scrcpy_connect/services/file_publication_leases.dart';

import 'dart:async';

/// 受管来源可在调用方未传发布标识时识别归属，禁止绕过持久租约。
abstract interface class ManagedFilePublicationLeases
    implements FilePublicationLeases {
  Future<String?> ownerForSources(List<String> sources);
}
