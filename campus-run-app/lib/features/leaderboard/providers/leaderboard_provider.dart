import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/my_rank.dart';
import '../../../data/repositories/leaderboard_repository.dart';

/// 榜单查询键：(scope, type)。scope 取值 daily/weekly/rolling30d/monthly；type 1=跑步 2=骑行。
typedef LeaderboardKey = (String, int);

final leaderboardProvider =
    FutureProvider.family<List<LeaderboardEntry>, LeaderboardKey>((ref, key) async {
  final (scope, type) = key;
  final result = await ref
      .read(leaderboardRepositoryProvider)
      .board(scope: scope, type: type);
  return result.list;
});

final myRankProvider = FutureProvider.family<MyRank, LeaderboardKey>((ref, key) {
  final (scope, type) = key;
  return ref.read(leaderboardRepositoryProvider).myRank(scope: scope, type: type);
});
