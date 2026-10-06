import 'package:campus_run_app/core/ws/global_ws_provider.dart';
import 'package:campus_run_app/data/models/chat_message.dart';
import 'package:campus_run_app/data/models/page_response.dart';
import 'package:campus_run_app/data/models/user.dart';
import 'package:campus_run_app/core/theme/app_theme.dart';
import 'package:campus_run_app/features/auth/providers/auth_provider.dart';
import 'package:campus_run_app/features/friends/pages/chat_page.dart';
import 'package:campus_run_app/features/friends/providers/message_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 聊天消息「发送方归属」回归测试。
///
/// 复现的 bug：同一设备切账号 A→B 后，A 发给 B 的消息在 B 侧显示成
/// **B 自己发的**（气泡靠右）。
///
/// 判据：气泡对齐只取决于 `mine = message.senderId == 当前登录 userId`，
/// 与当前会话的 friendId 无关。因此这里固定：
///   - 登录用户 = 4（B）
///   - 会话对象 = 3（A）
///   - 消息 senderId = 3, receiverId = 4
/// 期望：**靠左（收到）**。若实现里把 `friendId` 当成发送方，就会靠右。

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._user);
  final User? _user;
  @override
  Future<User?> build() async => _user;
}

class _FakeWs extends GlobalWsNotifier {
  @override
  GlobalWsStatus build() => GlobalWsStatus.connected;
  @override
  Future<ChatMessage> sendMessage({
    required int receiverId,
    required String content,
    int? type,
    String? mediaUrl,
  }) async {
    return ChatMessage(
      messageId: 999,
      senderId: 0,
      receiverId: receiverId,
      content: content,
      type: type ?? 1,
      mediaUrl: mediaUrl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

User _user(int id, String nickname) => User(
      userId: id,
      uniqueId: '0000000$id',
      nickname: nickname,
      phone: '1380013800$id',
    );

const _fromA = ChatMessage(
  messageId: 1,
  senderId: 3,
  receiverId: 4,
  content: 'A 发给 B 的消息',
  timestamp: 1791048417000,
);

Future<void> _pumpChat(
  WidgetTester tester, {
  required User loggedIn,
  required int friendId,
  required List<ChatMessage> history,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(() => _FakeAuth(loggedIn)),
      globalWsProvider.overrideWith(_FakeWs.new),
      messageHistoryProvider.overrideWith(
        (ref, id) async => PageResponse<ChatMessage>(
          total: history.length,
          page: 1,
          size: 20,
          list: history,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: ChatPage(friendId: friendId, friendName: 'A 同学'),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 气泡是否「我发的」。权威判据是 `_Bubble` 外层 Align 的对齐方向：
/// 靠右 = 我发的，靠左 = 收到的。
///
/// 刻意不用颜色判断：`Container(decoration: ...)` 实际渲染成 `DecoratedBox`，
/// `Container.color` 为 null，用颜色判断会永远得出「不是我发的」这个假结论。
bool _bubbleIsMine(WidgetTester tester, String content) {
  final text = find.text(content);
  expect(text, findsOneWidget, reason: '消息「$content」应渲染出来');
  final align = tester.widget<Align>(
    find.ancestor(of: text, matching: find.byType(Align)).first,
  );
  return align.alignment == Alignment.centerRight;
}

void main() {
  testWidgets('B 侧看 A 发来的消息 → 气泡靠左（不是我发的）', (tester) async {
    await _pumpChat(
      tester,
      loggedIn: _user(4, 'B'),
      friendId: 3,
      history: const [_fromA],
    );

    expect(
      _bubbleIsMine(tester, 'A 发给 B 的消息'),
      isFalse,
      reason: 'senderId=3 而当前登录 userId=4，必须判为「收到的消息」（靠左）',
    );
  });

  testWidgets('A 侧看自己发的同一条消息 → 气泡靠右（我发的）', (tester) async {
    await _pumpChat(
      tester,
      loggedIn: _user(3, 'A'),
      friendId: 4,
      history: const [_fromA],
    );

    expect(
      _bubbleIsMine(tester, 'A 发给 B 的消息'),
      isTrue,
      reason: 'senderId=3 等于当前登录 userId=3，必须判为「我发的」（靠右）',
    );
  });

  testWidgets('切账号（B→A）：同一条消息的归属跟着登录态翻转', (tester) async {
    // 覆盖「同设备切账号」：消息内容不变，只换登录用户与 fix 会话对象，
    // 归属必须翻转。用两个独立的 ProviderScope（真实场景就是重新登录后
    // 重建整棵树），而不是在同一个 container 上换 override —— 后者不是
    // app 的真实行为，测出来的是测试脚手架的问题。
    await _pumpChat(
      tester,
      loggedIn: _user(4, 'B'),
      friendId: 3,
      history: const [_fromA],
    );
    expect(
      _bubbleIsMine(tester, 'A 发给 B 的消息'),
      isFalse,
      reason: 'B 登录时看 A 的消息，必须是「收到的」',
    );

    // 卸载整棵树，模拟切账号后重新进入会话
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await _pumpChat(
      tester,
      loggedIn: _user(3, 'A'),
      friendId: 4,
      history: const [_fromA],
    );
    expect(
      _bubbleIsMine(tester, 'A 发给 B 的消息'),
      isTrue,
      reason: '切到 A 后同一条消息必须变成「我发的」',
    );
  });
}
