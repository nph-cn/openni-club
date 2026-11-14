import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter glass-inspired surfaces, not Apple's native Liquid Glass material.
/// Read iOS Reduce Transparency explicitly (not exposed by MediaQuery).
class GlassPreferences {
  static final reduceTransparency = ValueNotifier<bool>(false);
  static const _channel = MethodChannel('openni/accessibility');
  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'reduceTransparencyChanged') {
        reduceTransparency.value = call.arguments == true;
      }
    });
    try {
      reduceTransparency.value =
          await _channel.invokeMethod<bool>('reduceTransparency') ?? false;
    } on MissingPluginException {
      /* Widget tests / unsupported runners use solid high-contrast fallback. */
    }
  }
}
