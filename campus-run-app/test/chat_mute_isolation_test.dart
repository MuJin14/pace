import 'package:campus_run_app/data/models/user.dart';
import 'package:campus_run_app/data/repositories/chat_preference_repository.dart';
import 'package:campus_run_app/features/auth/providers/auth_provider.dart';
import 'package:campus_run_app/features/friends/providers/chat_preference_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 免打扰名单的**账号隔离**（跨账号数据泄漏回归）。
///
/// **复现的 bug 类型**：`mutedFriendIdsProvider` 是全局缓存。
/// 若不在 `build()` 里 `watchUserId()`，同一设备 A 退出、B 登录后，
/// B 会继承 **A 的静音名单** —— 表现是「新账号莫名其妙收不到某个好友的消息提醒」，
/// 而设置页显示的开关状态也是错的，用户完全无法自查。
///
/// 这与项目里已出过的 `friendListProvider` / `activityListProvider` 属于同一类，
/// 因此同样用 `watchUserId()` 加固，并用本测试固化。
class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._user);

  final User? _user;

  @override
  Future<User?> build() async => _user;

  /// 模拟「同一设备切换账号」。
  void switchTo(User? user) => state = AsyncData(user);
}

/// 按当前登录账号返回不同静音名单；不发真实请求。
class _PerAccountMuteRepository extends ChatPreferenceRepository {
  _PerAccountMuteRepository(this._mutedByUser)
      // 指向必然连不上的地址：任何漏掉的真实调用都会立刻失败，
      // 从而保证测试不会「悄悄」依赖后端。
      : super(Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1')));

  final Map<int, List<int>> _mutedByUser;
  int fetchCount = 0;

  /// 由测试在切换账号前后设置，代表「当前登录用户」。
  int currentUserId = 0;

  @override
  Future<List<int>> mutedFriendIds() async {
    fetchCount++;
    return _mutedByUser[currentUserId] ?? const [];
  }

  @override
  Future<void> setMuted(int friendId, bool muted) async {
    final list = _mutedByUser.putIfAbsent(currentUserId, () => []);
    if (muted) {
      if (!list.contains(friendId)) list.add(friendId);
    } else {
      list.remove(friendId);
    }
  }
}

User _user(int id, String nickname) => User(
      userId: id,
      uniqueId: '0000000$id',
      nickname: nickname,
      phone: '1380013800$id',
    );

void main() {
  group('免打扰名单必须随账号重建', () {
    test('B 登录后拿到的是 B 的静音名单，不是 A 的', () async {
      // A(id=1) 静音了 2；B(id=4) 静音了 3
      final repo = _PerAccountMuteRepository({
        1: [2],
        4: [3],
      });
      final auth = _FakeAuth(_user(1, '甲'));

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => auth),
        chatPreferenceRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      // A 的视角
      repo.currentUserId = 1;
      // 必须先等 authProvider 就绪：watchUserId() 读的是它的 value，
      // 未就绪时拿到 null 会走「未登录」分支（既有测试同样这么做）。
      await container.read(authProvider.future);
      final aMuted = await container.read(mutedFriendIdsProvider.future);
      expect(aMuted, {2}, reason: 'A 应看到自己静音的 2');

      // 切到 B：同时改「当前账号」与假仓库的视角
      repo.currentUserId = 4;
      auth.switchTo(_user(4, '乙'));

      // 切账号后同样先让 auth 就绪，再读业务 provider
      await container.read(authProvider.future);
      final bMuted = await container.read(mutedFriendIdsProvider.future);

      expect(bMuted, {3},
          reason: 'B 必须拿到自己的名单；拿到 {2} 说明沿用了 A 的缓存');
      expect(bMuted, isNot(contains(2)));
    });

    test('未登录时返回空集合，且不发请求', () async {
      final repo = _PerAccountMuteRepository({1: [2]});
      final auth = _FakeAuth(null);

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => auth),
        chatPreferenceRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      await container.read(authProvider.future);
      final ids = await container.read(mutedFriendIdsProvider.future);

      expect(ids, isEmpty, reason: '未登录直接给空集');
      expect(repo.fetchCount, 0,
          reason: '未登录不该发一个必然 401 的请求');
    });

    test('isMuted 在数据未就绪时返回 false（宁可不显示静音）', () {
      final repo = _PerAccountMuteRepository({1: [2]});
      final auth = _FakeAuth(null);

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => auth),
        chatPreferenceRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(mutedFriendIdsProvider.notifier);

      // 宁可短暂显示「未静音」，也不要误显示「已静音」——
      // 后者会让用户以为自己的设置丢了。
      expect(notifier.isMuted(2), isFalse);
    });

    test('toggle 成功后会更新本地状态', () async {
      // 必须是**可变**列表：传 const [] 会让 fake 的 setMuted 在 add 时
      // 抛 "Cannot add to an unmodifiable list"（这坑我在写测试时踩到了）。
      final repo = _PerAccountMuteRepository({1: <int>[]});
      final auth = _FakeAuth(_user(1, '甲'));

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => auth),
        chatPreferenceRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      repo.currentUserId = 1;
      await container.read(authProvider.future);
      await container.read(mutedFriendIdsProvider.future);

      final notifier = container.read(mutedFriendIdsProvider.notifier);
      await notifier.toggle(7, true);

      expect(notifier.isMuted(7), isTrue);
      expect(repo._mutedByUser[1], contains(7), reason: '应已写入服务端');
    });
  });
}
