import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/friend_item.dart';
import '../../../data/models/friend_request.dart';
import '../../../data/models/page_response.dart';
import '../../../data/models/user_brief.dart';
import '../../../data/repositories/friend_repository.dart';

final friendListProvider = FutureProvider<List<FriendItem>>((ref) {
  return ref.read(friendRepositoryProvider).list();
});

final friendRequestsProvider = FutureProvider<List<FriendRequest>>((ref) {
  return ref.read(friendRepositoryProvider).requests();
});

/// 好友搜索（按关键词）。
final friendSearchProvider =
    FutureProvider.family<PageResponse<UserBrief>, String>((ref, keyword) {
  return ref.read(friendRepositoryProvider).search(keyword);
});
