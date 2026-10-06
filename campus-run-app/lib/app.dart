import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/update/app_update_service.dart';
import 'core/widgets/update_dialog.dart';
import 'core/update/pending_update_provider.dart';
import 'core/network/version_signal_interceptor.dart';
import 'core/permissions/app_permission_service.dart';
import 'core/widgets/permission_prompt_sheet.dart';
import 'core/ws/global_ws_provider.dart';
import 'core/ws/ws_message.dart';
import 'data/repositories/app_version_repository.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/friends/providers/chat_preference_provider.dart';
import 'features/friends/providers/friend_badge_provider.dart';
import 'features/friends/providers/unread_sync_provider.dart';
import 'features/friends/providers/friend_provider.dart';
import 'features/friends/services/chat_notification_service.dart';
import 'features/friends/utils/notify_policy.dart';

/// 全局 ScaffoldMessenger，用于在无页面 context 时弹出提示（好友关系变更等）。
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();



/// 「本次进程是否已检查过更新」。
///
/// ⚠️ 用 provider 而不是 `static bool` 字段，原因有两个：
///
///   1. **可测**：widget 测试里 static 状态会跨用例泄漏 ——
///      第一个用例把它置为 true，后面的用例就全被跳过，
///      于是「未登录也会检查更新」这条断言永远测不到真实行为
///      （写这条测试时正好踩到：4 个用例只过了 1 个）；
///   2. 语义正确：这是「一次进程内的一次性动作」，
///      不该挂在某个 widget 实例上（实例会重建），
///      也不该是全局可变静态状态。
final updateCheckedProvider =
    NotifierProvider<UpdateCheckedNotifier, bool>(UpdateCheckedNotifier.new);

class UpdateCheckedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// 标记「本次进程已检查过」，返回 true 表示这是第一次。
  ///
  /// 用「读 + 写」合成一个方法，避免调用方写成
  /// `if (read) return; state = true;` 这种两步操作 ——
  /// 两步之间若再有一次调用就会重复请求。
  bool markChecked() {
    if (state) return false;
    state = true;
    return true;
  }
}

