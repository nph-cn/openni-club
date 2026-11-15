import 'package:material_ui/material_ui.dart';

import 'repository.dart';
import 'ui.dart';

/// 打手分级说明页。分级规则来自俱乐部配置；没有配置时不编造等级。
class TiersPage extends StatelessWidget {
  const TiersPage(this.repo, {super.key});
  final ClubRepository repo;

  Color _tierColor(Json tier) =>
      colorFromHex('${tier['color']}', fallback: warning);

  @override
  Widget build(BuildContext context) {
    final tiers = repo.tiers;
    final member = repo.role == 'member' ? repo.playerById(repo.memberPlayerId) : null;
    final myTier = member == null ? null : repo.tierFor(member);
    return ClubPage(
      repo: repo,
      title: '打手分级',
      child: PageList(
        children: [
          Surface(
            color: ink,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.military_tech_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '分级 × 认证 × 派单',
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '按真实接单、评分与培训记录评定',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: .6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final tier in tiers) ...[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TierBadge(tier: tier, compact: true),
                            const SizedBox(height: 5),
                            Text(
                              '${repo.players.where((p) => p['tier'] == tier['id']).length} 位成员',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.white.withValues(alpha: .55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (tier != tiers.last)
                        Container(
                          width: .5,
                          height: 30,
                          color: Colors.white.withValues(alpha: .12),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (member != null && myTier != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Surface(
                border: true,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    PlayerArt(
                      repo: repo,
                      player: member,
                      width: 46,
                      height: 54,
                      radius: 12,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '我的分级 · ${member['name']}',
                            style: typeLabel.copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              TierBadge(tier: myTier, showLevel: true),
                              const SizedBox(width: 6),
                              if (member['certified'] == true)
                                const Tag(
                                  '已认证',
                                  color: positive,
                                  fill: Color(0xFFE7F2EC),
                                  icon: Icons.verified_rounded,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${member['completedOrders'] ?? 0}', style: typeNumber),
                        Text('完成单量', style: typeCaption),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SectionTitle('分级标准', caption: '示例俱乐部规则，实际以运营配置为准'),
          for (final tier in tiers)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Surface(
                border: true,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _tierColor(tier),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  TierBadge(tier: tier, showLevel: true),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      '${tier['label'] ?? ''}级打手',
                                      style: typeLabel.copyWith(fontSize: 13.5),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '接单 ≥ ${tier['minOrders'] ?? 0} · 评分 ≥ ${tier['minRating'] ?? '—'} · 分成 ${_percent(tier['commissionRate'])}',
                                style: typeCaption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if ((tier['perks'] as List? ?? []).isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final perk in tier['perks'] as List)
                            Tag('$perk', fill: sage, color: muted),
                        ],
                      ),
                    ],
                    if (repo.players.where((p) => p['tier'] == tier['id']).isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          for (final player in repo.players
                              .where((p) => p['tier'] == tier['id'])
                              .take(5))
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: PlayerArt(
                                repo: repo,
                                player: player,
                                width: 28,
                                height: 28,
                                radius: 8,
                              ),
                            ),
                          const SizedBox(width: 2),
                          Text(
                            repo.players
                                .where((p) => p['tier'] == tier['id'])
                                .map((p) => '${p['name']}')
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typeCaption,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SectionTitle('如何认证', caption: '示例流程'),
          Surface(
            border: true,
            child: Column(
              children: [
                _Step(
                  index: 1,
                  title: '提交资料与擅长游戏',
                  body: '成员在俱乐部工作台提交游戏账号截图、擅长位置与可接时段；不收集账号密码。',
                ),
                _Step(
                  index: 2,
                  title: '完成培训与实战考核',
                  body: '由已认证成员或教练完成一次实战考核，记录沟通、协作与交付表现。',
                ),
                _Step(
                  index: 3,
                  title: '按阶段评定分级',
                  body: '按完成单量、客户评分与考核结果更新分级；降级与申诉规则由运营配置。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '分级、认证与分成均为示例数据，实际规则需由俱乐部运营在后台配置。真实运营中不展示未经核实的分级或评分。',
            style: typeCaption.copyWith(height: 1.5),
          ),
          DemoStamp(repo),
        ],
      ),
    );
  }

  String _percent(dynamic value) {
    final text = '${value ?? ''}';
    final parsed = double.tryParse(text);
    if (parsed == null) return '—';
    return '${(parsed * 100).round()}%';
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.title, required this.body});
  final int index;
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: ink, shape: BoxShape.circle),
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: typeLabel.copyWith(fontSize: 13)),
              const SizedBox(height: 2),
              Text(body, style: typeSecondary.copyWith(height: 1.5)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 俱乐部能力 / 可开通模块。展示俱乐部真实配置状态，未开通的显示为示例。
class ClubFeaturesPage extends StatelessWidget {
  const ClubFeaturesPage(this.repo, {super.key});
  final ClubRepository repo;

  @override
  Widget build(BuildContext context) {
    final features = repo.clubFeatures;
    final enabled = features.where((f) => f['enabled'] == true).length;
    final categories = <String>[];
    for (final feature in features) {
      final category = '${feature['category'] ?? '其他'}';
      if (!categories.contains(category)) categories.add(category);
    }
    return ClubPage(
      repo: repo,
      title: '俱乐部能力',
      child: PageList(
        children: [
          Surface(
            color: const Color(0xFF232A33),
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '可开通能力',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: .55),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '按俱乐部阶段逐步开通',
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '$enabled',
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/ ${features.length} 项已开通',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: .55),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '示例配置',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final category in categories) ...[
            SectionTitle(category),
            for (final feature in features.where(
              (f) => '${f['category']}' == category,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _FeatureRow(feature: feature),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            '能力开通由俱乐部运营在后台配置；当前为演示快照，切换开关不会产生真实计费或服务变更。',
            style: typeCaption.copyWith(height: 1.5),
          ),
          DemoStamp(repo),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});
  final Json feature;
  @override
  Widget build(BuildContext context) {
    final on = feature['enabled'] == true;
    return Surface(
      border: true,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: on ? const Color(0xFFE7F2EC) : sage,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              on ? Icons.check_rounded : Icons.lock_outline_rounded,
              size: 16,
              color: on ? positive : faint,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${feature['title']}',
                        style: typeLabel.copyWith(fontSize: 13.5),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: on ? const Color(0xFFE7F2EC) : sage,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        on ? '已开通' : '可开通',
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: on ? positive : muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${feature['description'] ?? ''}',
                  style: typeSecondary.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
