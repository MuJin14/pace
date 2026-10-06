import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/account_scope.dart';
import '../../../data/models/badge.dart';
import '../../../data/models/user_badge.dart';
import '../../../data/repositories/badge_repository.dart';

/// 全部勋章定义（与账号无关，不需要 watchUserId）。
final badgeAllProvider = FutureProvider<List<Badge>>((ref) {
  return ref.read(badgeRepositoryProvider).all();
});

/// 我获得的勋章 —— 私有数据，必须随账号变化。
final badgeMineProvider = FutureProvider<List<UserBadge>>((ref) async {
  if (ref.watchUserId() == null) return const [];
  return ref.read(badgeRepositoryProvider).mine();
});
