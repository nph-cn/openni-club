import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;

import 'repository.dart';
import 'ui.dart';
import 'auth.dart';
import 'loading.dart';
import 'discover.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  String filter = '进行中';
  bool loading = false;
  String? failure;
  @override
  void initState() {
    super.initState();
    if (!widget.repo.isLocal && widget.repo.token != null) load();
  }

  Future<void> load() async {
    if (widget.repo.isProduction && widget.repo.token == null) {
      if (!await requireClubLogin(context, widget.repo)) return;
      if (!mounted) return;
    }
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      await widget.repo.refreshOrders();
    } catch (e) {
      if (mounted) setState(() => failure = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    if (repo.isProduction && repo.token == null) {
      return OrdersSignInPage(repo, onSignIn: load);
    }
    if (loading && repo.orders.isEmpty) {
      return ClubPage(
        repo: repo,
        title: '我的订单',
        tab: 2,
        child: const ClubSkeleton(kind: SkeletonKind.catalog),
      );
    }
    final items = repo.orders
        .where(
          (o) =>
              filter == '全部' ||
              (filter == '已结束'
                  ? ['completed', 'cancelled'].contains(stage(o))
                  : !['completed', 'cancelled'].contains(stage(o))),
        )
        .toList();
    final activeCount = repo.orders
        .where((o) => !['completed', 'cancelled'].contains(stage(o)))
        .length;
    return ClubPage(
      repo: repo,
      title: '我的订单',
      tab: 2,
      actions: [
        IconButton(
          tooltip: '刷新预约',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
      ],
      child: PageList(
        children: [
          ClubSegmentedControl(
            values: const ['进行中', '已结束', '全部'],
            value: filter,
            onChanged: (next) => setState(() => filter = next),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('共 ${repo.orders.length} 笔预约', style: typeSecondary),
              const Spacer(),
              if (activeCount > 0) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: positive,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text('$activeCount 笔进行中', style: typeSecondary),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (failure != null)
            EmptyState(
              '订单加载失败',
              failure!,
              action: TextButton(
                onPressed: loading ? null : load,
                child: const Text('重新加载'),
              ),
            ),
          if (!loading && failure == null && items.isEmpty)
            EmptyState(
              filter == '全部' ? '这里还没有预约' : '当前分组暂无预约',
              '选择服务并预约时段。',
              action: FilledButton(
                onPressed: () => context.go('/services'),
                child: const Text('去发现服务'),
              ),
            ),
          for (final order in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OrderCard(repo: repo, order: order),
            ),
          DemoStamp(repo),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.repo, required this.order});
  final ClubRepository repo;
  final Json order;
  @override
  Widget build(BuildContext context) {
    final service =
        repo.findService('${order['serviceId']}') ??
        Json.from(order['serviceSnapshot'] as Map? ?? const {});
    final player = repo.findPlayer(
      '${order['assignedPlayerId'] ?? order['playerId'] ?? ''}',
    );
    final status = stage(order);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/orders/${order['id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 84,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ServiceArt(service, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xE60D1218), Color(0x990D1218), Color(0x330D1218)],
                        stops: [0, .55, 1],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StagePill(status, compact: true),
                            const Spacer(),
                            const Icon(
                              CupertinoIcons.chevron_forward,
                              size: 12,
                              color: Color(0x99FFFFFF),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          '${order['serviceTitle']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.3,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          orderSpecification(order),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              child: Row(
                children: [
                  if (player != null) ...[
                    PlayerArt(
                      repo: repo,
                      player: player,
                      width: 26,
                      height: 26,
                      radius: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${player['name']}',
                      style: typeSecondary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      when(order['scheduledAt']),
                      style: typeSecondary,
                    ),
                  ),
                  Text(
                    '¥${money(order)}',
                    style: typeNumber,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 客户与成员看到同一份冻结服务规格，仅布局随上下文变化。
class OrderServiceSummary extends StatelessWidget {
  const OrderServiceSummary({
    super.key,
    required this.repo,
    required this.order,
  });
  final ClubRepository repo;
  final Json order;
  @override
  Widget build(BuildContext context) {
    final service = {
      ...?repo.findService('${order['serviceId']}'),
      ...Json.from(order['serviceSnapshot'] as Map? ?? const {}),
    };
    return Row(
      children: [
        SizedBox(
          width: 76,
          height: 82,
          child: ServiceArt(service, radius: 12),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${order['serviceTitle']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typeBodySmall.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                orderSpecification(order),
                style: typeSecondary,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.clock,
                    size: 12,
                    color: faint,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      when(order['scheduledAt']),
                      style: typeCaption,
                    ),
                  ),
                  Text(
                    '¥${money(order)}',
                    style: typeLabel.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class OrderPage extends StatefulWidget {
  const OrderPage(this.repo, this.id, {super.key});
  final ClubRepository repo;
  final String id;
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  bool busy = false, reading = false;
  String? failure;
  Json? get order =>
      widget.repo.orders.where((o) => o['id'] == widget.id).firstOrNull;
  @override
  void initState() {
    super.initState();
    if (!widget.repo.isLocal && widget.repo.token != null) refresh();
  }

  Future<void> refresh() async {
    if (reading) return;
    setState(() {
      reading = true;
      failure = null;
    });
    try {
      if (order != null) {
        await widget.repo.refreshOrder(order!);
      } else {
        final o = Json.from(
          await widget.repo.request('GET', '/orders/${widget.id}'),
        );
        widget.repo.orders.insert(0, o);
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => failure = '$e');
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  Future<void> action(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo, o = order;
    if (reading && o == null) {
      return ClubPage(
        repo: repo,
        title: '订单详情',
        child: const ClubSkeleton(kind: SkeletonKind.order),
      );
    }
    if (o == null) {
      return ClubPage(
        repo: repo,
        title: '预约详情',
        child: EmptyState(
          '暂时没有这笔预约',
          failure ?? '请登录后查看，或返回预约列表。',
          action: FilledButton(
            onPressed: failure != null ? refresh : () => context.go('/orders'),
            child: Text(failure != null ? '重新加载' : '查看预约'),
          ),
        ),
      );
    }
    final status = stage(o),
        player = repo.findPlayer(o['assignedPlayerId'] ?? o['playerId']);
    final events = (o['events'] as List? ?? [])
        .map((e) => Json.from(e))
        .toList();
    final service =
        repo.findService(o['serviceId']) ??
        Json.from(o['serviceSnapshot'] as Map? ?? const {});
    final blocksCancel = [
      'awaiting_assignment',
      'awaiting_acceptance',
      'scheduled',
      'awaiting_payment',
    ].contains(status);
    final closed = ['cancelled', 'awaiting_payment', 'disputed'].contains(status);
    return ClubPage(
      repo: repo,
      title: '订单详情',
      actions: [
        IconButton(
          tooltip: '刷新进度',
          onPressed: busy || reading ? null : refresh,
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
      ],
      bottom: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: closed
                  ? () => textSheet(
                      context,
                      '服务条款',
                      '${repo.club['termsText'] ?? ''}',
                    )
                  : () => context.push('/orders/${o['id']}/support'),
              icon: const Icon(CupertinoIcons.headphones, size: 15),
              label: Text(closed ? '服务条款' : '申请售后'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: busy ? null : () => primaryAction(o),
              child: Text(
                busy
                    ? '处理中…'
                    : status == 'awaiting_payment'
                    ? '确认付款'
                    : status == 'awaiting_confirmation'
                    ? '确认完成'
                    : ['completed', 'cancelled'].contains(status)
                    ? '再次预约'
                    : '联系俱乐部',
              ),
            ),
          ),
        ],
      ),
      child: PageList(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: SizedBox(
              height: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ServiceArt(service, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xE60E131A),
                          Color(0xB3253040),
                          Color(0x730E131A),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '订单 ${o['id']}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                letterSpacing: .3,
                                color: Color(0xB3FFFFFF),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                repo.isProduction ? '正式环境' : '演示订单',
                                style: const TextStyle(
                                  fontSize: 10,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          stageName(status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${when(o['scheduledAt'])} · ${orderSpecification(o)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xD9FFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ProgressStrip(status),
          const SizedBox(height: 14),
          Surface(
            border: true,
            child: Column(
              children: [
                OrderServiceSummary(repo: repo, order: o),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: Divider(height: .5, thickness: .5),
                ),
                PairRow('预约时间', when(o['scheduledAt']), strong: true),
                PairRow('服务费用', '¥${money(o)}'),
                PairRow(
                  '支付状态',
                  repo.isProduction
                      ? const {
                              'paid': '已支付',
                              'pending': '等待确认',
                              'unpaid': '待支付',
                              'refund_pending': '退款处理中',
                              'refunded': '已退款',
                            }[o['paymentStatus']] ??
                            '待确认'
                      : '未发生付款',
                ),
              ],
            ),
          ),
          if (player != null) ...[
            const SectionTitle('服务队友'),
            Surface(
              border: true,
              padding: EdgeInsets.zero,
              child: MemberRow(
                repo: repo,
                player: player,
                trailing: Tag(
                  o['assignedPlayerId'] == null ? '意向队友' : '服务队友',
                  fill: Colors.white,
                  color: ink,
                ),
              ),
            ),
          ],
          if (o['delivery'] is Map) ...[
            const SectionTitle('队友的服务记录'),
            Surface(
              color: sage,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.doc_text,
                        size: 14,
                        color: muted,
                      ),
                      const SizedBox(width: 6),
                      Text('服务说明', style: typeLabel),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${o['delivery']['summary']}',
                    style: typeBodySmall.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ],
          if (o['review'] is Map) ...[
            const SectionTitle('我的评价'),
            Surface(
              border: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Icon(
                          i < ((o['review'] as Map)['rating'] as num? ?? 0)
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 17,
                          color: const Color(0xFFD9A21B),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        '${(o['review'] as Map)['rating']} 分',
                        style: typeLabel.copyWith(fontFeatures: const []),
                      ),
                    ],
                  ),
                  if ('${(o['review'] as Map)['comment'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${(o['review'] as Map)['comment']}',
                      style: typeBodySmall,
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    when((o['review'] as Map)['at']),
                    style: typeCaption,
                  ),
                ],
              ),
            ),
          ],
          if (o['dispute'] is Map) ...[
            const SizedBox(height: 12),
            Surface(
              color: const Color(0xFFF9E9E7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        size: 14,
                        color: danger,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '售后记录',
                        style: typeLabel.copyWith(color: danger),
                      ),
                      const Spacer(),
                      StagePill('disputed', compact: true),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${(o['dispute'] as Map)['reason']}',
                    style: typeBodySmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if ('${(o['dispute'] as Map)['details'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${(o['dispute'] as Map)['details']}',
                      style: typeSecondary.copyWith(height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SectionTitle('订单进度', caption: '时间均为北京时间'),
          if (events.isEmpty)
            TimelineEntry(
              title: '预约已提交',
              description: '等待俱乐部处理预约',
              time: when(o['createdAt']),
              last: true,
            )
          else
            ...events.asMap().entries.map(
              (e) => TimelineEntry(
                title: orderEventTitle(e.value),
                description:
                    '${((e.value['actor'] as Map?)?['name'] ?? '俱乐部')}',
                time: when(e.value['at']),
                last: e.key == events.length - 1,
              ),
            ),
          const SizedBox(height: 4),
          Surface(
            border: true,
            child: Column(
              children: [
                PairRow('订单编号', '${o['id']}'),
                PairRow('联系方式', '${o['contact']}'),
                PairRow(
                  '预约备注',
                  '${o['note'] ?? ''}'.isEmpty ? '未填写' : '${o['note']}',
                ),
              ],
            ),
          ),
          if (blocksCancel)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : () => cancel(o),
                style: TextButton.styleFrom(foregroundColor: danger),
                child: const Text('取消预约'),
              ),
            ),
          if (!closed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push('/orders/${o['id']}/support'),
                child: const Text('遇到问题，申请售后'),
              ),
            ),
          if (failure != null)
            Text(
              failure!,
              style: const TextStyle(color: danger, fontSize: 13),
            ),
          DemoStamp(repo),
        ],
      ),
    );
  }

  Future<void> primaryAction(Json o) async {
    final repo = widget.repo;
    switch (stage(o)) {
      case 'awaiting_payment':
        if (repo.isProduction && repo.token == null) {
          await requireClubLogin(context, repo);
          return;
        }
        if (!mounted) return;
        await action(() async {
          try {
            await repo.pay(o);
          } on ClubApiException catch (e) {
            if (e.code != 'WECHAT_LINK_REQUIRED' || !mounted) rethrow;
            final link = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('关联微信支付'),
                content: const Text('本账号尚未关联微信。关联后继续支付当前订单。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('暂不关联'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('关联微信并继续支付'),
                  ),
                ],
              ),
            );
            if (link != true) return;
            await repo.linkWechatForPayment();
            await repo.pay(o);
          }
          if (mounted) {
            toast(
              context,
              o['paymentStatus'] == 'paid' ? '付款已确认' : '请稍后刷新付款结果。',
            );
          }
        });
      case 'awaiting_confirmation':
        await confirm(o);
      case 'completed':
      case 'cancelled':
        final snapshot = o['serviceSnapshot'];
        final variantId =
            o['variantId'] ?? (snapshot is Map ? snapshot['variantId'] : null);
        context.push(
          Uri(
            path: '/book',
            queryParameters: {
              'service': '${o['serviceId']}',
              if (variantId != null) 'variant': '$variantId',
              if (o['assignedPlayerId'] != null)
                'player': '${o['assignedPlayerId']}',
            },
          ).toString(),
        );
      default:
        await textSheet(
          context,
          '联系俱乐部',
          '${repo.club['supportContact'] ?? '请通过俱乐部公开客服渠道联系。'}\n订单编号：${o['id']}',
        );
    }
  }

  Future<void> cancel(Json o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消这次预约？'),
        content: Text(
          widget.repo.isProduction ? '取消及退款将按俱乐部服务条款处理。' : '这是演示预约，没有真实扣款。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保留预约'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (ok == true) await action(() => widget.repo.cancel(o));
  }

  Future<void> confirm(Json o) async {
    var rating = 5;
    final comment = TextEditingController();
    final yes = await showClubSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            18 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeading(
                '评价服务',
                caption: '确认后服务完成；有问题可先申请售后。',
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    tooltip: '${i + 1}星',
                    onPressed: () => set(() => rating = i + 1),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      i < rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFD9A21B),
                      size: 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: comment,
                maxLength: 200,
                maxLines: 3,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: '评价内容（选填）',
                  counterText: '',
                  hintText: '说说这次服务里具体的收获',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认服务完成'),
              ),
            ],
          ),
        ),
      ),
    );
    if (yes == true) {
      await action(() async {
        await widget.repo.orderAction(o, 'confirm', {
          'rating': rating,
          'comment': comment.text.trim(),
        });
      });
    }
    comment.dispose();
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final current =
        const {
          'awaiting_payment': 0,
          'awaiting_assignment': 1,
          'awaiting_acceptance': 1,
          'scheduled': 1,
          'in_progress': 2,
          'awaiting_confirmation': 2,
          'completed': 3,
        }[status] ??
        0;
    final labels = [
      '提交预约',
      '安排队友',
      status == 'awaiting_confirmation' ? '核对交付' : '服务中',
      '服务完成',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(4, (i) {
        final reached = i <= current;
        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: reached ? ink : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: reached ? ink : rule,
                        width: .7,
                      ),
                    ),
                    child: i < current
                        ? const Icon(
                            Icons.check_rounded,
                            size: 10,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  if (i < 3)
                    Expanded(
                      child: Container(
                        height: 1,
                        color: i < current ? ink : rule,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  color: reached ? ink : faint,
                  fontWeight: i == current ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class TimelineEntry extends StatelessWidget {
  const TimelineEntry({
    super.key,
    required this.title,
    required this.description,
    required this.time,
    this.last = false,
  });
  final String title, description, time;
  final bool last;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 18,
          child: Column(
            children: [
              const SizedBox(height: 5),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: last ? faint : ink,
                  borderRadius: BorderRadius.circular(3.5),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: rule,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: typeBodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(time, style: typeCaption),
                  ],
                ),
                const SizedBox(height: 2),
                Text(description, style: typeSecondary),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

String orderEventTitle(Json event) =>
    const {
      'created': '已提交预约',
      'assigned': '俱乐部已派单',
      'accepted': '陪练已接单',
      'started': '服务已开始',
      'submitted': '已提交服务记录',
      'confirmed': '客户已确认完成',
      'cancelled': '预约已取消',
      'declined': '陪练已退回派单',
      'disputed': '已申请售后',
    }[event['type']] ??
    '${event['message'] ?? event['type']}';

/// Shared guest entry, also used by the local gallery without fabricating a session.
class OrdersSignInPage extends StatelessWidget {
  const OrdersSignInPage(this.repo, {required this.onSignIn, super.key});
  final ClubRepository repo;
  final VoidCallback onSignIn;
  @override
  Widget build(BuildContext context) => ClubPage(
    repo: repo,
    title: '我的订单',
    tab: 2,
    child: PageList(
      children: [
        const SizedBox(height: 8),
        Surface(
          border: true,
          child: Column(
            children: [
              SizedBox(
                height: 104,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (repo.services.isNotEmpty)
                      ServiceArt(repo.services.first, radius: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Color(0xD90E131A), Color(0x660E131A)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '登录后同步预约',
                            style: typeSection.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '订单进度、服务记录与评价都在这里',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xCCFFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const EmptyState(
                '登录后查看订单',
                '查看预约安排和服务进度',
              ),
              FilledButton(onPressed: onSignIn, child: const Text('登录 / 注册')),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DemoStamp(repo),
      ],
    ),
  );
}
