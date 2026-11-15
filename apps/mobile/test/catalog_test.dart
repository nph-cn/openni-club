import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openni_club/discover.dart';
import 'package:openni_club/main.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/screens.dart';

void main() {
  test(
    'gallery manifest covers every captured route with a real mobile PNG',
    () {
      final manifest = jsonDecode(
        File('screenshots/manifest.json').readAsStringSync(),
      ) as List;
      final ids = manifest.map((row) => row['id'] as String).toList();
      expect(ids.toSet(), screenNames.toSet());
      expect(ids.length, ids.toSet().length);
      for (final row in manifest) {
        final image = File('screenshots/${row['id']}.png').readAsBytesSync();
        expect(image.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = image.buffer.asByteData();
        expect(header.getUint32(16), row['width']);
        expect(header.getUint32(20), row['height']);
        expect(File('../../${row['source']}').existsSync(), isTrue);
        expect([
          'ready',
          'loading',
          'empty',
          'error',
          'verification',
          'success',
        ], contains(row['stateGroup']));
      }
    },
  );

  test('catalog loads operator banners from the API', () async {
    final repo = ClubRepository(
      baseUrl: 'https://club.example/api/v1',
      persist: false,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.path.endsWith('/club')
                ? {'name': 'Configured club'}
                : r.url.path.endsWith('/banners')
                ? [
                    {
                      'id': 'b1',
                      'title': 'Game service',
                      'serviceId': 's1',
                      'imageUrl': 'https://images.example/game.jpg',
                    },
                  ]
                : [],
          ),
          200,
        ),
      ),
    );
    await repo.load();
    expect(repo.error, isNull);
    expect(repo.banners.single['id'], 'b1');
  });
  testWidgets(
    'banner opens its configured service; game selector filters actual services',
    (tester) async {
      final repo = ClubRepository(persist: false);
      await repo.load();
      repo.banners = [
        {'id': 'b1', 'title': '查看复盘服务', 'serviceId': 's2', 'imageUrl': ''},
      ];
      await tester.pumpWidget(OpenNIApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看复盘服务'));
      await tester.pumpAndSettle();
      expect(tester.widget<ServicePage>(find.byType(ServicePage)).id, 's2');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      final selector = find.byWidgetPredicate(
        (w) => w is GameSelector && w.service['game'] == '无畏契约',
      );
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is ServiceFeature && w.service['id'] == 's3',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is ServiceFeature && w.service['id'] == 's1',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
