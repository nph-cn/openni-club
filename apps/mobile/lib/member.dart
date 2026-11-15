import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;

import 'repository.dart';
import 'ui.dart';
import 'orders.dart';
import 'loading.dart';
import 'discover.dart';

String slotDay(dynamic value) {
  final time = DateTime.tryParse('$value')
      ?.toUtc()
      .add(const Duration(hours: 8));
  return time == null ? '--' : '${time.day}';
}

class MemberPage extends StatefulWidget {
  const MemberPage(
    this.repo, {
    super.key,
    this.mode = 'home',
    this.orderId,
    this.openDelivery = false,
  });
  final ClubRepository repo;
  final String mode;
  final String? orderId;
  final bool openDelivery;
  @override
  State<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends State<MemberPage> {
  bool loading = false, busy = false, loaded = false;
  bool deliveryOpened = false;
  String orderFilter = '待接单';
  String? error;
  ClubRepository get repo => widget.repo;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    if (repo.isProduction && repo.token == null) {
      setState(() => error = '请先在“我的”页面登录俱乐部账号。');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await repo.loadMemberData();
      if (mounted) setState(() => loaded = true);
      if (mounted && widget.openDelivery && !deliveryOpened) {
        final o = repo.memberOrders
            .where(
              (o) => o['id'] == widget.orderId && stage(o) == 'in_progress',
            )
            .firstOrNull;
        if (o != null) {
          deliveryOpened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) submit(o);
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> act(Json order, String action, [Json body = const {}]) async {
    setState(() => busy = true);
    try {
      await repo.memberAction(order, action, body);
      if (mounted) toast(context, '订单已更新。');
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heading = {
      'home': '成员工作台',
      'orders': '我的服务',
      'earnings': '收入账本',
      'order': '履约详情',
    }[widget.mode]!;
    final tab = {'home': 0, 'orders': 1, 'earnings': 2}[widget.mode];
    final order = repo.memberOrders
        .where((o) => o['id'] == widget.orderId)
        .firstOrNull;
    final hasContent = widget.mode == 'order'
        ? order != null
        : loaded || repo.memberOrders.isNotEmpty || repo.earnings.isNotEmpty;
    if (loading && !hasContent) {
      return ClubPage(
        repo: repo,
        title: heading,
        tab: tab,
        child: ClubSkeleton(
          kind: switch (widget.mode) {
            'orders' => SkeletonKind.catalog,
            'earnings' => SkeletonKind.earnings,
            'order' => SkeletonKind.order,
            _ => SkeletonKind.member,
          },
        ),
      );
    }
    if (error != null && !hasContent) {
      return ClubPage(
        repo: repo,
        title: heading,
        tab: tab,
        child: EmptyState(
          '暂时无法进入工作台',
          error!,
          action: OutlinedButton(onPressed: load, child: const Text('重新连接')),
        ),
      );
    }
    final children = switch (widget.mode) {
      'home' => dashboard(),
      'orders' => queue(),
      'earnings' => ledger(),
      'order' => detail(order),
      _ => <Widget>[],
    };
    return ClubPage(
      repo: repo,
      title: heading,
      tab: tab,
      actions: [
        IconButton(
          tooltip: '刷新工作台',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
      ],
      bottom: widget.mode == 'order' && order != null ? actions(order) : null,
      child: PageList(
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Row(
              children: [
                Expanded(
                  child: Text(error!, style: typeSecondary),
                ),
                TextButton(onPressed: load, child: const Text('重试')),
              ],
            ),
          ...children,
          DemoStamp(
            repo,
            text: '成员演示数据来自只读快照：订单、分成与结算记录均为示例，不产生真实打款。',
          ),
        ],
      ),
    );
  }

  List<Widget> dashboard() {
    final assigned = repo.memberOrders
            .where((o) => stage(o) == 'awaiting_acceptance')
            .toList(),
        active = repo.memberOrders
            .where((o) => ['scheduled', 'in_progress'].contains(stage(o)))
            .toList();
    final player = repo.findPlayer(repo.memberPlayerId),
        totals = repo.earnings['totals'] as Map? ?? {};
    final scene = player == null ? repo.services.firstOrNull : sceneForPlayer(repo, player);
    final unread = repo.notifications.where((n) => n['readAt'] == null).length;
    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: SizedBox(
          height: 186,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (scene != null) ServiceArt(scene, radius: 0),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC0B0F14),
                      Color(0xE60B0F14),
                      Color(0xF20B0F14),
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
                        if (player != null)
                          PlayerArt(
                            repo: repo,
                            player: player,
                            width: 38,
                            height: 42,
                            radius: 11,
                          ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${player?['name'] ?? repo.memberName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Row(
                                children: [
                                  const Text(
                                    '俱乐部成员 · 服务队列',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xB3FFFFFF),
                                    ),
                                  ),
                                  if (repo.tierFor(player ?? Json.from(<String, dynamic>{})) !=
                                      null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: .14),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: TierBadge(
                                        tier: repo.tierFor(player ?? Json.from(<String, dynamic>{})),
                                        compact: true,
                                      ),
                                    ),
                                  ],
                                  if (player?['certified'] == true) ...[
                                    const SizedBox(width: 5),
                                    const Icon(
                                      Icons.verified_rounded,
                                      size: 12,
                                      color: Color(0xFFE7C777),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            IconButton(
                              tooltip: '通知',
                              onPressed: () => context.push('/notifications'),
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                                size: 19,
                                color: Colors.white,
                              ),
                            ),
                            if (unread > 0)
                              Positioned(
                                top: 9,
                                right: 9,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE95D4F),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _heroMetric(
                          value: '${assigned.length}',
                          label: '待接单',
                          highlight: assigned.isNotEmpty,
                        ),
                        _heroMetric(
                          value: '${active.length}',
                          label: '待服务',
                        ),
                        _heroMetric(
                          value:
                              '¥${((totals['availableCents'] as num? ?? 0) / 100).toStringAsFixed(0)}',
                          label: '可结算',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _memberShortcut(
              icon: Icons.calendar_month_outlined,
              label: '可接时段',
              onTap: () => context.push('/member/availability'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _memberShortcut(
              icon: Icons.account_balance_wallet_outlined,
              label: '收入账本',
              onTap: () => context.go('/member/earnings'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _memberShortcut(
              icon: Icons.assignment_outlined,
              label: '我的服务',
              onTap: () => context.go('/member/orders'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _memberShortcut(
              icon: Icons.military_tech_outlined,
              label: '分级与认证',
              onTap: () => context.push('/club/tiers'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _memberShortcut(
              icon: Icons.tune_rounded,
              label: '俱乐部能力',
              onTap: () => context.push('/club/features'),
            ),
          ),
        ],
      ),
      SectionTitle(
        '待你接单',
        caption: assigned.isEmpty ? null : '确认后可开始安排档期',
        action: '全部',
        onTap: () => context.go('/member/orders'),
      ),
      if (assigned.isEmpty)
        Surface(
          border: true,
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.tray,
                size: 17,
                color: faint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '暂时没有待接单，新的指派会在这里出现。',
                  style: typeSecondary,
                ),
              ),
            ],
          ),
        ),
      for (final o in assigned.take(2)) taskRow(o, urgent: true),
      const SectionTitle('接下来的安排'),
      if (active.isEmpty)
        const Text('没有已排期的服务。', style: typeSecondary),
      for (final o in active.take(3)) taskRow(o),
    ];
  }

  Widget _heroMetric({
    required String value,
    required String label,
    bool highlight = false,
  }) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
            fontFeatures: [FontFeature.tabularFigures()],
            color: highlight ? const Color(0xFFFFD58A) : Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Color(0xB3FFFFFF)),
        ),
      ],
    ),
  );

  Widget taskRow(Json o, {bool urgent = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/member/orders/${o['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StagePill(stage(o)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      when(o['scheduledAt']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typeCaption,
                    ),
                  ),
                  const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 12,
                    color: faint,
                  ),
                ],
              ),
              const SizedBox(height: 9),
              OrderServiceSummary(repo: repo, order: o),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Divider(height: .5, thickness: .5),
              ),
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.person,
                    size: 12,
                    color: faint,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${o['contact'] ?? '客户联系方式待同步'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typeCaption,
                    ),
                  ),
                  Text('预计收入', style: typeCaption),
                  const SizedBox(width: 5),
                  Text(
                    '¥${money(o, 'memberCents')}',
                    style: typeLabel.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _memberShortcut({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
        child: Row(
          children: [
            Icon(icon, size: 15, color: muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typeLabel.copyWith(fontSize: 12),
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 11,
              color: faint,
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> queue() {
    final items =
        repo.memberOrders.where((o) {
          final status = stage(o);
          return switch (orderFilter) {
            '待接单' => status == 'awaiting_acceptance',
            '已结束' => ['completed', 'cancelled'].contains(status),
            _ => ![
              'awaiting_acceptance',
              'completed',
              'cancelled',
            ].contains(status),
          };
        }).toList()..sort(
          (a, b) => '${a['scheduledAt']}'.compareTo('${b['scheduledAt']}'),
        );
    return [
      ClubSegmentedControl(
        values: const ['待接单', '服务中', '已结束'],
        value: orderFilter,
        onChanged: (value) => setState(() => orderFilter = value),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Text('${items.length} 笔服务', style: typeSecondary),
          const Spacer(),
          Text('按预约时间排序', style: typeCaption),
        ],
      ),
      const SizedBox(height: 8),
      if (items.isEmpty)
        EmptyState(switch (orderFilter) {
          '待接单' => '暂时没有待接单',
          '已结束' => '还没有结束的服务',
          _ => '暂时没有进行中的服务',
        }, orderFilter == '待接单' ? '俱乐部安排的预约会出现在这里。' : '服务状态更新后，会同步到对应列表。'),
      for (final o in items) taskRow(o, urgent: orderFilter == '待接单'),
    ];
  }

  List<Widget> detail(Json? o) {
    if (o == null) return [const EmptyState('找不到这笔服务', '订单可能尚未指派给你。')];
    final status = stage(o);
    final service =
        repo.findService('${o['serviceId']}') ??
        Json.from(o['serviceSnapshot'] as Map? ?? const {});
    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: SizedBox(
          height: 132,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ServiceArt(service, radius: 0),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xE60B0F14), Color(0x990B0F14), Color(0x330B0F14)],
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
                        Flexible(
                          child: Text(
                            '履约单 ${o['id']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xB3FFFFFF),
                            ),
                          ),
                        ),
                        if (o['acceptBy'] != null) ...[
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '接单截止 ${when(o['acceptBy'])}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xCCFFFFFF),
                              ),
                            ),
                          ),
                        ],
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
                    const SizedBox(height: 3),
                    Text(
                      '${when(o['scheduledAt'])} · ${orderSpecification(o)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
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
      const SizedBox(height: 10),
      Surface(border: true, child: OrderServiceSummary(repo: repo, order: o)),
      const SectionTitle('服务约定'),
      Surface(
        border: true,
        child: Column(
          children: [
            PairRow('客户联系', '${o['contact']}'),
            PairRow(
              '客户备注',
              '${o['note'] ?? ''}'.isEmpty ? '未填写' : '${o['note']}',
            ),
            if (o['acceptBy'] != null) PairRow('接单截止', when(o['acceptBy'])),
          ],
        ),
      ),
      if (o['delivery'] is Map) ...[
        const SectionTitle('已提交的服务记录'),
        Surface(
          border: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${(o['delivery'] as Map)['summary']}',
                style: typeBodySmall.copyWith(height: 1.6),
              ),
              if ((o['delivery'] as Map)['evidenceUrl'] != null) ...[
                const SizedBox(height: 9),
                Text('交付凭证', style: typeCaption),
                SelectableText(
                  '${(o['delivery'] as Map)['evidenceUrl']}',
                  style: typeSecondary.copyWith(color: link),
                ),
              ],
            ],
          ),
        ),
      ],
      const SectionTitle('收入明细'),
      Surface(
        border: true,
        child: Column(
          children: [
            PairRow('订单金额', '¥${money(o)}'),
            PairRow(
              '俱乐部分成',
              '${((o['commissionBps'] as num? ?? 0) / 100).toStringAsFixed(0)}%',
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 3),
              child: Divider(height: .5, thickness: .5),
            ),
            PairRow('你的预计收入', '¥${money(o, 'memberCents')}', strong: true),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '客户确认完成且无争议后，进入可结算账目。',
                style: typeCaption,
              ),
            ),
          ],
        ),
      ),
      const SectionTitle('履约记录', caption: '时间均为北京时间'),
      ...(o['events'] as List? ?? []).asMap().entries.map((e) {
        final v = e.value as Map;
        return TimelineEntry(
          title: orderEventTitle(Json.from(v)),
          description: '${v['actor']?['name'] ?? ''}',
          time: when(v['at']),
          last: e.key == (o['events'] as List).length - 1,
        );
      }),
    ];
  }

  Widget actions(Json o) => switch (stage(o)) {
    'awaiting_acceptance' => Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy || repo.isLocal ? null : () => decline(o),
            child: const Text('无法接单'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: busy || repo.isLocal ? null : () => act(o, 'accept'),
            child: const Text('确认接单'),
          ),
        ),
      ],
    ),
    'scheduled' => FilledButton(
      onPressed: busy || repo.isLocal ? null : () => act(o, 'start'),
      child: Text(busy ? '正在更新…' : '开始服务'),
    ),
    'in_progress' => FilledButton(
      onPressed: busy ? null : () => submit(o),
      child: const Text('提交服务记录'),
    ),
    _ => Text(
      stage(o) == 'awaiting_confirmation' ? '已提交，等待客户确认。' : '当前状态无需成员操作。',
      textAlign: TextAlign.center,
      style: typeSecondary,
    ),
  };
  Future<void> decline(Json o) async {
    final reason = await inputSheet(
      '这次无法接单的原因',
      '说明原因，方便俱乐部重新安排。',
      label: '拒单原因',
    );
    if (reason != null) await act(o, 'decline', {'reason': reason});
  }

  Future<void> submit(Json o) async {
    final summary = TextEditingController(), evidence = TextEditingController();
    String? fail;
    final yes = await showClubSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              0,
              18,
              18 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHeading(
                    '留下这场服务的记录',
                    caption: '描述实际完成的内容，客户核对后确认完成。',
                  ),
                  TextField(
                    controller: summary,
                    maxLines: 4,
                    maxLength: 2000,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: '服务说明',
                      hintText: '练习内容、配合情况、约定事项是否完成',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: evidence,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: '交付凭证 HTTPS 链接（选填）',
                      hintText: 'https://',
                    ),
                  ),
                  if (fail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        fail!,
                        style: const TextStyle(color: danger, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: repo.isLocal
                        ? null
                        : () {
                            if (summary.text.trim().length < 5) {
                              set(() => fail = '请说明实际完成的服务内容。');
                              return;
                            }
                            if (evidence.text.isNotEmpty &&
                                Uri.tryParse(evidence.text.trim())?.scheme !=
                                    'https') {
                              set(() => fail = '凭证链接必须以 https:// 开头。');
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                    child: const Text('提交给客户确认'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (yes == true) {
      await act(o, 'submit', {
        'summary': summary.text.trim(),
        if (evidence.text.trim().isNotEmpty)
          'evidenceUrl': evidence.text.trim(),
      });
    }
    summary.dispose();
    evidence.dispose();
  }

  Future<String?> inputSheet(
    String title,
    String description, {
    required String label,
  }) async {
    final text = TextEditingController();
    final result = await showClubSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
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
              SheetHeading(title, caption: description),
              TextField(
                controller: text,
                maxLength: 500,
                maxLines: 3,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(labelText: label, counterText: ''),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  if (text.text.trim().length >= 3) {
                    Navigator.pop(ctx, text.text.trim());
                  }
                },
                child: const Text('确认提交'),
              ),
            ],
          ),
        ),
      ),
    );
    text.dispose();
    return result;
  }

  List<Widget> ledger() {
    final totals = repo.earnings['totals'] as Map? ?? {},
        entries = (repo.earnings['entries'] as List? ?? [])
            .map((e) => Json.from(e))
            .toList();
    final settled = (totals['settledCents'] as num? ?? 0) / 100,
        held = (totals['heldCents'] as num? ?? 0) / 100,
        available = (totals['availableCents'] as num? ?? 0) / 100;
    final maxValue = [settled, held, available, 1].reduce(
      (a, b) => a > b ? a : b,
    );
    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Container(
          color: ink,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.creditcard,
                    size: 14,
                    color: Color(0xB3FFFFFF),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '可结算金额',
                    style: typeSecondary.copyWith(color: const Color(0xB3FFFFFF)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '由俱乐部结算',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: Color(0xCCFFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '¥${available.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              for (final row in [
                ('已记录结算', settled, const Color(0xFF8FD3AC)),
                ('待确认 / 冻结', held, const Color(0xFFE8C87B)),
                ('可结算', available, const Color(0xFF92B4F2)),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(
                          row.$1,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xB3FFFFFF),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (row.$2 / maxValue).clamp(0.02, 1.0),
                            minHeight: 5,
                            backgroundColor: Colors.white.withValues(alpha: .12),
                            valueColor: AlwaysStoppedAnimation<Color>(row.$3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      SizedBox(
                        width: 54,
                        child: Text(
                          '¥${row.$2.toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xE6FFFFFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          const Icon(
            CupertinoIcons.info_circle,
            size: 12,
            color: faint,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '结算由俱乐部处理，请核对实际到账；演示记录不代表真实收入。',
              style: typeCaption,
            ),
          ),
        ],
      ),
      const SectionTitle('每笔服务的分成'),
      if (entries.isEmpty)
        const EmptyState('暂时没有收入记录', '完成服务并由客户确认后，会生成相应账目。'),
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: stageFill(
                            e['state'] == 'available'
                                ? 'completed'
                                : e['state'] == 'held'
                                ? 'awaiting_confirmation'
                                : 'cancelled',
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          e['state'] == 'available'
                              ? Icons.check_rounded
                              : e['state'] == 'held'
                              ? Icons.hourglass_bottom_rounded
                              : Icons.receipt_long_outlined,
                          size: 15,
                          color: ink,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '服务 #${e['orderId'].toString().substring(0, 8)}',
                              style: typeBodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(when(e['createdAt']), style: typeCaption),
                          ],
                        ),
                      ),
                      Text(
                        '¥${money(e, 'memberCents')}',
                        style: typeNumber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Tag(
                        const {
                              'held': '待确认 / 冻结',
                              'available': '可结算',
                              'settled': '已记录结算',
                              'reversed': '已撤销',
                            }[e['state']] ??
                            '待处理',
                        fill: e['state'] == 'available' ? sage : sand,
                        color: ink,
                      ),
                      const Spacer(),
                      if (e['settlementId'] != null)
                        TextButton(
                          onPressed: () => textSheet(
                            context,
                            '结算凭据',
                            _settlement(e['settlementId']),
                          ),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child: const Text('查看结算记录'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  String _settlement(String id) {
    final s = (repo.earnings['settlements'] as List? ?? [])
        .where((v) => v['id'] == id)
        .firstOrNull;
    return s == null
        ? '暂未找到结算记录，请联系俱乐部核对。'
        : '付款凭据：${s['paymentReference']}\n说明：${s['note'] ?? ''}\n\n系统没有执行自动转账，请核对实际到账。';
  }
}

class AvailabilityPage extends StatefulWidget {
  const AvailabilityPage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  State<AvailabilityPage> createState() => _AvailabilityPageState();
}

class _AvailabilityPageState extends State<AvailabilityPage> {
  List<Json> slots = [];
  bool loading = false, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.repo.memberAvailability();
      if (mounted) setState(() => slots = result);
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> add() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 89)),
      initialDate: now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
      helpText: '开始时间（北京时间）',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 22, minute: 0),
      helpText: '结束时间（北京时间）',
    );
    if (end == null || !mounted) return;
    final a = DateTime.utc(
          date.year,
          date.month,
          date.day,
          start.hour,
          start.minute,
        ).subtract(const Duration(hours: 8)),
        b = DateTime.utc(
          date.year,
          date.month,
          date.day,
          end.hour,
          end.minute,
        ).subtract(const Duration(hours: 8));
    if (!b.isAfter(a)) {
      toast(context, '结束时间需要晚于开始时间。');
      return;
    }
    setState(
      () => slots.add({
        'startAt': a.toIso8601String(),
        'endAt': b.toIso8601String(),
      }),
    );
  }

  @override
  Widget build(BuildContext context) => ClubPage(
    repo: widget.repo,
    title: '我的可接时段',
    bottom: FilledButton(
      onPressed: saving || loading || error != null || widget.repo.isLocal
          ? null
          : () async {
              setState(() => saving = true);
              try {
                await widget.repo.setMemberAvailability(slots);
                if (context.mounted) toast(context, '可接时段已保存。');
              } catch (e) {
                if (context.mounted) toast(context, e);
              } finally {
                if (mounted) setState(() => saving = false);
              }
            },
      child: Text(saving ? '正在保存…' : '保存可接时段'),
    ),
    child: loading
        ? const ClubSkeleton(kind: SkeletonKind.availability)
        : PageList(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('可接时段', style: typeTitle),
                        const SizedBox(height: 2),
                        Text(
                          '北京时间 · 由你维护，俱乐部按此时段派单',
                          style: typeSecondary,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${slots.length} 段',
                    style: typeNumber,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (error != null)
                EmptyState(
                  '暂时无法加载排班',
                  error!,
                  action: TextButton(onPressed: load, child: const Text('重试')),
                ),
              if (error == null) ...[
                if (slots.isEmpty)
                  const EmptyState('还没有开放时段', '添加可接时段后，俱乐部才能向你派单。'),
                for (final slot in slots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(11, 10, 6, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 40,
                              decoration: BoxDecoration(
                                color: sage,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    slotDay(slot['startAt']),
                                    style: typeLabel.copyWith(fontSize: 13),
                                  ),
                                  Text('日', style: typeCaption),
                                ],
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    when(slot['startAt']),
                                    style: typeBodySmall.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    '至 ${when(slot['endAt'])}',
                                    style: typeSecondary,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '移除此时段',
                              onPressed: widget.repo.isLocal
                                  ? null
                                  : () => setState(
                                      () => slots.remove(slot),
                                    ),
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: faint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: widget.repo.isLocal ? null : add,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('添加可接时段'),
                ),
                if (widget.repo.isLocal)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '离线只读演示：排班修改需要连接俱乐部 API。',
                      style: typeCaption,
                    ),
                  ),
              ],
              DemoStamp(
                widget.repo,
                text: '排班数据来自成员演示快照，仅用于界面预览。',
              ),
            ],
          ),
  );
}

