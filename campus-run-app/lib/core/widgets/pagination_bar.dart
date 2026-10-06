import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 通用分页控件：上一页 / 页码 / 下一页。
///
/// ## 为什么不用无限滚动（下拉加载更多）
///
/// 两者的取舍：
///   · 无限滚动适合「内容流」（朋友圈、动态），用户不知道有多少、也不关心；
///   · **搜索结果的用户需要知道「共几人、我在第几页」** ——
///     找同学时「一共 37 人，我在第 2 页」是有效信息，
///     而无限滚动只给「越拉越多」的不确定感。
///
/// 所以这里用显式的分页条。
///
/// ## 页码展示规则
///
/// 页数少时全部列出来；多了则折叠成「首页 … 当前-1 当前 当前+1 … 末页」。
/// 全列会让窄屏横向溢出，而超过 7 个页码按钮在手机上也点不准。
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.size,
    required this.total,
    required this.onPageChanged,
    this.enabled = true,
  });

  /// 当前页（从 1 开始）。
  final int page;

  /// 每页条数。
  final int size;

  /// 总条数。
  final int total;

  final ValueChanged<int> onPageChanged;

  /// 加载中时置 false，避免连点导致重复请求。
  final bool enabled;

  int get _pageCount => total <= 0 ? 1 : (total + size - 1) ~/ size;

  @override
  Widget build(BuildContext context) {
    final pages = _pageCount;
    if (pages <= 1) {
      // 只有一页时不显示翻页条：一个点了没反应的控件不如没有
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ArrowButton(
                icon: Icons.chevron_left,
                enabled: enabled && page > 1,
                onTap: () => onPageChanged(page - 1),
              ),
              const SizedBox(width: AppSpacing.xs),
              for (final item in _pageItems(pages)) ...[
                if (item == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '…',
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        color: AppColors.textHint,
                      ),
                    ),
                  )
                else
                  _PageChip(
                    page: item,
                    current: item == page,
                    enabled: enabled,
                    onTap: () => onPageChanged(item),
                  ),
                const SizedBox(width: AppSpacing.xs),
              ],
              _ArrowButton(
                icon: Icons.chevron_right,
                enabled: enabled && page < pages,
                onTap: () => onPageChanged(page + 1),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '第 $page / $pages 页 · 共 $total 位',
            style: const TextStyle(
              fontSize: AppFontSize.caption,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  /// 要显示的页码；null 表示省略号。
  List<int?> _pageItems(int pages) {
    const window = 1; // 当前页左右各显示几个
    // 显式标注 List<int>：直接建成 <int?> 的话 where 里的 p 是可空的，
    // 比较运算会报「unchecked_use_of_nullable_value」。
    final wanted = <int>{
      1,
      pages,
      for (var i = page - window; i <= page + window; i++) i,
    }.where((p) => p >= 1 && p <= pages).toList()
      ..sort();
    final items = wanted;

    final result = <int?>[];
    int? prev;
    for (final p in items) {
      if (prev != null && p - prev > 1) result.add(null); // 中间有断档
      result.add(p);
      prev = p;
    }
    return result;
  }
}

class _PageChip extends StatelessWidget {
  const _PageChip({
    required this.page,
    required this.current,
    required this.enabled,
    required this.onTap,
  });

  final int page;
  final bool current;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled && !current ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: current ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(
            color: current ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Text(
          '$page',
          style: TextStyle(
            fontSize: AppFontSize.label,
            fontWeight: current ? AppFontWeight.bold : AppFontWeight.regular,
            color: current ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppColors.textSecondary : AppColors.textHint,
        ),
      ),
    );
  }
}
