# 视觉比较

`pages.json` 配置 Pencil/Flutter 配对、尺寸和裁剪。Pencil 以 1× 导出到系统临时目录；应用布局捕获从 `app/` 运行：

```sh
DESIGN_REFINEMENT_CAPTURE_DIR=/tmp/connect-design/flutter \
  flutter test --no-pub test/design_refinement_capture.dart
```

根目录比较：

```sh
dart tool/visual_parity/compare.dart \
  --pencil-dir /tmp/connect-design/pencil \
  --flutter-dir /tmp/connect-design/flutter \
  --output /tmp/connect-design/comparison
```

输入尺寸/裁剪必须匹配；工具不缩放或自动对齐。输出差异图用于人工判断，completed 不等于验收通过。真实材料另用 `app/integration_test/glass_chrome_test.dart`，软件布局截图不证明 GPU 效果。
