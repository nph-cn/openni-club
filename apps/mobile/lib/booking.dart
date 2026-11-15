import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;

import 'repository.dart';
import 'discover.dart' show ServiceArt;
import 'ui.dart';
import 'auth.dart';
import 'loading.dart';

class BookingPage extends StatefulWidget {
  const BookingPage(
    this.repo,
    this.serviceId, {
    super.key,
    this.playerId,
    this.variantId,
    this.previewCheckout = false,
  });
  final ClubRepository repo;
  final String serviceId;
  final String? playerId;
  final String? variantId;
  final bool previewCheckout;
  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final scroll = ScrollController(keepScrollOffset: false);
  final form = GlobalKey<FormState>(),
      contact = TextEditingController(),
      note = TextEditingController();
  late DateTime day;
  late final String requestId;
  String? playerId;
  String? variantId;
  Json? selectedSlot;
  List<Json>? slots;
  String? failure, slotFailure;
  bool busy = false, checking = false, reviewing = false, accepted = false;
  int fetchId = 0;
  ClubRepository get repo => widget.repo;
  Json? get baseService => repo.findService(widget.serviceId);
  Json? get service =>
      baseService == null ? null : selectedService(baseService!, variantId);
  List<Json> get eligible => repo.players
      .where((p) => (p['games'] as List).contains(service?['game']))
      .toList();
  @override
  void initState() {
    super.initState();
    final now = repo.now.toUtc().add(const Duration(hours: 8));
    day = DateTime(now.year, now.month, now.day);
    playerId = widget.playerId;
    variantId =
        widget.variantId ??
        (baseService == null
            ? null
            : serviceVariants(baseService!).firstOrNull?['id']);
    requestId = 'mobile-${DateTime.now().microsecondsSinceEpoch}';
    if (widget.previewCheckout && repo.isLocal && !repo.isProduction) {
      preparePreview();
    } else if (playerId != null) {
      loadSlots();
    }
  }

  Future<void> preparePreview() async {
    playerId = eligible.firstOrNull?['id'];
    if (playerId == null) return;
    await loadSlots();
    if (!mounted || slots == null) return;
    final firstAvailable = slots!
        .where((s) => s['available'] == true)
        .firstOrNull;
    if (firstAvailable == null) return;
    setState(() {
      selectedSlot = firstAvailable;
      contact.text = 'demo-player';
      reviewing = true;
    });
    resetReviewScroll();
  }

