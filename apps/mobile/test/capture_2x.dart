import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
