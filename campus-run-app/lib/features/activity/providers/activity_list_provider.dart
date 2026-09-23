import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/activity_summary.dart';
import '../../../data/repositories/activity_repository.dart';

/// 运动记录列表状态（分页）。
final activityListProvider =
    AsyncNotifierProvider<ActivityListNotifier, List<ActivitySummary>>(
  ActivityListNotifier.new,
);

/// 上拉加载中的标记，供列表底部 spinner 响应式展示。
final activityLoadingMoreProvider =
    NotifierProvider<ActivityLoadingMoreNotifier, bool>(
  ActivityLoadingMoreNotifier.new,
);

class ActivityLoadingMoreNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class ActivityListNotifier extends AsyncNotifier<List<ActivitySummary>> {
  static const _size = 20;

  int _page = 1;
  int? _type;
  bool _hasMore = true;

  bool get hasMore => _hasMore;

  @override
  Future<List<ActivitySummary>> build() async {
    _page = 1;
    _hasMore = true;
    final result = await ref
        .read(activityRepositoryProvider)
        .page(page: 1, size: _size, type: _type);
    _hasMore = result.total > result.list.length;
    return result.list;
  }

  /// 切换类型筛选：null=全部，1=跑步，2=骑行。
  void setType(int? type) {
    if (_type == type) return;
    _type = type;
    ref.invalidateSelf();
  }

  Future<void> refresh() async {
    final result = await ref
        .read(activityRepositoryProvider)
        .page(page: 1, size: _size, type: _type);
    _page = 1;
    _hasMore = result.total > result.list.length;
    state = AsyncData(result.list);
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    if (ref.read(activityLoadingMoreProvider)) return;
    ref.read(activityLoadingMoreProvider.notifier).set(true);
    try {
      final current = state.value ?? const <ActivitySummary>[];
      final next = _page + 1;
      final result = await ref
          .read(activityRepositoryProvider)
          .page(page: next, size: _size, type: _type);
      _page = next;
      _hasMore = (current.length + result.list.length) < result.total;
      state = AsyncData([...current, ...result.list]);
    } finally {
      ref.read(activityLoadingMoreProvider.notifier).set(false);
    }
  }
}
