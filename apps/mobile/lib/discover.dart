import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoSlidingSegmentedControl;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'repository.dart';
import 'ui.dart';

String priceUnit(Json s) => s['billingUnit'] == 'hour'
    ? (s['durationMinutes'] == 60 ? '小时' : '套餐')
    : const {'session': '场', 'target': '单'}[s['billingUnit']] ?? '场';
String serviceKind(Json s) =>
    const {
      'hourly': '小时陪练',
      'escort': '护航',
      'review': '对局复盘',
    }[s['serviceType']] ??
    '${s['category'] ?? ''}';
List<String> serviceFacts(Json s) => [
  if (s['platform'] != null) s['platform'] == 'mobile' ? '手游' : '端游',
  if ('${s['gameMode'] ?? ''}'.isNotEmpty) '${s['gameMode']}',
  if (s['teamSize'] != null) '${s['teamSize']} 位陪练',
];

class HomePage extends StatefulWidget {
  const HomePage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? selectedGame;
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final active = repo.orders
        .where((o) => !['completed', 'cancelled'].contains(stage(o)))
        .firstOrNull;
    final games = repo.services.map((s) => '${s['game']}').toSet().toList();
    selectedGame ??= games.firstOrNull;
    final services = repo.services
        .where((s) => s['game'] == selectedGame)
        .toList();
    final players = repo.players
        .where((p) => (p['games'] as List).contains(selectedGame))
        .toList();
    final player = active == null
        ? null
        : repo.findPlayer(active['assignedPlayerId'] ?? active['playerId']);
    return ClubPage(
      repo: repo,
      tab: 0,
      appBar: false,
      child: PageList(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        children: [
          Row(
            children: [
              BrandMark(repo, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  repo.clubName,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.4,
                  ),
                ),
              ),
              if (!repo.isProduction) const DemoMarker(),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '通知',
                onPressed: () => context.push('/notifications'),
                icon: const Icon(Icons.notifications_none_rounded, size: 23),
              ),
            ],
          ),
          const SizedBox(height: 19),
          if (active != null) ...[
            InkWell(
              onTap: () => context.push('/orders/${active['id']}'),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.timelapse_rounded,
                                size: 16,
                                color: Color(0xFFC5CBD6),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                stageName(stage(active)),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFC5CBD6),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            '${active['serviceTitle']}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            '${when(active['scheduledAt'], onlyTime: true)}  ·  ${player?['name'] ?? '等待安排'}',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFFC5CBD6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.arrow_outward_rounded,
                      color: Colors.white,
                      size: 23,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          InkWell(
            onTap: () => context.go('/services'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, size: 22, color: muted),
                  SizedBox(width: 10),
                  Text('搜索服务或陪练', style: TextStyle(fontSize: 16, color: muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (games.length > 1 && appleChrome(context))
            CupertinoSlidingSegmentedControl<String>(
              groupValue: selectedGame,
              backgroundColor: const Color(0xFFE7EAF0),
              thumbColor: Colors.white,
              padding: const EdgeInsets.all(3),
              children: {
                for (final game in games.take(3))
                  game: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 2,
                    ),
                    child: Text(
                      game,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 14,
                        fontWeight: game == selectedGame
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: ink,
                      ),
                    ),
                  ),
              },
              onValueChanged: (value) {
                if (value != null) setState(() => selectedGame = value);
              },
            ),
          if (games.length > 1 && !appleChrome(context))
            SegmentedButton<String>(
              segments: games
                  .take(3)
                  .map(
                    (game) => ButtonSegment(
                      value: game,
                      label: Text(game, style: const TextStyle(fontSize: 14)),
                    ),
                  )
                  .toList(),
              selected: {selectedGame!},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => selectedGame = value.first),
            ),
          const SizedBox(height: 9),
          SectionTitle(
            '服务',
            action: '全部',
            onTap: () => context.go(
              '/services?game=${Uri.encodeComponent(selectedGame ?? '全部')}',
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final item in services.take(2).indexed) ...[
                  if (item.$1 > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 1),
                    ),
                  ServiceFeature(repo: repo, service: item.$2, embedded: true),
                ],
              ],
            ),
          ),
          const SizedBox(height: 9),
          SectionTitle(
            '陪练',
            action: '全部',
            onTap: () => context.push('/players'),
          ),
          ...players.take(3).map((p) => RosterRow(repo: repo, player: p)),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('俱乐部公告'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/announcements'),
          ),
        ],
      ),
    );
  }
}

