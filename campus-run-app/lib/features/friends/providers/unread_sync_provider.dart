import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/account_scope.dart';
import '../../../data/repositories/message_repository.dart';
import 'friend_badge_provider.dart';

/// 未读红点的**服务端同步**。
///
/// ## 为什么需要它（真实故障）
///
/// 未读红点原本是**纯内存态**：只有 WebSocket 实时到达的消息才会 +1
/// （见 [FriendBadgeNotifier.markMessage]）。于是：
///
/// ```
/// 设备被顶下线 / 离线  →  期间的消息不会到达客户端
/// 用户重新登录        →  红点是空的，看起来「没人找过我」
/// ```
///
/// 现在登录后、以及每次回到前台都会拉一次服务端的未读数来重建。
///
/// ## 为什么用「依赖 userId 的 provider」而不是 ref.listen
///
/// 第一版是在一个常驻 Notifier 的 `build()` 里 `ref.listen(authProvider)`
/// 触发同步，实测**红点出现得很慢**：登录事件与同步请求之间隔着好几层
/// 异步，时序不确定，还要额外加一个「等 600ms」的延迟避让首屏请求。
///
/// 改成 provider **直接依赖** userId 之后，「登录」就是一次普通的依赖变化：
/// Riverpod 立刻重建它，同步随即发出，没有额外的监听链路，也不需要猜延迟。
///
/// ## 与调用方的契约
///
/// [unreadSyncProvider] 仍然暴露（app.dart 里 watch 它）—— 它只是
/// 「用户维度同步」的 watcher，不持有状态。界面照旧只 watch
/// [friendBadgeProvider]。
final unreadSyncProvider = Provider<void>((ref) {
  final userId = ref.watchUserId();
  if (userId != null) {
    ref.watch(userUnreadSyncProvider(userId));
  }
});

/// 每个用户一次：进入时拉一次未读数并重建红点。
///
/// 用 family 而不是常驻单例：切账号时旧的 key 不再被 watch、
/// 自动释放；新账号立刻触发一次，天然不会把上一个账号的未读混进来。
@visibleForTesting
final userUnreadSyncProvider =
    FutureProvider.family<void, int>((ref, userId) async {
  // 不 await 任何延迟：用户反馈过「登录后很久才看到红点」，
  // 每多等一毫秒都是可见的。并发请求由服务器的连接数承受，
  // 而这个请求本身很小（一次 GROUP BY）。
  final counts = await ref.read(messageRepositoryProvider).unreadCounts();
  // ⚠️ null = 拉取失败，必须跳过：拿一次失败的结果重建红点
  // 会把用户已有的未读全部清掉。空 Map 是合法的「确实没有未读」。
  if (counts == null) return;
  // 请求期间可能已经登出/切号：不要把上一个账号的未读写进去。
  if (ref.read(authUserIdProvider) != userId) return;
  ref.read(friendBadgeProvider.notifier).mergeFromServer(counts);
});

/// 把「回到前台」也接上同步。
///
/// 只做登录后同步是不够的：App 在后台被系统冻结期间 WebSocket 收不到消息，
/// 用户切回 App 时如果不补一次，红点仍然是旧的（用户反馈过这个）。
///
/// 挂在根组件上，只监听生命周期，不持有状态。
class UnreadLifecycleSync extends ConsumerStatefulWidget {
  const UnreadLifecycleSync({super.key, required this.child, this.onResumed});

  final Widget child;

  /// 回到前台时的额外回调。
  ///
  /// 目前用于让根组件**重查更新** —— 用户装完新版本切回 App 时，
  /// 进程往往还活着（安装不会杀掉它），内存里那条「发现新版本」便一直留着。
  /// 回前台时重查一次即可自然清掉。
  final VoidCallback? onResumed;

  @override
  ConsumerState<UnreadLifecycleSync> createState() =>
      _UnreadLifecycleSyncState();
}

class _UnreadLifecycleSyncState extends ConsumerState<UnreadLifecycleSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // 更新检查与是否登录无关（未登录也该提示），所以放在登录判断之前。
    widget.onResumed?.call();

    final userId = ref.read(authUserIdProvider);
    if (userId == null) return;
    // invalidate 让它立刻重跑：等价于「回前台补一次同步」，
    // 且不必自己管并发与去重（同一 key 只会跑一份）。
    ref.invalidate(userUnreadSyncProvider(userId));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 当前登录用户 id；未登录为 null。
///
/// 单独抽出来是为了让同步逻辑只依赖「账号是否变化」，
/// 而不是订阅 authProvider 的全部字段。
final authUserIdProvider = Provider<int?>((ref) => ref.watchUserId());
