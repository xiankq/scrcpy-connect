import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'gallery_scanner.dart';

final galleryScannerProvider = Provider<GalleryScanner>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.gallery)),
);
