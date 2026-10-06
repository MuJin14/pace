import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/account_scope.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/my_rank.dart';
import '../../../data/repositories/leaderboard_repository.dart';

/// 榜单查询键：(scope, type)。scope 取值 daily/weekly/rolling30d/monthly；type 1=跑步 2=骑行。
typedef LeaderboardKey = (String, int);

/// 榜单条目本身是公开数据，与账号无关，不需要 watchUserId。
final leaderboardProvider =
    FutureProvider.family<List<LeaderboardEntry>, LeaderboardKey>((ref, key) async {
  final (scope, type) = key;
  final result = await ref
      .read(leaderboardRepositoryProvider)
      .board(scope: scope, type: type);
  return result.list;
});

/// 我的排名 —— 私有数据，必须随账号变化，否则换账号后会显示上一个账号的名次。
final myRankProvider = FutureProvider.family<MyRank, LeaderboardKey>((ref, key) async {
  if (ref.watchUserId() == null) {
    return const MyRank(rank: null, distanceMeters: 0, total: 0);
  }
  final (scope, type) = key;
  return ref.read(leaderboardRepositoryProvider).myRank(scope: scope, type: type);
});
