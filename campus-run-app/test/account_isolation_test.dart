import 'package:campus_run_app/data/models/friend_item.dart';
import 'package:campus_run_app/data/models/user.dart';
import 'package:campus_run_app/data/repositories/friend_repository.dart';
import 'package:campus_run_app/features/auth/providers/auth_provider.dart';
import 'package:campus_run_app/features/friends/providers/friend_badge_provider.dart';
import 'package:campus_run_app/features/friends/providers/friend_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 跨账号数据泄漏回归测试。
///
/// 复现的 bug：同一设备 A 退出、B 登录后，「社区」里显示的是 **A 的好友列表**
/// （A 的好友里恰好有 B），看起来就像「自己的账号出现在自己的好友里」。
///
/// 根因：`friendListProvider` 是全局缓存，没有和账号绑定 ——
/// 登出/登录并不会清掉它，于是 B 读到的是 A 的数据。
///
/// 这里用一个「按当前登录账号返回不同列表」的假仓储来固化行为：
/// 切账号后 provider 必须重新取数。
class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._user);
  final User? _user;
  @override
  Future<User?> build() async => _user;

  /// 模拟「同一设备切换账号」：直接改登录态。
  void switchTo(User? user) => state = AsyncData(user);
}

/// 按当前登录账号返回不同好友列表；不关心网络。
class _PerAccountFriendRepository extends FriendRepository {
  _PerAccountFriendRepository(this._friendsByUser)
      // 指向一个必然连不上的地址：任何真实网络调用都会失败，
      // 从而保证测试不会「悄悄」依赖后端（本类的 list() 已被覆写）。
      : super(Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1')));

  final Map<int, List<FriendItem>> _friendsByUser;
  int fetchCount = 0;

  /// 由测试在切换账号前后设置，代表「当前登录用户」。
  int currentUserId = 0;

  @override
  Future<List<FriendItem>> list() async {
    fetchCount++;
    return _friendsByUser[currentUserId] ?? const [];
  }
}

FriendItem _friend(int userId, String nickname, String uniqueId) => FriendItem(
      friendshipId: userId * 10,
      userId: userId,
      uniqueId: uniqueId,
      nickname: nickname,
    );

User _user(int id, String nickname) => User(
      userId: id,
      uniqueId: '0000000$id',
      nickname: nickname,
      phone: '1380013800$id',
    );

void main() {
  group('切账号后好友列表不会串号', () {
    test('B 登录后拿到的是 B 的好友，不是 A 的', () async {
      // A(id=1) 的好友是 TesterB(id=2)；B(id=4) 的好友是 沐瑾(id=3)
      final repo = _PerAccountFriendRepository({
        1: [_friend(2, 'TesterB', '53052911')],
        4: [_friend(3, '沐瑾', '47601012')],
      });
      final fakeAuth = _FakeAuth(_user(1, 'Mujin'));
      repo.currentUserId = 1;

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => fakeAuth),
        friendRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      // 保持一个订阅：Riverpod 会在无人监听时立刻回收 provider，
      // 那样 `.future` 会永远停在 loading（测试里表现为超时）。
      container.listen(friendListProvider, (_, __) {});
      container.listen(authProvider, (_, __) {});

      // A 登录：看到 TesterB
      var list = await container.read(friendListProvider.future);
      expect(list.map((f) => f.nickname), ['TesterB']);
      // 首次可能因账号切换重算而多取一次，这里只记录基线
      final baseline = repo.fetchCount;

      // 切换到 B：currentUserId 变了，provider 必须重新取数
      repo.currentUserId = 4;
      fakeAuth.switchTo(_user(4, '沐瑾B'));
      // 等 authProvider 变更传播到 friendListProvider
      await container.read(authProvider.future);
      list = await container.read(friendListProvider.future);

      expect(
        list.map((f) => f.nickname),
        ['沐瑾'],
        reason: '切到 B 后必须显示 B 的好友（沐瑾），而不是 A 的好友（TesterB）',
      );
      expect(repo.fetchCount, greaterThan(baseline), reason: '账号变化必须触发一次重新取数');

      // 关键断言：B 自己的昵称不能出现在 B 的好友列表里
      expect(
        list.any((f) => f.nickname == '沐瑾B'),
        isFalse,
        reason: '自己的账号不应出现在自己的好友列表里',
      );
    });

    test('登出后不再持有任何人的好友数据', () async {
      final repo = _PerAccountFriendRepository({
        1: [_friend(2, 'TesterB', '53052911')],
      });
      final fakeAuth = _FakeAuth(_user(1, 'Mujin'));
      repo.currentUserId = 1;

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => fakeAuth),
        friendRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      container.listen(friendListProvider, (_, __) {});
      container.listen(authProvider, (_, __) {});

      expect((await container.read(friendListProvider.future)).length, 1);

      fakeAuth.switchTo(null);
      await container.read(authProvider.future);
      final after = await container.read(friendListProvider.future);

      expect(after, isEmpty, reason: '登出后必须清空，避免下一个账号读到上一个人的数据');
    });

    test('反方向也一样：先 B 后 A，A 不该看到 B 的好友（含 A 自己）', () async {
      // 用户实测反馈的是这个方向：先登录沐瑾B、再登录 Mujin，
      // 结果 Mujin 页面的好友栏里出现的是 A（即上一个账号 B 的好友列表里的 Mujin）。
      final repo = _PerAccountFriendRepository({
        1: [_friend(2, 'TesterB', '53052911')], // A 的好友（注意：里面是 B）
        4: [_friend(3, '沐瑾', '47601012')], // B 的好友
      });
      final fakeAuth = _FakeAuth(_user(4, '沐瑾B'));
      repo.currentUserId = 4;

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => fakeAuth),
        friendRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      container.listen(friendListProvider, (_, __) {});
      container.listen(authProvider, (_, __) {});

      expect((await container.read(friendListProvider.future)).map((f) => f.nickname), ['沐瑾']);

      // 切到 A
      repo.currentUserId = 1;
      fakeAuth.switchTo(_user(1, 'Mujin'));
      await container.read(authProvider.future);
      final list = await container.read(friendListProvider.future);

      expect(list.map((f) => f.nickname), ['TesterB']);
      expect(
        list.any((f) => f.nickname == 'Mujin'),
        isFalse,
        reason: 'A 的昵称不能出现在 A 自己的好友列表里',
      );
      expect(
        list.any((f) => f.nickname == '沐瑾'),
        isFalse,
        reason: '不能残留上一个账号（B）的好友「沐瑾」',
      );
    });

