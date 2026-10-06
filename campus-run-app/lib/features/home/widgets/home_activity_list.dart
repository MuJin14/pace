import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_empty_hint.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../../data/models/activity_summary.dart';

/// 设计稿 §2：近期运动行高 64、图标盒 36（圆角 12）、图标 18。
const double _kRowHeight = 64;
const double _kIconBox = 36;
const double _kIconSize = 18;

/// 设计稿 §3：空态圆图标 56。
const double _kEmptyIconBox = 56;

/// 空态动作箭头尺寸。
const double _kChevronSize = 12;

/// 首页「近期运动」区块（设计稿 §1：区块高度 226）。
///
/// - 有记录 → 卡片内最多 [take] 行（行高 64、分隔线 #F5F0EB）；点击行回调 [onItemTap]
/// - 无记录 → 空态卡：圆图标 56 + 召唤语「还没有运动记录」+ 可点动作「去跑步」
///
/// 跳转由页面注入，widget 内部不做 `context.push`：
/// - [onStartRun]：必填，空态「去跑步」动作
/// - [onSeeAll]：可选，标题右侧「查看全部」（为 null 时隐藏）
/// - [onItemTap]：可选，单条记录点击（为 null 时行不可点）
class HomeActivityList extends StatelessWidget {
  const HomeActivityList({
    super.key,
    required this.items,
    this.take = 3,
    required this.onStartRun,
    this.onSeeAll,
    this.onItemTap,
  });

  final List<ActivitySummary> items;
  final int take;
  final VoidCallback onStartRun;
  final VoidCallback? onSeeAll;
  final void Function(ActivitySummary item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    final recent = items.take(take < 0 ? 0 : take).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionTitle(title: '近期运动', onSeeAll: onSeeAll),
        const SizedBox(height: AppSpacing.smLg),
        if (recent.isEmpty)
          _EmptyRecentCard(onStartRun: onStartRun)
        else
          Container(
            // AppCard / AppDashboardCard 无裁剪参数，行内 InkWell 水波纹需按圆角裁切，
            // 故此处复用同一套 token 自绘容器（视觉与 AppDashboardCard 完全一致）。
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              children: [
                for (int i = 0; i < recent.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.dividerLight,
                    ),
                  _RecentItem(
                    item: recent[i],
                    deltaMeters: _homeDeltaMeters(recent, i),
                    onTap:
                        onItemTap == null ? null : () => onItemTap!(recent[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 单条运动记录行（设计稿 §2：行高 64、图标盒 36 圆角 12）。
class _RecentItem extends StatelessWidget {
  const _RecentItem({
    required this.item,
    required this.onTap,
    this.deltaMeters,
  });

  final ActivitySummary item;
  final VoidCallback? onTap;

  /// 与更早一条同类型记录的距离差（米）；不可比时为 null。
  final int? deltaMeters;

  @override
  Widget build(BuildContext context) {
    final isRun = item.isRunning;
    final color = isRun ? AppColors.run : AppColors.ride;
    final icon = isRun ? Icons.directions_run : Icons.directions_bike;
    final title =
        '${isRun ? '跑步' : '骑行'} · ${Formatters.distance(item.distanceMeters)}';
    final subtitle =
        '${_homeRelativeTime(item.startTime)}'
        ' · 配速 ${Formatters.pace(item.avgPace)}';
    final delta = deltaMeters;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _kRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: _kIconBox,
                height: _kIconBox,
                decoration: BoxDecoration(
                  color: AppColors.iconBgPeach,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: _kIconSize, color: color),
              ),
              const SizedBox(width: AppSpacing.smLg),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: AppFontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: AppFontWeight.regular,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.duration(item.durationSeconds),
                    style: const TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: AppFontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (delta != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${delta > 0 ? '+' : '-'}'
                      '${(delta.abs() / 1000).toStringAsFixed(1)} km',
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        fontWeight: AppFontWeight.medium,
                        color:
                            delta > 0 ? AppColors.deltaUp : AppColors.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 无记录空态：圆图标 56 + 召唤语 + 可点「去跑步」（设计稿 §3）。
class _EmptyRecentCard extends StatelessWidget {
  const _EmptyRecentCard({required this.onStartRun});

  final VoidCallback onStartRun;

  @override
  Widget build(BuildContext context) {
    return AppDashboardCard(
      child: AppEmptyHint(
        layout: AppEmptyHintLayout.row,
        icon: Icons.directions_run,
        iconBoxSize: _kEmptyIconBox,
        title: '还没有运动记录',
        titleSize: AppFontSize.subtitle,
        description: '去跑一跑，留下你的第一条轨迹',
        descriptionSize: AppFontSize.caption,
        action: _StartRunLink(onTap: onStartRun),
      ),
    );
  }
}

/// 空态动作：轻量文字链接（刻意不用整宽主按钮，避免与页面顶部主 CTA 重复）。
class _StartRunLink extends StatelessWidget {
  const _StartRunLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '去跑步',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: AppFontWeight.bold,
                  color: AppColors.accentHot,
                ),
              ),
              SizedBox(width: AppSpacing.xxs),
              Icon(
                Icons.arrow_forward_ios,
                size: _kChevronSize,
                color: AppColors.accentHot,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 自包含工具（复制自 home_page.dart，避免 import 页面文件形成环） ──
DateTime _homeDayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// 相对时间：今天 / 昨天 HH:mm，更早显示 M月d日 HH:mm。
String _homeRelativeTime(String? s) {
  final dt = DateTime.tryParse(s ?? '');
  if (dt == null) return s ?? '';
  final today = _homeDayOf(DateTime.now());
  final day = _homeDayOf(dt);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  if (day == today) return '今天 $hh:$mm';
  if (day == today.subtract(const Duration(days: 1))) return '昨天 $hh:$mm';
  return '${dt.month}月${dt.day}日 $hh:$mm';
}

/// 环比（设计稿 §2「环比」）：与列表中下一条（更早一条）同类型记录比距离。
///
/// 依赖 [items] 为「新 → 旧」排序（activity_list_provider 的列表顺序）；
/// 末条、类型不同或距离持平时返回 null（不出现「0」「—」）。
int? _homeDeltaMeters(List<ActivitySummary> items, int index) {
  if (index + 1 >= items.length) return null;
  final current = items[index];
  final previous = items[index + 1];
  if (current.type != previous.type) return null;
  final diff = current.distanceMeters - previous.distanceMeters;
  return diff == 0 ? null : diff;
}