class ServiceFeature extends StatelessWidget {
  const ServiceFeature({
    super.key,
    required this.repo,
    required this.service,
    this.embedded = false,
  });
  final ClubRepository repo;
  final Json service;
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final variants = serviceVariants(service);
    final lowest = variants.isEmpty
        ? service
        : variants.reduce((a, b) => a['priceCents'] < b['priceCents'] ? a : b);
    final quote = {...service, ...lowest};
    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 66,
            child: ServiceArt(service, radius: 10),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${service['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${quote['durationMinutes']} 分钟 · ${serviceKind(quote)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '¥${money(quote)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                variants.length > 1 ? '起' : '/${priceUnit(quote)}',
                style: const TextStyle(fontSize: 13, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
    return InkWell(
      onTap: () => context.push('/services/${service['id']}'),
      borderRadius: BorderRadius.circular(16),
      child: embedded
          ? body
          : Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: body,
            ),
    );
  }
}

/// Original game-neutral contour geometry, not game art or a real map.
class ServiceArt extends StatelessWidget {
  const ServiceArt(this.service, {super.key, this.radius = 14});
  final Json service;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = '${service['coverUrl'] ?? ''}';
    final fallback = CustomPaint(
      painter: _ContourArt(service['serviceType'] == 'review'),
      child: const SizedBox.expand(),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.startsWith('https://')
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback,
    );
  }
}

class _ContourArt extends CustomPainter {
  const _ContourArt(this.review);
  final bool review;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = review ? const Color(0xFFE6EAF1) : const Color(0xFFDEE4ED),
    );
    final center = Offset(size.width * .67, size.height * .5);
    final unit = math.max(size.width, size.height);
    final line = Paint()
      ..color = const Color(0xFFAFBAC9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .65;
    for (var i = 0; i < 15; i++) {
      final path = Path();
      final radius = unit * (.08 + i * .039);
      for (var j = 0; j <= 90; j++) {
        final angle = j / 90 * math.pi * 2;
        final wave =
            1 +
            .15 * math.sin(angle * 3 + (review ? 1.4 : .4)) +
            .07 * math.cos(angle * 5);
        final point =
            center +
            Offset(
              math.cos(angle) * radius * wave,
              math.sin(angle) * radius * wave * .74,
            );
        if (j == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, line);
    }
    final route = Path()
      ..moveTo(size.width * -.08, size.height * .84)
      ..cubicTo(
        size.width * .26,
        size.height * .84,
        size.width * .35,
        size.height * .23,
        size.width * .71,
        size.height * .33,
      )
      ..quadraticBezierTo(
        size.width * .85,
        size.height * .4,
        size.width * 1.08,
        size.height * .12,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF5A6A82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    canvas.drawCircle(
      Offset(size.width * .7, size.height * .33),
      3,
      Paint()..color = const Color(0xFF273347),
    );
    canvas.drawCircle(
      Offset(size.width * .7, size.height * .33),
      6,
      Paint()
        ..color = const Color(0xFF273347).withValues(alpha: .2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
  }

  @override
  bool shouldRepaint(_ContourArt old) => old.review != review;
}

class RosterRow extends StatelessWidget {
  const RosterRow({super.key, required this.repo, required this.player});
  final ClubRepository repo;
  final Json player;
  @override
  Widget build(BuildContext context) {
    final prices =
        repo.services
            .where((s) => (player['games'] as List).contains(s['game']))
            .expand(
              (s) => serviceVariants(s).isEmpty ? [s] : serviceVariants(s),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['priceCents'] as int).compareTo(b['priceCents'] as int),
          );
    return InkWell(
      onTap: () => context.push('/players/${player['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlayerArt(
              repo: repo,
              player: player,
              width: 88,
              height: 104,
              radius: 16,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${player['name']}',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: muted,
                        size: 20,
                      ),
                    ],
                  ),
                  Text(
                    '${player['role']}',
                    style: const TextStyle(fontSize: 15, color: muted),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    (player['tags'] as List? ?? []).take(2).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (prices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '¥${money(prices.first)} 起',
                        style: TextStyle(
                          fontSize: 17,
                          color: brandColor(repo),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.repo, required this.player});
  final ClubRepository repo;
  final Json player;
  @override
  Widget build(BuildContext context) => RosterRow(repo: repo, player: player);
}

class ServicesPage extends StatefulWidget {
  const ServicesPage(this.repo, {super.key, this.initialGame = '全部'});
  final ClubRepository repo;
  final String initialGame;
  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  late String game = widget.initialGame;
  String query = '';
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final items = repo.services
        .where(
          (s) =>
              (game == '全部' || s['game'] == game) &&
              '${s['title']} ${s['game']} ${s['description']}'.contains(query),
        )
        .toList();
    return ClubPage(
      repo: repo,
      title: '找服务',
      tab: 1,
      child: PageList(
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '搜索游戏或服务',
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  ['全部', ...repo.services.map((s) => '${s['game']}').toSet()]
                      .map(
                        (v) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: game == v,
                            label: Text(
                              v,
                              style: const TextStyle(fontSize: 15),
                            ),
                            onSelected: (_) => setState(() => game = v),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 20),
          if (items.isEmpty) const EmptyState('没有匹配的服务', '试试其他游戏或关键词。'),
          ...items.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ServiceFeature(repo: repo, service: s),
            ),
          ),
        ],
      ),
    );
  }
}

class ServicePage extends StatefulWidget {
  const ServicePage(this.repo, this.id, {super.key, this.initialVariant});
  final ClubRepository repo;
  final String id;
  final String? initialVariant;
  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  String? variantId;
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo, service = widget.repo.findService(widget.id);
    if (service == null) {
      return ClubPage(
        repo: repo,
        title: '服务详情',
        child: const EmptyState('服务暂不可用', '请选择其他服务。'),
      );
    }
    final variants = serviceVariants(service);
    variantId ??= widget.initialVariant ?? variants.firstOrNull?['id'];
    final s = selectedService(service, variantId);
    final players = repo.players
        .where((p) => (p['games'] as List).contains(s['game']))
        .toList();
    final inclusions = s['inclusions'] as List? ?? [],
        rules = s['rules'] as List? ?? [],
        requirements = s['requirements'] as List? ?? [];
    final multiple = (s['teamSize'] as num? ?? 1) > 1;
    return ClubPage(
      repo: repo,
      title: '服务详情',
      bottom: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'NotoSansSC',
                      color: ink,
                    ),
                    children: [
                      TextSpan(
                        text: '¥${money(s)}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '/${priceUnit(s)}',
                        style: const TextStyle(fontSize: 14, color: muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${s['durationMinutes']} 分钟',
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: FilledButton(
              onPressed: multiple
                  ? null
                  : () => context.push(
                      '/book?service=${service['id']}${variantId == null ? '' : '&variant=$variantId'}',
                    ),
              child: Text(multiple ? '暂不支持多人单' : '立即预约'),
            ),
          ),
        ],
      ),
      child: PageList(
        children: [
          SizedBox(height: 122, child: ServiceArt(service, radius: 20)),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '${s['game']}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: brandColor(repo),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                serviceKind(s),
                style: const TextStyle(fontSize: 15, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${s['title']}',
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w600,
              letterSpacing: -.4,
            ),
          ),
          if (variants.isNotEmpty) ...[
            const SizedBox(height: 19),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: variants
                  .map(
                    (v) => ChoiceChip(
                      label: Text(
                        '${v['title']}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      selected: variantId == v['id'],
                      onSelected: (_) => setState(() => variantId = v['id']),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (serviceFacts(s).isNotEmpty) ...[
            const SizedBox(height: 15),
            Text(
              serviceFacts(s).join('   ·   '),
              style: const TextStyle(fontSize: 16),
            ),
          ],
          if ((s['maps'] as List? ?? []).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '地图  ${(s['maps'] as List).join(' / ')}',
                style: const TextStyle(fontSize: 16, color: muted),
              ),
            ),
          if ('${s['description'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                '${s['description']}',
                style: const TextStyle(fontSize: 16, color: muted, height: 1.6),
              ),
            ),
          if (inclusions.isNotEmpty) ...[
            const Divider(),
            const Text(
              '服务内容',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            ...inclusions.map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 21,
                      color: brandColor(repo),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('$v', style: const TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SectionTitle('可选陪练'),
          ...players.take(2).map((p) => MemberRow(repo: repo, player: p)),
          if (rules.isNotEmpty || requirements.isNotEmpty) ...[
            const Divider(),
            const Text(
              '下单须知',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...[...rules, ...requirements].map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '$v',
                  style: const TextStyle(fontSize: 16, color: muted),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.repo,
    required this.player,
    this.trailing,
  });
  final ClubRepository repo;
  final Json player;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/players/${player['id']}'),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          PlayerArt(
            repo: repo,
            player: player,
            width: 56,
            height: 64,
            radius: 12,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player['name']}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${player['role']}',
                  style: const TextStyle(fontSize: 15, color: muted),
                ),
              ],
            ),
          ),
          trailing ??
              const Icon(Icons.chevron_right_rounded, size: 22, color: muted),
        ],
      ),
    ),
  );
}

