import 'package:scrcpy_connect/core/files/file_stamp.dart';

/// 一次选择同时携带路径与当时观察到的身份；不按同名重新选择文件。
typedef FileMutationSelection = ({String path, FileStamp expected});

abstract interface class FileMutations {
  Future<void> createDirectory(String deviceId, String path);

  Future<void> rename(
    String deviceId,
    FileMutationSelection source, {
    required String destination,
  });

  Future<void> delete(String deviceId, List<FileMutationSelection> sources);
}
