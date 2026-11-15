import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Uses original downloaded URL bytes, never a replacement image or mock art.
/// Run `dart run tool/cache_catalog_media.dart` before golden capture.
Future<void> primeCatalogMedia() async {
  final file = File('.dart_tool/catalog-media/index.json');
  if (!await file.exists()) {
    throw StateError(
      'Run dart run tool/cache_catalog_media.dart before golden capture.',
    );
  }
  final index = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSizeBytes = 128 << 20;
  for (final entry in index.entries) {
    final key = NetworkImage(entry.key);
    if (cache.containsKey(key)) continue;
    final bytes = await File('.dart_tool/catalog-media/${entry.value}')
        .readAsBytes();
    final ready = Completer<void>();
    final stream = cache.putIfAbsent(
      key,
      () => MultiFrameImageStreamCompleter(
        codec: ui.instantiateImageCodec(
          bytes,
          targetWidth: 1200,
          allowUpscaling: false,
        ),
        scale: 1,
      ),
    )!;
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, synchronous) {
        if (!ready.isCompleted) ready.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    await ready.future;
    stream.removeListener(listener);
  }
}
