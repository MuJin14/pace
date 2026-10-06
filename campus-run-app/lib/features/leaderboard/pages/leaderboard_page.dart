import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_metric_text.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/repositories/friend_repository.dart';
import '../../friends/providers/friend_provider.dart';
import '../providers/leaderboard_provider.dart';

/// 榜单周期：日榜 / 周榜 / 滚动 30 天榜 / 自然月榜。
const _scopes = [
  ('daily', '日榜'),
  ('weekly', '周榜'),
  ('rolling30d', '30天榜'),
  ('monthly', '月榜'),
];

/// 排行榜：维度/类型切换 + 个人排名 + 榜单列表。
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key});

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  String _scope = 'daily';
  int _type = 1;

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(leaderboardProvider((_scope, _type)));
    return Scaffold(
      appBar: AppBar(title: const Text('排行榜')),
      body: Column(
        children: [
          _ScopeBar(selected: _scope, onChanged: (s) => setState(() => _scope = s)),
          _TypeBar(selected: _type, onChanged: (t) => setState(() => _type = t)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(leaderboardProvider((_scope, _type)));
                await ref.read(leaderboardProvider((_scope, _type)).future);
              },
              child: listAsync.when(
                loading: () => const ScrollableCenter(child: CircularProgressIndicator()),
                error: (err, _) => ScrollableCenter(
                  child: ErrorState(
                    message: err is ApiException ? err.message : '加载失败，请稍后重试',
                    onRetry: () => ref.invalidate(leaderboardProvider((_scope, _type))),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return ScrollableCenter(
                      child: EmptyState(
                        icon: Icons.emoji_events,
                        title: '这个榜单还空着',
                        subtitle: '去跑一跑，抢占第一名的位置吧',
                        actionLabel: '去跑步',
                        onAction: () => context.push('/start-run'),
                      ),
                    );
                  }
                  return _buildList(list);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<LeaderboardEntry> list) {
    // 前三名单独做「领奖台」：单纯平铺罗列让人感觉不到竞争；
    // 把前三名放大 + 奖牌色，一眼就有「我要上榜」的欲望。
    final podium = list.take(3).toList();
    final rest = list.skip(3).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.lg,
      ),
      children: [
        _MyRankCard(scope: _scope, type: _type),
        const SizedBox(height: AppSpacing.lg),
        if (podium.isNotEmpty) ...[
          const AppSectionTitle(title: '领奖台'),
          const SizedBox(height: AppSpacing.smLg),
          _Podium(entries: podium),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (rest.isNotEmpty) ...[
          const AppSectionTitle(title: '榜单排行'),
          const SizedBox(height: AppSpacing.smLg),
          for (final entry in rest) ...[
            _RankItem(entry: entry),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
        if (podium.isNotEmpty && rest.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: Center(
              child: Text(
                '榜单上只有这几位，叫上同学一起来比',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 前三名领奖台：中间最高（第 1），左右次之。
class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    // 顺序摆成 2 / 1 / 3：视觉上冠军居中、台面最高，符合颁奖台直觉
    final order = <int>[1, 0, 2];
    final present = order.where((i) => i < entries.length).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final i in present) ...[
          Expanded(child: _PodiumSlot(entry: entries[i])),
          if (i != present.last) const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final isChampion = entry.rank == 1;
    final avatarSize = isChampion ? 62.0 : 50.0;
    final medal = _medalColor(entry.rank);
    // 台面高度体现名次差，冠军最高
    final blockHeight = switch (entry.rank) {
      1 => 52.0,
      2 => 38.0,
      _ => 30.0,
    };

    return GestureDetector(
      // 整块可点：进 TA 的主页
      onTap: () => context.push('/user/${entry.userId}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.isSelf)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.xxs),
              child: _SelfTag(),
            ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(
                nickname: entry.nickname,
                avatarUrl: entry.avatarUrl,
                size: avatarSize,
              ),
              if (isChampion)
                const Positioned(
                  top: -6,
                  right: -2,
                  child: Icon(Icons.workspace_premium,
                      size: 22, color: AppColors.medal),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            Formatters.distance(entry.distanceMeters),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isChampion ? AppFontSize.title : AppFontSize.body,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          // 与第 1 名的差距：让「离榜首多远」一眼可见
          if (!isChampion && entry.rank > 1)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                _gapToLeaderLabel(entry),
                style: const TextStyle(
                  fontSize: AppFontSize.tiny,
                  color: AppColors.textHint,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: blockHeight,
            decoration: BoxDecoration(
              color: (medal ?? AppColors.barEmpty).withValues(alpha: 0.22),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sm),
              ),
              border: Border(
                top: BorderSide(
                  color: medal ?? AppColors.borderLight,
                  width: 3,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontSize: AppFontSize.headline,
                fontWeight: FontWeight.bold,
                color: medal ?? AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelfTag extends StatelessWidget {
  const _SelfTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Text(
        '我',
        style: TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

/// 「距榜首 1.2 km」文案。没有可比数据时返回空串（由调用方决定不渲染）。
String _gapToLeaderLabel(LeaderboardEntry entry) {
  // 榜单里未必包含第 1 名（分页），此时用与上一名的差距兜底
  final gap = entry.gapToAheadMeters;
  if (gap == null) return '';
  return '距上一名 ${Formatters.distance(gap)}';
}

class _ScopeBar extends StatelessWidget {
  const _ScopeBar({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        itemCount: _scopes.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final scope = _scopes[i];
          return AppChip(
            label: scope.$2,
            selected: scope.$1 == selected,
            onTap: () => onChanged(scope.$1),
          );
        },
      ),
    );
  }
}

class _TypeBar extends StatelessWidget {
  const _TypeBar({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          _typeChip(1, Icons.directions_run, '跑步'),
          const SizedBox(width: AppSpacing.sm),
          _typeChip(2, Icons.directions_bike, '骑行'),
        ],
      ),
    );
  }

  Widget _typeChip(int value, IconData icon, String label) {
    return AppChip(
      label: label,
      icon: icon,
      selected: selected == value,
      onTap: () => onChanged(value),
    );
  }
}

/// 「我的排名」卡片：加载中 / 未上榜 / 出错可重试。
class _MyRankCard extends ConsumerWidget {
  const _MyRankCard({required this.scope, required this.type});

  final String scope;
  final int type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRankProvider((scope, type)));
    final my = async.value;
    final ranked = my?.rank != null;
    final rankText = async.isLoading
        ? '统计中…'
        : (ranked ? '第 ${my!.rank} 名' : '暂未上榜');
    final distanceText = ranked
        ? Formatters.distance(my!.distanceMeters)
        : '待上榜';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_pin_circle,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppMetricText(
                  value: rankText,
                  label: '我的排名',
                  labelAbove: true,
                  valueSize: AppFontSize.headline,
                  labelSize: AppFontSize.caption,
                  labelColor: AppColors.textSecondary,
                  labelGap: AppSpacing.xs,
                  color: AppColors.textPrimary,
                  crossAxisAlignment: CrossAxisAlignment.start,
                ),
              ),
              AppMetricText(
                value: distanceText,
                label: '累计距离',
                labelAbove: true,
                valueSize: AppFontSize.title,
                labelSize: AppFontSize.caption,
                labelColor: AppColors.textSecondary,
                labelGap: AppSpacing.xs,
                color: AppColors.primary,
                crossAxisAlignment: CrossAxisAlignment.end,
                textAlign: TextAlign.right,
              ),
            ],
          ),
          if (async.hasError) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ref.invalidate(myRankProvider((scope, type))),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('个人排名加载失败，点击重试'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 榜单单行：排名 + 头像 + 昵称/ID + 差距 + 距离 + 社交按钮。
///
/// 社交按钮由服务端返回的 `relation` 决定，前端不自行推断：
/// 自己→看主页、好友→发消息、我申请过→等待中、对方申请我→通过、无关系→添加。
/// 这是「排行榜 → 加好友」的核心路径，也是本项目做排行榜的目的之一。
class _RankItem extends ConsumerStatefulWidget {
  const _RankItem({required this.entry});

  final LeaderboardEntry entry;

  @override
  ConsumerState<_RankItem> createState() => _RankItemState();
}

class _RankItemState extends ConsumerState<_RankItem> {
  bool _busy = false;
  bool _sent = false;

  LeaderboardEntry get entry => widget.entry;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(friendRepositoryProvider).sendRequest(entry.userId);
      if (!mounted) return;
      setState(() => _sent = true);
      _toast('已向「${entry.nickname}」发送好友申请');
      ref.invalidate(friendRequestsProvider);
      ref.invalidate(friendListProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    final requests = ref.read(friendRequestsProvider).value ?? const [];
    final match = requests.where((r) => r.userId == entry.userId).toList();
    if (match.isEmpty) {
      _toast('没有找到来自 TA 的申请，请下拉刷新后重试');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(friendRepositoryProvider).accept(match.first.requestId);
      if (!mounted) return;
      _toast('已添加「${entry.nickname}」为好友');
      // 刷新榜单，让按钮从「通过」变成「发消息」
      ref.invalidate(friendListProvider);
      ref.invalidate(friendRequestsProvider);
      ref.invalidate(leaderboardProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medalColor(entry.rank);
    return AppCard(
      // 自己那一行高亮：一眼找到「我在哪」，这是榜单最核心的诉求
      color: entry.isSelf ? AppColors.primaryLight : null,
      // 用 AppCard 自带的 onTap（内部是 Material + InkWell）。
      // 再在外层套 InkWell 会导致水波纹叠两层、点击态发暗。
      onTap: () => context.push('/user/${entry.userId}'),
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: AppMetricText(
                  value: '${entry.rank}',
                  valueSize: AppFontSize.headline,
                  color: medal ?? AppColors.textSecondary,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              UserAvatar(
                nickname: entry.nickname,
                avatarUrl: entry.avatarUrl,
                size: 42,
              ),
              const SizedBox(width: AppSpacing.smLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppFontSize.title,
                              fontWeight: AppFontWeight.medium,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (entry.isSelf) ...[
                          const SizedBox(width: AppSpacing.sm),
                          const _SelfTag(),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    // 有差距数据时优先显示「距上一名」，比再报一遍 ID 更有驱动力
                    if (entry.gapToAheadMeters != null)
                      Text(
                        _gapLabel(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppFontSize.caption,
                          color: AppColors.accentHot,
                        ),
                      )
                    else
                      Text(
                        Formatters.uniqueId(entry.uniqueId),
                        style: const TextStyle(
                          fontSize: AppFontSize.caption,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.distance(entry.distanceMeters),
                    style: const TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: AppFontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  _socialAction(),
                ],
              ),
            ],
          ),
        ),
    );
  }
  /// 「距离上一名还差 X」——比单纯报数字更能激发追赶。
  String _gapLabel(LeaderboardEntry e) {
    final ahead = e.gapToAheadMeters;
    if (ahead == null) return '';
    if (ahead == 0) return '与上一名持平';
    return '距上一名还差 ${Formatters.distance(ahead)}';
  }

  Widget _socialAction() {
    // 自己：没有社交操作
    if (entry.isSelf) {
      return const Text(
        '这是我',
        style: TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryDark,
        ),
      );
    }
    if (entry.isFriend) {
      return _MiniButton(
        icon: Icons.chat_bubble_outline,
        label: '发消息',
        onPressed: () => context.push(
          '/chat/${entry.userId}',
          extra: {'name': entry.nickname, 'avatarUrl': entry.avatarUrl},
        ),
      );
    }
    if (entry.isPendingIncoming) {
      return _MiniButton(
        icon: Icons.how_to_reg_outlined,
        label: '通过',
        loading: _busy,
        onPressed: _busy ? null : _accept,
      );
    }
    if (entry.isPendingOutgoing || _sent) {
      return const Text(
        '等待通过',
        style: TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.bold,
          color: AppColors.textHint,
        ),
      );
    }
    return _MiniButton(
      icon: Icons.person_add_alt,
      label: '加好友',
      loading: _busy,
      onPressed: _busy ? null : _add,
    );
  }
}

/// 行内小按钮：比主按钮更紧凑，避免把榜单行撑高。
class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.6, color: AppColors.onPrimary),
              )
            : Icon(icon, size: 13),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          textStyle: const TextStyle(
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.bold,
          ),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// 前三名配色：金 / 银 / 铜，其余走副文本色。
Color? _medalColor(int rank) {
  switch (rank) {
    case 1:
      return AppColors.rankGold;
    case 2:
      return AppColors.rankSilver;
    case 3:
      return AppColors.rankBronze;
    default:
      return null;
  }
}
