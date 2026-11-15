import 'capture_2x.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/screens.dart';

import 'catalog_media_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCaptureFonts);
  for (final screen in stateScreenNames) {
    testWidgets('auth state: $screen', (tester) async {
      enableCaptureShadows();
      debugDefaultTargetPlatformOverride = screen == 'home_android'
          ? TargetPlatform.android
          : TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            disableAnimations: true,
            reduceMotion: true,
          );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final repo = ClubRepository(
        persist: false,
        clock: () => DateTime.utc(2026, 11, 15, 10, 30),
      );
      await repo.load();
      await repo.loadDemoPreview();
      await tester.runAsync(primeCatalogMedia);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: OpenNIApp(
            repository: repo,
            initialScreen: screen,
            previewDevice: true,
          ),
        ),
      );
      if (screen == 'code_verifying') {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      } else {
        await tester.pumpAndSettle();
      }
      await tester.runAsync(
        () => primeLocalMedia(tester.element(find.byType(Scaffold).first)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: screen);
      await expectLater(
        await captureAt2x(key),
        matchesGoldenFile('../screenshots/$screen.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