/// 根 Widget：挂载全局 WebSocket 并分发好友事件到各 provider / 红点 / 通知。
///
/// ⚠️ 同时负责**应用级**的「检查更新」。
///
/// 这里曾经是 [MainShell] 的职责，而 MainShell 挂在登录后的
/// `StatefulShellRoute` 上 —— 于是整条链路变成：
///
///     启动 → 未登录 → 登录页 → 登录成功 → 主界面 → 才会检查更新
///
/// 结果是**没登录就永远不知道有新版本**（用户反馈「到了新版本没有自动更新，
/// 之前也没有」）。而版本接口本身是公开的（不带 token 也返回 200），
/// 根本不需要登录态。
///
/// 更新检查属于应用级行为，不该依赖「用户走到了哪一页」。
/// 现在放在根组件里，与登录状态和路由完全解耦。
class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  /// 弹窗展示中标记：避免与其它弹窗叠加（同时弹两个会抛异常）。
  bool _updateDialogOpen = false;

  /// 已经提示过的版本号，避免每次请求都弹一次。
  String? _promptedVersion;

  /// 启动权限检查的延迟计时器。
  ///
  /// ⚠️ 必须持有并在 `dispose` 里取消。
  ///
  /// 第一版用 `await Future.delayed(...)` 直接等，没有句柄可取消 ——
  /// 结果是：App 被销毁后这个延迟仍会到期，进而在一个已经没有 Overlay 的
  /// 上下文里尝试弹「权限说明卡」。
  /// 而且 widget 测试会直接断言失败：
  /// `A Timer is still pending even after the widget tree was disposed.`
  Timer? _permissionTimer;

  @override
  void initState() {
    super.initState();
    // 服务端在**每个**响应上都会带更新信号（见 VersionSignalInterceptor）。
    // 注册回调后，即使启动那次检查失败/被跳过，任何一次后续请求都能补上提示。
    VersionSignalInterceptor.onUpdate = (info, {required required}) {
      _promptForVersion(info.latest, force: required);
    };
    // 首帧之后再查：此时 Navigator/Overlay 已就绪。
    // 在 initState 里直接 showDialog 会因为还没有可用的 Overlay 而报错。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      _ensurePermissions();
      // 回收历史遗留的安装包。
      //
      // 用户反馈「之前下载多余的可以删掉了」—— 修复「重试会重下」之前，
      // 每次中断都会留下一个 54MB 的包，而用户没有任何入口去清理。
      // 这里在启动时收一次；只有存放超过 6 小时的包才会被删，
      // 避免误删「刚下好、正等着用户去授权」的那个。
      AppUpdateService.instance.cleanupStalePackage();
    });
  }

  /// 启动时统一补齐权限。
  ///
  /// **为什么必须前置**（用户的原始反馈）：
  ///   · 通知权限原先只在进聊天页时申请 → 不进聊天页就永远拿不到 →
  ///     退到后台收不到任何消息。这是个死循环；
  ///   · 定位权限原先只在点「开始跑步」时申请 → 用户已经站在操场上
  ///     才被要求授权，此时拒绝或翻设置体验最差。
  ///
  /// 现在首帧后统一处理：**先弹一张说明卡讲清用途，再弹系统框**。
  /// 直接弹系统框用户不知道要干什么、拒绝率更高 —— 那个顾虑是对的，
  /// 但解法是「先说明」，不是「推迟到相关页面」。
  ///
  /// 延迟 1.2 秒是为了不打断冷启动（启动动画 + 首次数据加载）。
  void _ensurePermissions() {
    // 用可取消的 Timer，而不是 `await Future.delayed`：
    // 见 _permissionTimer 的说明。
    _permissionTimer?.cancel();
    _permissionTimer = Timer(const Duration(milliseconds: 1200), () {
      _runPermissionCheck();
    });
  }

  Future<void> _runPermissionCheck() async {
    if (!mounted) return;
    try {

      final svc = AppPermissionService.instance;
      // 同一进程内只问一次：用户点了「暂不」后不该每次回前台都再弹。
      if (svc.alreadyAsked) return;

      final gaps = await svc.gaps();
      if (!gaps.any || !mounted) return;

      final ctx = _router?.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;

      await PermissionPromptSheet.show(ctx, gaps);
    } catch (e) {
      // 权限只是增强能力，任何失败都不该影响使用
      debugPrint('[权限] 启动检查失败（已忽略）: $e');
    }
  }

  /// 收到「有新版本」的信号后**记录待更新**（不是弹窗）。
  ///
  /// 响应头里只有版本号（头字段不适合塞长 URL），所以这里再从版本接口
  /// 取一次完整信息（含 apkUrl / 体积 / 更新说明）——
  /// 直接拿响应头构造 [AppVersionInfo] 会让 `apkUrl` 为 null，
  /// 用户点「立即更新」会发现按钮没反应。
  ///
  /// 与 [_checkForUpdate] 同样：默认只放进通知提醒，
  /// **强制更新**（`force == true`，即服务端要求）才立即弹窗。
  Future<void> _promptForVersion(String latest, {required bool force}) async {
    if (!mounted) return;
    if (_promptedVersion == latest) return; // 同一个版本只处理一次

    try {
      final repo = ref.read(appVersionRepositoryProvider);
      final full = await repo.fetchLatest();
      if (!full.hasDownloadableUpdate || !mounted) return;
      if (_promptedVersion == full.latest) return;
      _promptedVersion = full.latest;

      ref.read(pendingUpdateProvider.notifier).found(full, mandatory: force);
      if (force) {
        debugPrint('[update] 服务端要求强制更新，立即弹窗：${full.latest}');
        await _showDialog(full, force: true);
      } else {
        debugPrint('[update] 服务端提示新版本 ${full.latest}，已放入通知提醒');
      }
    } catch (e) {
      debugPrint('[update] 拉取版本详情失败（已忽略）: $e');
    }
  }

  Future<void> _showDialog(AppVersionInfo info, {bool force = false}) async {
    if (_updateDialogOpen) return;
    final ctx = _router?.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    _updateDialogOpen = true;
    try {
      await UpdateDialog.show(ctx, info, force: force);
    } finally {
      _updateDialogOpen = false;
    }
  }

  /// 静默检查更新：**任何失败都不打扰用户**。
  ///
  /// ## 为什么不再直接弹窗
  ///
  /// 原先这里发现新版本就 `UpdateDialog.show(...)`。实测有两个问题：
  ///
  ///   1. **打扰** —— 冷启动弹「要更新吗」，而用户此刻往往只想看一眼步数；
  ///   2. **容易被误关掉** —— 用户条件反射点「稍后」，之后再也没有入口，
  ///      更新提示等于形同虚设。
  ///
  /// 现在改为把结果写进 [pendingUpdateProvider]：右上角铃铛出现红点，
  /// 用户点进通知页看到「发现新版本」那一条，点它才弹对话框。
  /// 入口一直留在通知页里，不会被误关掉。
  ///
  /// **唯一例外是强制更新**（本机低于服务端 minSupported）：
  /// 那种情况下继续用旧版本会出问题（接口不兼容等），不能等用户自己发现，
  /// 所以仍然立即弹窗，且弹窗不可关闭。
  /// [force] 为 true 时跳过「每进程只查一次」的限制。
  /// 用于**回到前台**时重查 —— 用户很可能刚装完新版本切回来。
  Future<void> _checkForUpdate({bool force = false}) async {
    if (!force && !ref.read(updateCheckedProvider.notifier).markChecked()) {
      return;
    }

    try {
      final current = await AppUpdateService.instance.currentVersion();
      final info = await AppUpdateService.instance.checkForUpdate(
        ref.read(appVersionRepositoryProvider),
        current,
      );
      if (!mounted) return;

      if (info == null) {
        // ⚠️⚠️ 「没有新版本」时**必须清掉**之前记下的待更新状态。
        //
        // 用户反馈：「下载了新版本，提示还在」。
        // 原来的代码在这里直接 return，于是 pendingUpdateProvider 里那条
        // 记录**永远留着** —— 因为没有任何地方调用过它的 clear()。
        // 表现就是：装完新版本、通知里的「发现新版本」照旧显示，
        // 铃铛红点也照旧亮着。
        ref.read(pendingUpdateProvider.notifier).clear();
        return;
      }

      final mandatory = _isMandatory(info, current);
      ref.read(pendingUpdateProvider.notifier).found(info, mandatory: mandatory);

      if (mandatory) {
        debugPrint('[update] 低于强制更新下限，立即弹窗：${info.latest}');
        await _showDialog(info, force: true);
      } else {
        debugPrint('[update] 发现新版本 ${info.latest}，已放入通知提醒');
      }
    } catch (e) {
      debugPrint('[update] 检查更新异常（已忽略）: $e');
    }
  }

  /// 是否属于「必须更新」：本机版本低于服务端下发的下限。
  ///
  /// 下限为空串表示服务端不做强制（默认情况）。
  bool _isMandatory(AppVersionInfo info, String current) {
    if (info.minSupported.isEmpty || current.isEmpty) return false;
    return isVersionNewer(info.minSupported, current);
  }

  /// 缓存当前 GoRouter 实例。
  ///
  /// dialog 需要它来拿 `navigatorKey` —— 见 [_checkForUpdate] 里的说明。
  GoRouter? _router;

  @override
  void dispose() {
    _permissionTimer?.cancel();
    _permissionTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(globalWsProvider);
    // 未读红点的服务端同步：登录后与回到前台各拉一次，
    // 补上「离线期间收到的消息登录后没有红点」的缺口。
    ref.watch(unreadSyncProvider);
    ref.listen(wsMessageStreamProvider, (_, next) {
      final ws = next.value;
      if (ws != null) {
        _handleWsMessage(ref, ws);
      }
    });

    _router = ref.watch(routerProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // ⚠️ 状态栏样式必须在这里全局设一次。
      //
      // 只设 `AppBarTheme.systemOverlayStyle` 是不够的：那只在有 AppBar 的
      // 页面上生效，而登录页/注册页/启动页都**没有 AppBar** ——
      // 于是系统沿用默认（深色主题下是浅色图标），白字画在奶油白背景上，
      // 时间与电量几乎看不见。
      // 以前登录页顶部是一大块橙色渐变，白图标正好可见，把这个问题掩盖了。
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Android
        statusBarBrightness: Brightness.light, // iOS
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      // 包一层生命周期监听：回到前台时补一次未读同步
      // （App 在后台被冻结期间 WebSocket 收不到消息，不补的话红点是旧的）。
      child: UnreadLifecycleSync(
        // 回到前台时强制重查更新：用户很可能刚装完新版本切回来，
        // 而安装过程不会杀掉本进程 —— 内存里那条「发现新版本」会一直留着。
        // 重查一次、发现已是最新版，就会自动清掉（见 _checkForUpdate）。
        onResumed: () => _checkForUpdate(force: true),
        child: MaterialApp.router(
          title: '行迹',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          scaffoldMessengerKey: scaffoldMessengerKey,
          routerConfig: _router,
        ),
      ),
    );
  }
}

