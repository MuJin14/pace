import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/account_scope.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/models/page_response.dart';
import '../../../data/repositories/message_repository.dart';

/// 与某好友的聊天历史（最新一页）。
///
/// 虽然参数是 friendId，但**会话是「我 ↔ 他」的**，同一次切换账号后
/// 同一条历史在两侧看到的归属不同（见 chat_page 的消息归属约定），
/// 所以也必须随账号重算，否则切账号后展示的是上一个账号与好友的对话。
final messageHistoryProvider =
    FutureProvider.family<PageResponse<ChatMessage>, int>((ref, friendId) async {
  if (ref.watchUserId() == null) {
    return PageResponse<ChatMessage>(total: 0, page: 1, size: 20, list: const []);
  }
  return ref.read(messageRepositoryProvider).history(friendId);
});