    test('切账号会清空未读红点（避免继承上一个账号的红点）', () {
      final fakeAuth = _FakeAuth(_user(4, '沐瑾B'));

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => fakeAuth),
      ]);
      addTearDown(container.dispose);
      container.listen(friendBadgeProvider, (_, __) {});
      container.listen(currentChatFriendIdProvider, (_, __) {});
      container.listen(authProvider, (_, __) {});

      container.read(friendBadgeProvider.notifier).markMessage();
      container.read(currentChatFriendIdProvider.notifier).set(3);

      expect(container.read(friendBadgeProvider).hasUnreadMessage, isTrue);
      expect(container.read(currentChatFriendIdProvider), 3);

      // 切账号
      fakeAuth.switchTo(_user(1, 'Mujin'));

      expect(
        container.read(friendBadgeProvider).hasUnreadMessage,
        isFalse,
        reason: '切账号后红点必须清空，否则新账号会继承上一个账号的未读状态',
      );
      expect(
        container.read(currentChatFriendIdProvider),
        isNull,
        reason: '「当前打开会话」必须随账号重置，否则新消息会被误判为正在浏览而被吞掉',
      );
    });

    test('未登录时不发请求（避免带旧令牌打一次必然 401 的请求）', () async {
      final repo = _PerAccountFriendRepository({});
      final fakeAuth = _FakeAuth(null);

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => fakeAuth),
        friendRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      container.listen(friendListProvider, (_, __) {});
      container.listen(authProvider, (_, __) {});

      final list = await container.read(friendListProvider.future);

      expect(list, isEmpty);
      expect(repo.fetchCount, 0, reason: '未登录不该发请求');
    });
  });
}
