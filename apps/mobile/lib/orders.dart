import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'repository.dart';
import 'ui.dart';
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
      context.go('/profile');
      return;
    }
    setState(() => loading = true);
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
    final items = repo.orders
        .where(
          (o) =>
              filter == '全部' ||
              (filter == '已结束'
                  ? ['completed', 'cancelled'].contains(stage(o))
                  : !['completed', 'cancelled'].contains(stage(o))),
        )
        .toList();
    return ClubPage(
      repo: repo,
      title: '我的订单',
      tab: 2,
      actions: [
        IconButton(
          tooltip: '刷新预约',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: PageList(
        children: [
          Row(
            children: ['进行中', '已结束', '全部']
                .map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(v),
                      selected: filter == v,
                      onSelected: (_) => setState(() => filter = v),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
          if (loading) const LinearProgressIndicator(),
          if (failure != null)
            Text(failure!, style: const TextStyle(color: Colors.red)),
          if (items.isEmpty)
            EmptyState(
              '这里还没有预约',
              '找到喜欢的服务，和合拍的队友一起开始。',
              action: FilledButton(
                onPressed: () => context.go('/services'),
                child: const Text('去发现服务'),
              ),
            ),
          ...items.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                onTap: () => context.push('/orders/${o['id']}'),
                child: Surface(
                  border: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Tag(stageName(stage(o)), fill: sage, color: forest),
                          const Spacer(),
                          const Icon(Icons.arrow_outward_rounded, size: 19),
                        ],
                      ),
                      const SizedBox(height: 17),
                      Text(
                        '${o['serviceTitle']}',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        when(o['scheduledAt']),
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Text(
                            '${repo.findPlayer(o['assignedPlayerId'] ?? o['playerId'])?['name'] ?? '等待俱乐部安排队友'}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const Spacer(),
                          Text(
                            '¥${money(o)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
  bool busy = false;
  String? failure;
  Json? get order =>
      widget.repo.orders.where((o) => o['id'] == widget.id).firstOrNull;
  @override
  void initState() {
    super.initState();
    if (!widget.repo.isLocal && widget.repo.token != null) refresh();
  }

  Future<void> refresh() async {
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
    if (o == null) {
      return ClubPage(
        repo: repo,
        title: '预约详情',
        child: EmptyState(
          '暂时没有这笔预约',
          failure ?? '请登录后查看，或返回预约列表。',
          action: FilledButton(
            onPressed: () => context.go('/orders'),
            child: const Text('查看预约'),
          ),
        ),
      );
    }
    final status = stage(o),
        player = repo.findPlayer(o['assignedPlayerId'] ?? o['playerId']);
    final events = (o['events'] as List? ?? [])
        .map((e) => Json.from(e))
        .toList();
    final title = stageName(status);
    return ClubPage(
      repo: repo,
      title: '订单详情',
      actions: [
        IconButton(
          tooltip: '刷新进度',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      bottom: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  ['cancelled', 'awaiting_payment', 'disputed'].contains(status)
                  ? () => textSheet(
                      context,
                      '服务条款',
                      '${repo.club['termsText'] ?? ''}',
                    )
                  : () => context.push('/orders/${o['id']}/support'),
              icon: const Icon(Icons.headset_mic_outlined, size: 18),
              label: Text(
                ['cancelled', 'awaiting_payment', 'disputed'].contains(status)
                    ? '服务条款'
                    : '申请售后',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
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
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(),
              Text(
                '#${o['id'].toString().split('-').last.substring(0, o['id'].toString().split('-').last.length.clamp(0, 8))}',
                style: const TextStyle(fontSize: 13, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 20),
          _ProgressStrip(status),
          const SizedBox(height: 24),
          Surface(
            border: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: sage,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.sports_esports_outlined,
                        size: 23,
                        color: forest,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${o['serviceTitle']}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${o['serviceSnapshot']?['variantTitle'] ?? '${o['serviceSnapshot']?['durationMinutes'] ?? o['durationMinutes'] ?? repo.findService(o['serviceId'])?['durationMinutes'] ?? 60} 分钟'}',
                            style: const TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(),
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
            const SizedBox(height: 16),
            Surface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Colors.white,
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
          SectionTitle('订单进度'),
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
                description: '${(e.value['actor'] as Map?)?['name'] ?? '俱乐部'}',
                time: when(e.value['at']),
                last: e.key == events.length - 1,
              ),
            ),
          if (o['delivery'] is Map) ...[
            const Divider(),
            const Text(
              '队友的服务记录',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Surface(
              color: sage,
              child: Text(
                '${o['delivery']['summary']}',
                style: const TextStyle(fontSize: 16, height: 1.7),
              ),
            ),
          ],
          if (o['dispute'] is Map) ...[
            const SizedBox(height: 18),
            Surface(
              color: sand,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '售后记录',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text('${o['dispute']['reason']}'),
                  Text(
                    '${o['dispute']['details'] ?? ''}',
                    style: const TextStyle(fontSize: 14, color: muted),
                  ),
                ],
              ),
            ),
          ],
          const Divider(),
          PairRow('联系方式', '${o['contact']}'),
          PairRow(
            '预约备注',
            '${o['note'] ?? ''}'.isEmpty ? '未填写' : '${o['note']}',
          ),
          if ([
            'awaiting_assignment',
            'awaiting_acceptance',
            'scheduled',
            'awaiting_payment',
          ].contains(status))
            TextButton(
              onPressed: busy ? null : () => cancel(o),
              child: const Text('取消预约'),
            ),
          if (!['cancelled', 'awaiting_payment', 'disputed'].contains(status))
            TextButton(
              onPressed: () => context.push('/orders/${o['id']}/support'),
              child: const Text('遇到问题，申请售后'),
            ),
          if (failure != null)
            Text(
              failure!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Future<void> primaryAction(Json o) async {
    final repo = widget.repo;
    switch (stage(o)) {
      case 'awaiting_payment':
        await action(() async {
          await repo.pay(o);
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
        context.push(
          '/book?service=${o['serviceId']}${o['variantId'] == null ? '' : '&variant=${o['variantId']}'}${o['assignedPlayerId'] == null ? '' : '&player=${o['assignedPlayerId']}'}',
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
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '这一场，感觉如何？',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '确认后服务完成；有问题可先申请售后。',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    tooltip: '${i + 1}星',
                    onPressed: () => set(() => rating = i + 1),
                    icon: Icon(
                      i < rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: forest,
                      size: 32,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: comment,
                maxLength: 200,
                decoration: const InputDecoration(labelText: '说说这次配合（选填）'),
              ),
              const SizedBox(height: 16),
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
    return Row(
      children: List.generate(
        4,
        (i) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: i <= current ? forest : rule,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      i < current ? Icons.check_rounded : Icons.circle,
                      size: i < current ? 13 : 6,
                      color: i <= current ? Colors.white : muted,
                    ),
                  ),
                  if (i < 3)
                    Expanded(
                      child: Container(
                        height: 1,
                        color: i < current ? forest : rule,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                ['提交预约', '安排队友', '服务中', '服务完成'][i],
                style: TextStyle(
                  fontSize: 13,
                  color: i <= current ? ink : muted,
                  fontWeight: i == current ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
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
          width: 22,
          child: Column(
            children: [
              const SizedBox(height: 6),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: forest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (!last) Expanded(child: Container(width: 1, color: rule)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$description · $time',
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
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
