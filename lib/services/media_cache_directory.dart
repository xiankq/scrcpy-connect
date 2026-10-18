import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Normalize system aliases once; managed files themselves may not be links.
Future<Directory> outgoingMediaDirectory() async {
  final temporary = await getTemporaryDirectory();
  final outgoing = await Directory('${temporary.path}/outgoing')
      .create(recursive: true);
  return Directory(await outgoing.resolveSymbolicLinks());
}
