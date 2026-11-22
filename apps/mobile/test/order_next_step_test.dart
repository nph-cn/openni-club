import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:openni_club/orders.dart';
import 'package:openni_club/repository.dart';
import 'package:openni_club/ui.dart';

void main() {
  test('next steps reflect fulfillment state and available actions', () {
    const examples = {
      'awaiting_payment': '确认付款后，可在这里查看派单进度。',
      'awaiting_assignment': '刷新进度查看派单结果；需要协助可联系俱乐部。',
      'awaiting_acceptance': '刷新进度查看队友接单结果。',
      'scheduled': '按预约时间准备服务；需要协助可联系俱乐部。',
      'in_progress': '服务中如有问题，可申请售后。',
      'disputed': '可联系俱乐部了解售后进度。',
      'completed': '需要服务，可再次预约。',
      'cancelled': '需要服务，可再次预约。',
    };
    for (final entry in examples.entries) {
      expect(
        orderNextStep({'fulfillmentStatus': entry.key}),
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      orderNextStep({
        'fulfillmentStatus': 'awaiting_confirmation',
        'delivery': {'summary': '真实服务记录'},
      }),
      '核对服务记录后确认完成；如有问题可申请售后。',
    );
    expect(
      orderNextStep({'fulfillmentStatus': 'awaiting_confirmation'}),
      '核对本次服务后确认完成；如有问题可申请售后。',
    );
  });

  testWidgets('in-progress order shows guidance with available support', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = ClubRepository(persist: false);
    await repo.load();
    for (final service in repo.services) {
      service.remove('coverUrl');
    }
    repo.club.remove('previewLogoUrl');
    repo.club.remove('logoUrl');
    repo.orders = [
      {
        'id': 'order-next-step',
        'serviceId': 's1',
        'serviceTitle': '三角洲 · PC 小时陪',
        'fulfillmentStatus': 'in_progress',
        'status': 'confirmed',
        'paymentStatus': 'unpaid',
        'priceCents': 3900,
        'scheduledAt': '2026-11-15T13:15:00.000Z',
        'createdAt': '2026-11-15T13:05:00.000Z',
        'contact': 'demo-contact',
        'events': [],
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: clubTheme(repo),
        home: OrderPage(repo, 'order-next-step'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('下一步 · 服务中如有问题，可申请售后。'), findsOneWidget);
    final contact = find.widgetWithText(FilledButton, '联系俱乐部');
    expect(contact, findsOneWidget);
    expect(tester.widget<FilledButton>(contact).onPressed, isNotNull);
    expect(find.widgetWithText(OutlinedButton, '申请售后'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
