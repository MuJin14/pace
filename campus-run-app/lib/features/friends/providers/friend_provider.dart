import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/account_scope.dart';
import '../../../data/models/friend_item.dart';
import '../../../data/models/friend_request.dart';
import '../../../data/models/page_response.dart';
import '../../../data/models/user_brief.dart';
import '../../../data/repositories/friend_repository.dart';

/// 好友列表。
///
/// **必须 `watchUserId()`**：这是「自己的好友」，会随账号变化。
/// 早期少了这一步，同一设备切账号后会显示上一个账号的好友列表
/// （表现为「自己的账号出现在自己的好友里」）。
final friendListProvider = FutureProvider<List<FriendItem>>((ref) async {
  if (ref.watchUserId() == null) return const [];
  return ref.read(friendRepositoryProvider).list();
});

/// 收到的好友申请。同样随账号变化，理由同 [friendListProvider]。
final friendRequestsProvider = FutureProvider<List<FriendRequest>>((ref) async {
  if (ref.watchUserId() == null) return const [];
  return ref.read(friendRepositoryProvider).requests();
});

/// 好友搜索（按关键词）。
///
/// 结果里的 `relation`（self / friend / pending_*）是**相对当前登录用户**算出来的，
/// 所以也必须随账号重算；否则换账号后按钮状态会沿用上一个账号的关系
/// （例如把「已是好友」显示成「添加」）。
/// 搜索结果的查询条件：**关键词 + 页码**。
///
/// 之前 family 的 key 只有关键词，于是永远只能看到第 1 页（20 条），
/// 超过 20 人的搜索结果被静默截断 —— 用户以为「只有这些人」。
/// 加页码后每次翻页都是一次正常的分页请求，服务端本来就已经支持。
@immutable
class FriendSearchQuery {
  const FriendSearchQuery(this.keyword, this.page);

  final String keyword;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is FriendSearchQuery &&
      other.keyword == keyword &&
      other.page == page;

  @override
  int get hashCode => Object.hash(keyword, page);
}

final friendSearchProvider =
    FutureProvider.family<PageResponse<UserBrief>, FriendSearchQuery>(
  (ref, query) async {
    if (ref.watchUserId() == null) {
      return PageResponse<UserBrief>(total: 0, page: 1, size: 20, list: const []);
    }
    return ref.read(friendRepositoryProvider).search(query.keyword, page: query.page);
  },
);
