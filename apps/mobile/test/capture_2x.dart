import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 截图加载应用实际使用的中文字体与两套图标字体。
Future<void> loadCaptureFonts() async {
  for (final entry in {
    'NotoSansSC': 'assets/fonts/NotoSansSC.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'packages/cupertino_icons/CupertinoIcons':
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  }.entries) {
    await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
  }
}

/// Widget 测试默认关闭阴影模糊；视觉截图保留实际应用的阴影绘制。
void enableCaptureShadows() {
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = previous);
}

/// 以真实控件树重新栅格化为 2×；不放大或加工旧截图。
Future<ui.Image> captureAt2x(GlobalKey key) {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage(pixelRatio: 2);
}
