import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'repository.dart';
import 'discover.dart' show ServiceArt;
import 'ui.dart';

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
  String? failure;
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
    day = DateTime(now.year, now.month, now.day + 1);
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
    if (!mounted || slots == null || slots!.isEmpty) return;
    setState(() {
      selectedSlot = slots!.firstWhere((s) => s['available'] == true);
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
      if (mounted && revision == fetchId) setState(() => slots = result);
    } catch (e) {
      if (mounted && revision == fetchId) {
        setState(() => failure = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && revision == fetchId) setState(() => checking = false);
    }
  }

  Future<void> choosePlayer() async {
    final id = await showClubSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: canvas,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择意向队友',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '俱乐部会核对档期。最终服务队友以订单安排为准。',
                style: TextStyle(fontSize: 14, color: muted),
              ),
              const SizedBox(height: 18),
              ...eligible.map(
                (p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PlayerArt(
                    repo: repo,
                    player: p,
                    width: 48,
                    height: 54,
                  ),
                  title: Text('${p['name']}'),
                  subtitle: Text('${p['role']}'),
                  trailing: Icon(
                    playerId == p['id']
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color: playerId == p['id'] ? forest : muted,
                  ),
                  onTap: () => Navigator.pop(ctx, p['id']),
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
    setState(() {
      reviewing = true;
      failure = null;
    });
    resetReviewScroll();
  }

  Future<void> submit() async {
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
            s['startAt'] == selectedSlot!['startAt'] && s['available'] == true,
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
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '合计',
                    style: const TextStyle(fontSize: 15, color: muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FilledButton(
                onPressed:
                    busy ||
                        repo.authenticationUnavailable != null ||
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
              Row(
                children: [
                  SizedBox(
                    width: 78,
                    height: 86,
                    child: ServiceArt(s, radius: 12),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s['title']}',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${s['durationMinutes']} 分钟 · ${s['gameMode'] ?? s['game']}',
                          style: const TextStyle(fontSize: 14, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(),
              if (!reviewing) ...[
                if (serviceVariants(baseService!).isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                  const SizedBox(height: 20),
                ],
                const Text(
                  '选择陪练',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: choosePlayer,
                  borderRadius: BorderRadius.circular(14),
                  child: Surface(
                    border: true,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        if (p != null)
                          PlayerArt(
                            repo: repo,
                            player: p,
                            width: 46,
                            height: 50,
                          )
                        else
                          const Icon(
                            Icons.person_search_outlined,
                            size: 36,
                            color: muted,
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p == null ? '选择意向队友' : '${p['name']}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                p == null ? '查看擅长游戏与可约档期' : '${p['role']}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.expand_more_rounded, size: 22),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('预约日期'),
                SizedBox(
                  height: 82,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final d = DateTime(now.year, now.month, now.day + i + 1);
                      final picked =
                          d.year == day.year &&
                          d.month == day.month &&
                          d.day == day.day;
                      return InkWell(
                        onTap: () {
                          setState(() => day = d);
                          if (playerId != null) loadSlots();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 96,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: picked ? ink : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: picked ? ink : rule),
                          ),
                          child: Column(
                            children: [
                              Text(
                                i == 0
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
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${d.month}/${d.day}',
                                style: TextStyle(
                                  color: picked ? Colors.white : ink,
                                  fontSize: 17,
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
                const SectionTitle('可约时段', caption: '北京时间'),
                if (playerId == null)
                  const Text(
                    '先选一位队友，即可查看对应排班。',
                    style: TextStyle(color: muted, fontSize: 15),
                  )
                else if (checking)
                  const LinearProgressIndicator()
                else if (slots?.isEmpty ?? false)
                  const Text(
                    '这一天暂无可约时段，试试其他日期或队友。',
                    style: TextStyle(color: muted, fontSize: 15),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (slots ?? []).map((slot) {
                      final picked =
                              selectedSlot?['startAt'] == slot['startAt'],
                          available = slot['available'] == true;
                      return SizedBox(
                        width: 102,
                        child: OutlinedButton(
                          onPressed: available
                              ? () => setState(() => selectedSlot = slot)
                              : null,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: picked ? sage : Colors.white,
                            side: BorderSide(color: picked ? forest : rule),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                when(slot['startAt'], onlyTime: true),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: picked
                                      ? forest
                                      : available
                                      ? ink
                                      : muted,
                                ),
                              ),
                              if (!available)
                                const Text(
                                  '已占用',
                                  style: TextStyle(fontSize: 14, color: muted),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SectionTitle('联系信息'),
                TextFormField(
                  controller: contact,
                  maxLength: 64,
                  decoration: InputDecoration(
                    labelText: '联系方式',
                    hintText: '微信号或手机号',
                  ),
                  validator: (v) => v == null || v.trim().length < 3
                      ? '请填写至少 3 个字符的联系方式'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: note,
                  maxLength: 200,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '预约备注（选填）',
                    hintText: '例如区服、沟通偏好、想练习的配合',
                  ),
                ),
              ] else ...[
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
                      const Divider(),
                      PairRow('合计', '¥${money(s)}', strong: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => setState(() => reviewing = false),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('修改预约安排'),
                ),
                if (!repo.isProduction)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '预览预约，不收取费用。',
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: accepted,
                  onChanged: (v) => setState(() => accepted = v ?? false),
                  title: Text(
                    repo.isProduction ? '同意微信登录、服务协议与隐私政策' : '同意服务协议与隐私政策',
                    style: const TextStyle(
                      fontSize: 14,
                      color: muted,
                      height: 1.7,
                    ),
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
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    failure!,
                    style: const TextStyle(
                      color: Color(0xFF9F3227),
                      fontSize: 15,
                    ),
                  ),
                ),
              if (repo.authenticationUnavailable != null)
                Text(
                  repo.authenticationUnavailable!,
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