  @override
  void dispose() {
    scroll.dispose();
    contact.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> loadSlots() async {
    final revision = ++fetchId;
    setState(() {
      checking = true;
      slotFailure = null;
      slots = null;
      selectedSlot = null;
      failure = null;
    });
    try {
      final result = await repo.getAvailability(
        playerId!,
        day,
        service!['durationMinutes'],
      );
      if (mounted && revision == fetchId) {
        setState(() => slots = result.where(isFutureSlot).toList());
      }
    } catch (e) {
      if (mounted && revision == fetchId) {
        setState(() => slotFailure = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && revision == fetchId) setState(() => checking = false);
    }
  }

  // 排班返回后也可能经过等待；显示与提交均遵守服务端的一分钟提前量。
  bool isFutureSlot(Json slot) {
    final start = DateTime.tryParse('${slot['startAt']}');
    return start != null &&
        !start.isBefore(repo.now.toUtc().add(const Duration(minutes: 1)));
  }

  Future<void> choosePlayer() async {
    final id = await showClubSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: canvas,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHeading(
                '选择意向队友',
                caption: '俱乐部会核对档期。最终服务队友以订单安排为准。',
              ),
              if (eligible.isEmpty) const EmptyState('暂无可选陪练', '请选择其他服务'),
              ...eligible.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      leading: PlayerArt(
                        repo: repo,
                        player: p,
                        width: 42,
                        height: 46,
                        radius: 10,
                      ),
                      title: Text(
                        '${p['name']}',
                        style: typeBodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${p['role']}',
                        style: typeSecondary,
                      ),
                      trailing: Icon(
                        playerId == p['id']
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        size: 17,
                        color: playerId == p['id'] ? positive : faint,
                      ),
                      onTap: () => Navigator.pop(ctx, p['id']),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (id != null && mounted) {
      setState(() => playerId = id);
      await loadSlots();
    }
  }

  void resetReviewScroll() {
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  Future<void> next() async {
    if (!form.currentState!.validate()) return;
    if (playerId == null || selectedSlot == null) {
      setState(() => failure = '请选择队友和一个可约时段。');
      return;
    }
    if (!isFutureSlot(selectedSlot!)) {
      await loadSlots();
      if (mounted) setState(() => failure = '该时段已过期，请重新选择。');
      return;
    }
    setState(() {
      reviewing = true;
      failure = null;
    });
    resetReviewScroll();
  }

  Future<void> submit() async {
    if (repo.isProduction && repo.token == null) {
      await requireClubLogin(context, repo);
      return;
    }
    if (!accepted) {
      setState(() => failure = '请先阅读并同意预约说明');
      return;
    }
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final latest = await repo.getAvailability(
        playerId!,
        day,
        service!['durationMinutes'],
      );
      if (!latest.any(
        (s) =>
            s['startAt'] == selectedSlot!['startAt'] &&
            s['available'] == true &&
            isFutureSlot(s),
      )) {
        throw Exception('该时段已不可约，请返回重新选择。');
      }
      final o = await repo.book(
        service: service!,
        variantId: variantId,
        player: repo.findPlayer(playerId),
        date: DateTime.parse(selectedSlot!['startAt']),
        contact: contact.text.trim(),
        note: note.text.trim(),
        idempotencyKey: requestId,
      );
      if (mounted) context.go('/orders/${o['id']}');
    } catch (e) {
      if (mounted) {
        setState(() => failure = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _stepStrip(bool apple) => Row(
    children: [
      for (final step in const [
        (1, '选择队友与时间'),
        (2, '核对信息'),
      ])
        Expanded(
          child: Row(
            children: [
              Container(
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (reviewing ? step.$1 == 2 : step.$1 == 1)
                      ? ink
                      : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: rule, width: .6),
                ),
                child: Text(
                  '${step.$1}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: (reviewing ? step.$1 == 2 : step.$1 == 1)
                        ? Colors.white
                        : muted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  step.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typeCaption.copyWith(
                    color: (reviewing ? step.$1 == 2 : step.$1 == 1)
                        ? ink
                        : faint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (step.$1 == 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    CupertinoIcons.chevron_forward,
                    size: 11,
                    color: faint,
                  ),
                ),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final s = service;
    if (s == null) {
      return ClubPage(
        repo: repo,
        title: '确认预约',
        child: const EmptyState('服务暂不可用', '请选择其他服务。'),
      );
    }
    final p = repo.findPlayer(playerId),
        now = repo.now.toUtc().add(const Duration(hours: 8));
    return PopScope(
      canPop: !reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && reviewing) setState(() => reviewing = false);
      },
      child: ClubPage(
        repo: repo,
        onBack: reviewing ? () => setState(() => reviewing = false) : null,
        title: reviewing ? '核对这次预约' : '选择队友与时间',
        bottom: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¥${money(s)}',
                    style: typePrice,
                  ),
                  Text(
                    reviewing ? '确认后提交预约' : '合计 · 示例价格',
                    style: typeCaption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed:
                    busy ||
                        repo.operatingUnavailable != null ||
                        (s['teamSize'] as num? ?? 1) > 1
                    ? null
                    : reviewing
                    ? submit
                    : next,
                child: Text(
                  busy
                      ? '正在提交…'
                      : reviewing
                      ? '提交预约'
                      : '核对预约',
                ),
              ),
            ),
          ],
        ),
        child: Form(
          key: form,
          child: PageList(
            key: ValueKey(reviewing),
            controller: scroll,
            children: [
              _stepStrip(appleChrome(context)),
              const SizedBox(height: 12),
              Surface(
                border: true,
                padding: const EdgeInsets.all(11),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      height: 76,
                      child: ServiceArt(s, radius: 11),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typeBodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${s['durationMinutes']} 分钟 · ${s['gameMode'] ?? s['game']}',
                            style: typeSecondary,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Tag('${s['game']}', fill: sage, color: muted),
                              const SizedBox(width: 5),
                              if (p != null)
                                Text(
                                  '陪练 ${p['name']}',
                                  style: typeCaption,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              if (!reviewing) ...[
                if (serviceVariants(baseService!).isNotEmpty) ...[
                  const SectionTitle('服务规格'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: serviceVariants(baseService!)
                        .map(
                          (v) => ChoiceChip(
                            selected: variantId == v['id'],
                            label: Text('${v['title']} · ¥${money(v)}'),
                            onSelected: busy
                                ? null
                                : (_) {
                                    setState(() {
                                      variantId = v['id'];
                                      selectedSlot = null;
                                    });
                                    if (playerId != null) loadSlots();
                                  },
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SectionTitle('选择陪练'),
                InkWell(
                  onTap: choosePlayer,
                  borderRadius: BorderRadius.circular(14),
                  child: Surface(
                    border: true,
                    padding: const EdgeInsets.all(11),
                    child: Row(
                      children: [
                        if (p != null)
                          PlayerArt(
                            repo: repo,
                            player: p,
                            width: 42,
                            height: 46,
                            radius: 10,
                          )
                        else
                          const Icon(
                            Icons.person_search_outlined,
                            size: 30,
                            color: faint,
                          ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p == null ? '选择意向队友' : '${p['name']}',
                                style: typeBodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                p == null ? '查看擅长游戏与可约档期' : '${p['role']}',
                                style: typeSecondary,
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_down,
                          size: 14,
                          color: faint,
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('预约日期'),
                SizedBox(
                  height: 66,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final d = DateTime(now.year, now.month, now.day + i);
                      final picked =
                          d.year == day.year &&
                          d.month == day.month &&
                          d.day == day.day;
                      return InkWell(
                        onTap: () {
                          setState(() => day = d);
                          if (playerId != null) loadSlots();
                        },
                        borderRadius: BorderRadius.circular(11),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 74,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: picked ? ink : Colors.white,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: picked ? ink : rule,
                              width: .6,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                i == 0
                                    ? '今天'
                                    : i == 1
                                    ? '明天'
                                    : [
                                        '周一',
                                        '周二',
                                        '周三',
                                        '周四',
                                        '周五',
                                        '周六',
                                        '周日',
                                      ][d.weekday - 1],
                                style: TextStyle(
                                  color: picked ? Colors.white70 : muted,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${d.month}/${d.day}',
                                style: TextStyle(
                                  color: picked ? Colors.white : ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SectionTitle('可约时段', caption: '北京时间 · 按所选规格计算'),
                if (playerId == null)
                  const Text(
                    '先选一位队友，即可查看对应排班。',
                    style: typeSecondary,
                  )
                else if (checking)
                  const ClubSkeleton(kind: SkeletonKind.slots)
                else if (slotFailure != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(slotFailure!, style: typeSecondary),
                      ),
                      TextButton(
                        onPressed: loadSlots,
                        child: const Text('重新加载'),
                      ),
                    ],
                  )
                else if (slots?.isEmpty ?? false)
                  const Text(
                    '这一天暂无可约时段，试试其他日期或队友。',
                    style: typeSecondary,
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: (slots ?? []).map((slot) {
                      final picked =
                              selectedSlot?['startAt'] == slot['startAt'],
                          available = slot['available'] == true;
                      return SizedBox(
                        width: 78,
                        child: OutlinedButton(
                          onPressed: available
                              ? () => setState(() => selectedSlot = slot)
                              : null,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: picked ? ink : Colors.white,
                            foregroundColor: picked ? Colors.white : ink,
                            side: BorderSide(color: picked ? ink : rule),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: const Size(0, 46),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                when(slot['startAt'], onlyTime: true),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: picked
                                      ? Colors.white
                                      : available
                                      ? ink
                                      : muted,
                                ),
                              ),
                              if (!available)
                                const Text(
                                  '已占用',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SectionTitle('联系信息', caption: '仅用于本次演示预约核对'),
                TextFormField(
                  controller: contact,
                  maxLength: 64,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: '联系方式',
                    hintText: '微信号或手机号',
                    counterText: '',
                  ),
                  validator: (v) => v == null || v.trim().length < 3
                      ? '请填写至少 3 个字符的联系方式'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: note,
                  maxLength: 200,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: '预约备注（选填）',
                    hintText: '例如区服、沟通偏好、想练习的配合',
                    counterText: '',
                  ),
                ),
              ] else ...[
                const SectionTitle('预约信息'),
                Surface(
                  border: true,
                  child: Column(
                    children: [
                      PairRow('意向队友', '${p?['name']}', strong: true),
                      PairRow(
                        '预约时间',
                        when(selectedSlot!['startAt']),
                        strong: true,
                      ),
                      PairRow('服务时长', '${s['durationMinutes']} 分钟'),
                      PairRow('联系方式', contact.text.trim()),
                      PairRow(
                        '预约备注',
                        note.text.trim().isEmpty ? '未填写' : note.text.trim(),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 3),
                        child: Divider(height: .5, thickness: .5),
                      ),
                      PairRow('合计', '¥${money(s)}', strong: true),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => reviewing = false),
                  icon: const Icon(CupertinoIcons.pencil, size: 14),
                  label: const Text('修改预约安排'),
                ),
                if (!repo.isProduction)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.info_circle,
                          size: 13,
                          color: faint,
                        ),
                        const SizedBox(width: 5),
                        Text('预览预约，不收取费用。', style: typeCaption),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                GroupCard(
                  children: [
                    CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      value: accepted,
                      onChanged: (v) => setState(() => accepted = v ?? false),
                      title: Text(
                        repo.isProduction ? '同意微信登录、服务协议与隐私政策' : '同意服务协议与隐私政策',
                        style: typeSecondary.copyWith(height: 1.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () => textSheet(
                        context,
                        '预约说明与隐私',
                        '${repo.club['termsText'] ?? ''}\n\n${repo.club['privacyText'] ?? ''}\n\n客服：${repo.club['supportContact'] ?? ''}',
                      ),
                      child: const Text('阅读服务、退款与隐私说明'),
                    ),
                  ],
                ),
              ],
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          failure!,
                          style: const TextStyle(
                            color: danger,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (repo.operatingUnavailable != null)
                Text(
                  repo.operatingUnavailable!,
                  style: typeSecondary.copyWith(color: danger),
                ),
              DemoStamp(repo),
            ],
          ),
        ),
      ),
    );
  }
}
