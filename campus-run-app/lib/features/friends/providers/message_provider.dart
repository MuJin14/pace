import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat_message.dart';
import '../../../data/models/page_response.dart';
import '../../../data/repositories/message_repository.dart';

/// 与某好友的聊天历史（最新一页）。
final messageHistoryProvider =
    FutureProvider.family<PageResponse<ChatMessage>, int>((ref, friendId) {
  return ref.read(messageRepositoryProvider).history(friendId);
});