class PlayersPage extends StatelessWidget {
  const PlayersPage(this.repo, {super.key});
  final ClubRepository repo;
  @override
  Widget build(BuildContext context) => ClubPage(
    repo: repo,
    title: '俱乐部陪练',
    child: PageList(
      children: repo.players
          .map((p) => RosterRow(repo: repo, player: p))
          .toList(),
    ),
  );
}

class PlayerPage extends StatefulWidget {
  const PlayerPage(this.repo, this.id, {super.key});
  final ClubRepository repo;
  final String id;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  List<Json>? slots;
  String? failure;
  @override
  void initState() {
    super.initState();
    loadSlots();
  }

  Future<void> loadSlots() async {
    try {
      final today = widget.repo.now.toUtc().add(const Duration(hours: 8));
      final value = await widget.repo.getAvailability(
        widget.id,
        DateTime(today.year, today.month, today.day + 1),
        60,
      );
      if (mounted) {
        setState(() {
          slots = value;
          failure = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo, p = widget.repo.findPlayer(widget.id);
    if (p == null) {
      return ClubPage(
        repo: repo,
        title: '陪练主页',
        child: const EmptyState('未找到这位陪练', '请返回陪练目录。'),
      );
    }
    final services = repo.services
        .where((s) => (p['games'] as List).contains(s['game']))
        .toList();
    final prices =
        services
            .expand(
              (s) => serviceVariants(s).isEmpty ? [s] : serviceVariants(s),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['priceCents'] as int).compareTo(b['priceCents'] as int),
          );
    final available = slots?.where((s) => s['available'] == true).toList();
    return ClubPage(
      repo: repo,
      title: '陪练主页',
      actions: [
        IconButton(
          tooltip: repo.following.contains(widget.id) ? '取消关注' : '关注陪练',
          onPressed: () => repo.toggleFollow(widget.id),
          icon: Icon(
            repo.following.contains(widget.id)
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            size: 21,
          ),
        ),
      ],
      bottom: Row(
        children: [
          if (prices.isNotEmpty)
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: 'NotoSansSC', color: ink),
                  children: [
                    TextSpan(
                      text: '¥${money(prices.first)}',
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text: ' 起',
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: FilledButton(
              onPressed: services.isEmpty
                  ? null
                  : () => context.push(
                      '/book?service=${services.first['id']}&player=${p['id']}',
                    ),
              child: const Text('预约 TA'),
            ),
          ),
        ],
      ),
      child: PageList(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8ECF2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['name']}',
                        style: const TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.4,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${p['role']}',
                        style: const TextStyle(fontSize: 16, color: muted),
                      ),
                      const SizedBox(height: 23),
                      Text(
                        (p['games'] as List).join(' / '),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                PlayerArt(
                  repo: repo,
                  player: p,
                  width: 120,
                  height: 146,
                  radius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (p['tags'] as List? ?? [])
                .map((v) => Tag('$v', fill: Colors.white, color: ink))
                .toList(),
          ),
          const SizedBox(height: 15),
          Text(
            '${p['bio']}',
            style: const TextStyle(fontSize: 16, height: 1.65, color: muted),
          ),
          const SizedBox(height: 10),
          SectionTitle('服务'),
          ...services.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ServiceFeature(repo: repo, service: s),
            ),
          ),
          const SizedBox(height: 5),
          SectionTitle('明日可约'),
          if (failure != null)
            TextButton(onPressed: loadSlots, child: const Text('排班加载失败，重试'))
          else if (slots == null)
            const LinearProgressIndicator()
          else if (available!.isEmpty)
            const Text('暂无时段', style: TextStyle(fontSize: 16, color: muted))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: available
                  .take(4)
                  .map(
                    (s) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        when(s['startAt'], onlyTime: true),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
