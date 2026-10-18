import 'package:flutter/material.dart';

import 'live_video_benchmark.dart';

/// Only allocation/removal changes this widget. Video updates travel through
/// Flutter's external Texture machinery, without per-frame setState or pumps.
class LiveVideoPage extends StatelessWidget {
  const LiveVideoPage({required this.benchmark, super.key});

  final LiveVideoBenchmark benchmark;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ValueListenableBuilder(
      valueListenable: benchmark.texture,
      builder: (context, value, child) => ColoredBox(
        color: Colors.black,
        child: value == null
            ? const SizedBox.expand()
            : Center(
                child: AspectRatio(
                  aspectRatio: value.width / value.height,
                  child: Texture(
                    key: benchmark.textureKey,
                    textureId: value.id,
                  ),
                ),
              ),
      ),
    ),
  );
}