void _handleWsMessage(WidgetRef ref, WsMessage ws) {
  // 诊断：确认 WS 事件真的走到了根处理器。
  // ignore: avoid_print
  switch (ws.type) {
    case WsEventType.friendRequest:
      ref.invalidate(friendRequestsProvider);
    case WsEventType.friendAccepted:
      ref.invalidate(friendListProvider);
      final nickname = ws.data?['friendNickname'] as String? ?? '';
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('你和 $nickname 已成为好友')),
      );
    case WsEventType.friendDeleted:
      ref.invalidate(friendListProvider);
    case WsEventType.message:
      _handleIncomingMessage(ref, ws);
    default:
      break;
  }
}

/// 处理收到的聊天消息：红点 +（按策略）震动与系统通知。
///
/// ## 红点规则（用户定的，也是更稳的那一套）
///
/// > **只在你点进会话之后红点才消失；否则一来新消息就显示红点。**
///
/// 也就是说红点只由两件事决定：
///   1. 来了新消息 → 立刻 +1；
///   2. 你点进了那个会话 → 清零。
///
/// ### 为什么不再用「是不是正在看这个会话」来决定红点
///
/// 原来加完红点后会再判一次 `action == none`（= 正在看这个会话）把它清掉。
/// 那样红点是否显示，取决于 `currentChatFriendId` 这个状态**准不准** ——
/// 而它恰恰出过问题：只在进入会话时被 set，从来没被清空，于是
/// App 会一直以为你还在看那个会话，之后所有消息的红点都被立刻清掉。
///
/// 现在红点不再依赖那个状态：
///   · 「正在看这个会话」的判定**只用于是否弹通知/震动**，不影响红点；
///   · 红点清零只发生在「真的点进去了」（chat_page 的 initState 调 clearFriend）。
///
/// 顺带的好处是语义更直白：红点表示「这条你还没看」，
/// 而不是「App 觉得你可能没看」。
///
/// ### 自己发的消息
///
/// 多端登录时自己发的消息会同步回来，不加红点也不提醒 ——
/// 这条仍然保留（否则会在自己手机上给自己弹通知）。
void _handleIncomingMessage(WidgetRef ref, WsMessage ws) {
  final data = ws.data;
  // ignore: avoid_print
  if (data == null) return;

  final senderId = (data['senderId'] as num?)?.toInt();
  // ignore: avoid_print
  if (senderId == null) return;

  // 上下文快照：全部取「此刻」的值，之后不再读 provider ——
  // 否则异步动作期间用户切了页面，判断会与实际状态不一致。
  //
  // ⚠️⚠️ 这里读的是**整个 auth 值**，不是只取 userId —— 因为要区分
  // 「尚未取到登录用户」与「登录用户就是 0 号」。
  //
  // 曾经写成 `.userId ?? 0` 再判 `myUserId == 0` 当「未登录」，
  // 那是**基于「id 从 1 开始」的错误前提**。迁移 006 把管理员重排为
  // id 0/1/2 之后，0 号用户（Mujin）收到的每条实时消息都被
  // 当成「未登录」而**静默丢弃** —— 红点不亮、通知不弹，
  // 且只在这一个人的手机上表现为故障。这就是「消息能收到但红点不亮」的根因。
  final authValue = ref.read(authProvider).value;
  final currentChat = ref.read(currentChatFriendIdProvider);
  final muted = ref.read(mutedFriendIdsProvider).value ?? const <int>{};

  // 真的还没登录（或登录态尚未加载完）：没有「我的账号」，不处理。
  if (authValue == null) return;
  final myUserId = authValue.userId;

  // 自己发的消息（多端登录时会同步回来）：不提醒、也不加红点。
  if (senderId == myUserId) return;

  // ── 红点：无条件加 ────────────────────────────────────────────
  //
  // 必须在「正在看这个会话」的判断**之前**无条件加，不能因为
  // action == none 就跳过 —— 否则就又回到「依赖 currentChat 準不准」的老路。
  // 真正清零的责任在 chat_page：点进会话时调 clearFriend。
  ref.read(friendBadgeProvider.notifier).markMessage(friendId: senderId);

  // ── 提醒方式：这里才用「是不是正在看这个会话」 ──────────────────
  final action = decideNotifyAction(NotifyContext(
    senderId: senderId,
    myUserId: myUserId,
    currentChatFriendId: currentChat,
    mutedFriendIds: muted,
    appInForeground: true,
  ));

  if (action == NotifyAction.none) {
    // 正在看这个会话：消息已经在眼前，不再弹通知/震动。
    // ⚠️ 但**不**清红点 —— 用户可能马上就要退出这个会话，
    // 那时红点应当还在（下次点进来才清）。
    ChatNotificationService.instance.cancelFor(senderId);
    return;
  }

  if (action == NotifyAction.badgeOnly) {
    // 免打扰：红点已加，不震动不弹通知
    return;
  }

  final type = (data['type'] as num?)?.toInt() ?? 1;
  final content = data['content'] as String?;
  // 昵称**优先用消息里带的**：好友列表要等用户进过社区页才加载，
  // 冷启动后收到的第一条消息查不到昵称，通知就只剩「新消息」。
  final fromMessage = (data['senderNickname'] as String?)?.trim();
  final nickname = (fromMessage != null && fromMessage.isNotEmpty)
      ? fromMessage
      : _senderNickname(ref, senderId);

  final (:title, :body) = buildNotificationContent(
    senderNickname: nickname,
    content: content,
    type: type,
  );
  ChatNotificationService.instance.showMessage(
    senderId: senderId,
    title: title,
    body: body,
  );
}

/// 取发送方昵称：优先用好友列表缓存，缺失时用兜底文案。
///
/// 不为此单独请求 profile：通知是即时动作，多一次网络往返会让通知延迟，
/// 而且请求失败时通知就没了 —— 不划算。
String _senderNickname(WidgetRef ref, int senderId) {
  try {
    final friends = ref.read(friendListProvider).value ?? const [];
    for (final f in friends) {
      if (f.userId == senderId) return f.nickname;
    }
  } catch (_) {
    // 好友列表尚未加载：不影响通知，用兜底文案
  }
  return '好友';
}
