import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_hint.dart';
import '../../../core/widgets/app_progress_ring.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../data/models/badge.dart' as models;
import '../providers/badge_provider.dart';

/// 勋章墙：全部勋章（已获得高亮）+ 点亮进度。
class BadgesPage extends ConsumerWidget {
  const BadgesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(badgeAllProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的勋章')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(badgeAllProvider);
          await ref.read(badgeAllProvider.future);
        },
        child: async.when(
          loading: () => const ScrollableCenter(child: CircularProgressIndicator()),
          error: (err, _) => ScrollableCenter(
            child: ErrorState(
              message: err is ApiException ? err.message : '加载失败，请稍后重试',
              onRetry: () => ref.invalidate(badgeAllProvider),
            ),
          ),
          data: (badges) {
            if (badges.isEmpty) {
              return ScrollableCenter(
                child: EmptyState(
                  icon: Icons.workspace_premium,
                  title: '勋章墙正在筹备中',
                  subtitle: '先跑起来，新的勋章会陆续点亮',
                  actionLabel: '去跑步',
                  onAction: () => context.push('/start-run'),
                ),
              );
            }
            final earned = badges.where((b) => b.earned).length;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.md,
                AppSpacing.page,
                AppSpacing.lg,
              ),
              children: [
                _ProgressCard(earned: earned, total: badges.length),
                const SizedBox(height: AppSpacing.lg),
                const AppSectionTitle(title: '全部勋章'),
                const SizedBox(height: AppSpacing.md),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.6,
                  ),
                  itemCount: badges.length,
                  itemBuilder: (context, i) => _BadgeTile(badge: badges[i]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 勋章进度卡片：已获得数量 + 进度条；一枚未点亮时给出召唤语与动作。
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.earned, required this.total});

  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : earned / total;

    // 一枚未点亮：走空态（召唤语 + 可点击动作），不出现「0」。
    if (earned == 0) {
      return AppCard(
        child: Row(
          children: [
            AppProgressRing(value: ratio, size: 72, strokeWidth: 8),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppEmptyHint(
                title: '勋章墙还空着',
                description: '完成一次运动，点亮第一枚勋章',
                actionLabel: '去跑步',
                onAction: () => context.push('/start-run'),
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Row(
        children: [
          AppProgressRing(value: ratio, size: 72, strokeWidth: 8),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已获得 $earned / $total',
                  style: const TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '继续保持，下一枚勋章就在前方',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final models.Badge badge;

  @override
  Widget build(BuildContext context) {
    final earned = badge.earned;
    final color = earned ? AppColors.gold : AppColors.textHint;
    return AppCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              earned ? Icons.emoji_events : Icons.lock_outline,
              color: color,
              size: 26,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            badge.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: AppFontWeight.bold,
              color: earned ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            badge.description ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: AppFontSize.caption,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
