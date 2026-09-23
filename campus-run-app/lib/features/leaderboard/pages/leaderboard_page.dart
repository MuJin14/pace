import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../providers/leaderboard_provider.dart';

const _scopes = [
  ('daily', '日榜'),
  ('weekly', '周榜'),
  ('monthly', '月榜'),
  ('rolling30d', '30天榜'),
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
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => _ErrorView(
                message: err is ApiException ? err.message : '加载失败，请稍后重试',
                onRetry: () => ref.invalidate(leaderboardProvider((_scope, _type))),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.emoji_events,
                    title: '榜单暂无数据',
                    subtitle: '去跑一跑，抢占第一名的位置吧',
                  );
                }
                return _buildList(list);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<LeaderboardEntry> list) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(leaderboardProvider((_scope, _type))),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: list.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _MyRankCard(scope: _scope, type: _type),
            );
          }
          return _RankItem(entry: list[index - 1]);
        },
      ),
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _scopes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final scope = _scopes[i];
          final isSel = scope.$1 == selected;
          return ChoiceChip(
            label: Text(scope.$2),
            selected: isSel,
            onSelected: (_) => onChanged(scope.$1),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.card,
            labelStyle: TextStyle(
              color: isSel ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            showCheckmark: false,
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          _typeChip(context, 1, Icons.directions_run, '跑步', AppColors.run),
          const SizedBox(width: 8),
          _typeChip(context, 2, Icons.directions_bike, '骑行', AppColors.ride),
        ],
      ),
    );
  }

  Widget _typeChip(BuildContext context, int value, IconData icon, String label, Color color) {
    final isSel = selected == value;
    return ChoiceChip(
      avatar: Icon(icon, size: 18, color: isSel ? Colors.white : color),
      label: Text(label),
      selected: isSel,
      onSelected: (_) => onChanged(value),
      selectedColor: color,
      backgroundColor: AppColors.card,
      labelStyle: TextStyle(
        color: isSel ? Colors.white : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      showCheckmark: false,
    );
  }
}

class _MyRankCard extends ConsumerWidget {
  const _MyRankCard({required this.scope, required this.type});

  final String scope;
  final int type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final my = ref.watch(myRankProvider((scope, type))).value;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.14), AppColors.card],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle, color: AppColors.primary, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('我的排名', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  my?.rank != null ? '第 ${my!.rank} 名' : '暂未上榜',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('累计距离', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(
                Formatters.distance(my?.distanceMeters ?? 0),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankItem extends StatelessWidget {
  const _RankItem({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final medal = _medalColor(entry.rank);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: medal ?? AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          UserAvatar(nickname: entry.nickname, avatarUrl: entry.avatarUrl, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.nickname, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(entry.uniqueId, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(
            Formatters.distance(entry.distanceMeters),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Color? _medalColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFF59E0B);
      case 2:
        return const Color(0xFF94A3B8);
      case 3:
        return const Color(0xFFB45309);
      default:
        return null;
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
