import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'repository.dart';
import 'ui.dart';
import 'orders.dart';

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
  bool loading = false, busy = false;
  bool deliveryOpened = false;
  String? error;
  ClubRepository get repo => widget.repo;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (repo.isProduction && repo.token == null) {
      setState(() => error = '请先在“我的”页面登录俱乐部账号。');
      return;
    }
    setState(() => loading = true);
    try {
      await repo.loadMemberData();
      if (mounted) setState(() => error = null);
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
    if (error != null) {
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
    if (loading && repo.memberOrders.isEmpty) {
      return ClubPage(
        repo: repo,
        title: heading,
        tab: tab,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final order = repo.memberOrders
        .where((o) => o['id'] == widget.orderId)
        .firstOrNull;
    return ClubPage(
      repo: repo,
      title: heading,
      demoLabel: repo.isLocal ? '只读演示' : '演示',
      tab: tab,
      actions: [
        IconButton(
          tooltip: '刷新工作台',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      bottom: widget.mode == 'order' && order != null ? actions(order) : null,
      child: PageList(
        children: switch (widget.mode) {
          'home' => dashboard(),
          'orders' => queue(),
          'earnings' => ledger(),
          'order' => detail(order),
          _ => [],
        },
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
    return [
      Row(
        children: [
          if (player != null)
            PlayerArt(
              repo: repo,
              player: player,
              width: 46,
              height: 50,
              radius: 10,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player?['name'] ?? repo.memberName}',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '俱乐部成员',
                  style: const TextStyle(fontSize: 14, color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '通知',
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _metric('${assigned.length}', '待接单', Colors.white),
            _metric('${active.length}', '待服务', Colors.white),
            _metric(
              '¥${((totals['availableCents'] as num? ?? 0) / 100).toStringAsFixed(2)}',
              '可结算',
              const Color(0xFFC5CBD6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      InkWell(
        onTap: () => context.push('/member/availability'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 21),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '安排我的可接时段',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
      SectionTitle(
        '待你接单',

        action: '全部',
        onTap: () => context.go('/member/orders'),
      ),
      if (assigned.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            '暂时没有待接单，新的指派会在这里出现。',
            style: TextStyle(fontSize: 15, color: muted),
          ),
        ),
      ...assigned.take(2).map((o) => taskRow(o, urgent: true)),
      const SectionTitle('接下来的安排'),
      if (active.isEmpty)
        const Text('没有已排期的服务。', style: TextStyle(fontSize: 15, color: muted)),
      ...active.take(3).map((o) => taskRow(o)),
    ];
  }

  Widget _metric(String value, String label, Color color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ],
    ),
  );
  Widget taskRow(Json o, {bool urgent = false}) => InkWell(
    onTap: () => context.push('/member/orders/${o['id']}'),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      when(o['scheduledAt']),
                      style: const TextStyle(fontSize: 14, color: muted),
                    ),
                    const Spacer(),
                    Text(
                      stageName(stage(o)),
                      style: TextStyle(
                        fontSize: 15,
                        color: urgent ? brandColor(repo) : forest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  '${o['serviceTitle']}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Text(
                      '${o['durationMinutes'] ?? 60}分钟 · 预计收入 ',
                      style: const TextStyle(fontSize: 14, color: muted),
                    ),
                    Text(
                      '¥${money(o, 'memberCents')}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded, size: 17),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  List<Widget> queue() => [
    const Text('待接单与履约中的服务', style: TextStyle(color: muted, fontSize: 15)),
    const SizedBox(height: 14),
    if (repo.memberOrders.isEmpty)
      const EmptyState('还没有指派给你的服务', '在可接时段内，运营者可以向你派单。'),
    ...repo.memberOrders.map(
      (o) => taskRow(o, urgent: stage(o) == 'awaiting_acceptance'),
    ),
  ];
  List<Widget> detail(Json? o) {
    if (o == null) return [const EmptyState('找不到这笔服务', '订单可能尚未指派给你。')];
    return [
      Tag(stageName(stage(o)), fill: sage, color: forest),
      const SizedBox(height: 18),
      Text(
        '${o['serviceTitle']}',
        style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      Text(
        when(o['scheduledAt']),
        style: const TextStyle(fontSize: 16, color: muted),
      ),
      const SectionTitle('订单信息'),
      PairRow('服务时长', '${o['durationMinutes'] ?? 60} 分钟'),
      PairRow('客户联系', '${o['contact']}'),
      PairRow('客户备注', '${o['note'] ?? ''}'.isEmpty ? '未填写' : '${o['note']}'),
      if (o['acceptBy'] != null) PairRow('接单截止', when(o['acceptBy'])),
      const Divider(),
      Surface(
        color: sage,
        child: Column(
          children: [
            PairRow('订单金额', '¥${money(o)}'),
            PairRow(
              '本单俱乐部分成',
              '${((o['commissionBps'] as num? ?? 0) / 100).toStringAsFixed(0)}%',
            ),
            PairRow('你的预计收入', '¥${money(o, 'memberCents')}', strong: true),
            const SizedBox(height: 8),
            const Text(
              '比例在派单时确定。客户确认完成且无争议后，才进入可结算账目。',
              style: TextStyle(fontSize: 14, color: muted, height: 1.7),
            ),
          ],
        ),
      ),
      if (o['delivery'] is Map) ...[
        const SectionTitle('你提交的服务记录'),
        Text(
          '${o['delivery']['summary']}',
          style: const TextStyle(fontSize: 14, height: 1.8),
        ),
        if (o['delivery']['evidenceUrl'] != null)
          SelectableText(
            '${o['delivery']['evidenceUrl']}',
            style: const TextStyle(fontSize: 14, color: muted),
          ),
      ],
      const SectionTitle('履约记录'),
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
        const SizedBox(width: 12),
        Expanded(
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
      style: const TextStyle(fontSize: 15, color: muted),
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
              24,
              0,
              24,
              24 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '留下这场服务的记录',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '描述实际完成的内容，客户核对后确认完成。',
                    style: TextStyle(fontSize: 14, color: muted),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: summary,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: '服务说明',
                      hintText: '练习内容、配合情况、约定事项是否完成',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: evidence,
                    decoration: const InputDecoration(
                      labelText: '交付凭证 HTTPS 链接（选填）',
                    ),
                  ),
                  if (fail != null)
                    Text(fail!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 18),
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
                    child: Text(repo.isLocal ? '只读演示 · 不提交' : '提交给客户确认'),
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
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(fontSize: 14, color: muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: text,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(labelText: label),
              ),
              const SizedBox(height: 16),
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
    return [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '可结算金额',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Text(
              '¥${((totals['availableCents'] as num? ?? 0) / 100).toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _metric(
                  '¥${((totals['heldCents'] as num? ?? 0) / 100).toStringAsFixed(2)}',
                  '待确认 / 冻结',
                  Colors.white,
                ),
                _metric(
                  '¥${((totals['settledCents'] as num? ?? 0) / 100).toStringAsFixed(2)}',
                  '已记录结算',
                  Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        '结算由俱乐部处理，请核对实际到账。',
        style: TextStyle(fontSize: 14, color: muted, height: 1.8),
      ),
      const SectionTitle('每笔服务的分成'),
      if (entries.isEmpty) const EmptyState('暂时没有收入记录', '完成服务并由客户确认后，会生成相应账目。'),
      ...entries.map(
        (e) => Container(
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: rule)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '服务 #${e['orderId'].toString().substring(0, 8)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '¥${money(e, 'memberCents')}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      when(e['createdAt']),
                      style: const TextStyle(fontSize: 14, color: muted),
                    ),
                  ),
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
                ],
              ),
              if (e['settlementId'] != null)
                TextButton(
                  onPressed: () => textSheet(
                    context,
                    '结算凭据',
                    _settlement(e['settlementId']),
                  ),
                  child: const Text('查看结算记录'),
                ),
            ],
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
  bool loading = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      slots = await widget.repo.memberAvailability();
      error = null;
    } catch (e) {
      error = '$e'.replaceFirst('Exception: ', '');
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
      child: Text(
        widget.repo.isLocal
            ? '只读演示'
            : saving
            ? '正在保存…'
            : '保存可接时段',
      ),
    ),
    child: PageList(
      children: [
        const Text(
          '可接时段',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          '北京时间',
          style: TextStyle(fontSize: 15, color: muted, height: 1.8),
        ),
        const SizedBox(height: 20),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          EmptyState(
            '暂时无法加载排班',
            error!,
            action: TextButton(onPressed: load, child: const Text('重试')),
          ),
        if (!loading && error == null) ...[
          if (slots.isEmpty) const EmptyState('还没有开放时段', '添加可接时段后，俱乐部才能向你派单。'),
          ...slots.asMap().entries.map(
            (e) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: Text(when(e.value['startAt'])),
              subtitle: Text('至 ${when(e.value['endAt'])}'),
              trailing: IconButton(
                tooltip: '移除此时段',
                onPressed: widget.repo.isLocal
                    ? null
                    : () => setState(() => slots.removeAt(e.key)),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: widget.repo.isLocal ? null : add,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加可接时段'),
          ),
        ],
      ],
    ),
  );
}
