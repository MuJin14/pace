import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/account_scope.dart';
import '../../../data/models/goal.dart';
import '../../../data/repositories/goal_repository.dart';

/// 我的运动目标列表 —— 私有数据，必须随账号变化。
final goalListProvider = FutureProvider<List<Goal>>((ref) async {
  if (ref.watchUserId() == null) return const [];
  return ref.read(goalRepositoryProvider).list();
});
