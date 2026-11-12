import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 已按受控清单核验的 Android 可执行产物。
final class BundledServerFiles {
  BundledServerFiles(Map<String, Uint8List> artifacts)
    : scrcpyBytes = artifacts['scrcpy']!.asUnmodifiableView(),
      companionBytes = artifacts['companion']!.asUnmodifiableView(),
      helperArtifacts = Map.unmodifiable({
        for (final entry in artifacts.entries)
          if (entry.key != 'scrcpy' && entry.key != 'companion')
            entry.key: entry.value.asUnmodifiableView(),
      });

  final Uint8List scrcpyBytes;
  final Uint8List companionBytes;
  final Map<String, Uint8List> helperArtifacts;
}
