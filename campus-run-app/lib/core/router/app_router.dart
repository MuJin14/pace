import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/pages/activity_detail_page.dart';
import '../../features/activity/pages/activity_list_page.dart';
import '../../features/activity/pages/run_result_page.dart';
import '../../features/activity/pages/start_run_page.dart';
import '../../features/admin/pages/admin_page.dart';
import '../widgets/brand_mark.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/badges/pages/badges_page.dart';
import '../../features/friends/pages/chat_history_page.dart';
import '../../features/friends/pages/chat_mute_settings_page.dart';
import '../../features/friends/pages/chat_page.dart';
import '../../features/friends/pages/friends_page.dart';
import '../../features/friends/pages/friends_search_page.dart';
import '../../features/goals/pages/goals_page.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/home/pages/main_shell.dart';
import '../../features/leaderboard/pages/leaderboard_page.dart';
import '../../features/notifications/pages/notifications_page.dart';
import '../../features/profile/pages/change_password_page.dart';
import '../../features/profile/pages/edit_profile_page.dart';
import '../../features/profile/pages/forgot_password_page.dart';
import '../../features/profile/pages/privacy_policy_page.dart';
import '../../features/settings/pages/background_message_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../features/profile/pages/user_profile_page.dart';
import '../../data/models/user.dart';
import '../../features/settings/pages/server_setting_page.dart';
import '../theme/app_theme.dart';

/// 路由守卫的纯函数形式（便于单测，避免只能靠手工点击验证）。
///
/// 返回 null 表示放行当前路径，否则返回要跳转到的路径。
///
/// ⚠️ **网络异常分支曾经是一个死锁**：原先写死 `return '/splash'`，
/// 于是服务器地址填错（或换了网络）时 App 永远停在启动页；
/// 而「修改服务器地址」的入口在登录页上 —— 用户完全无法自救，只能卸载重装。
/// 现在的规则：网络异常时放行 `/splash`、`/login`、`/server-setting`，
/// 让用户能去改地址或重新登录。**不清除登录态**，地址修好后重试即可恢复原账号。
String? resolveRedirect(AsyncValue<dynamic> auth, String loc) {
  if (auth.isLoading) {
    return loc == '/splash' ? null : '/splash';
  }

  if (auth.hasError) {
    // 这些是**用户自救入口**，网络异常时也必须可达：
    //   · `/server-setting`  —— 地址填错了才连不上，要去改；
    //   · `/forgot-password` —— 用户可能正是「登不上」才来的；
    //   · `/privacy`         —— 注册/登录前要能查阅协议，
    //     而登录页上就有协议入口，网络不好时点它却被弹回登录页，
    //     等于「强制用户盲勾同意」。（真实 bug：点协议条文打不开）
    const escapable = {
      '/splash',
      '/login',
      '/server-setting',
      '/forgot-password',
      '/privacy',
    };
    return escapable.contains(loc) ? null : '/login';
  }

  final loggedIn = auth.value != null;

  if (!loggedIn) {
    // 未登录也必须可达的页面：
    //   · `/forgot-password` —— 忘记密码的人本来就登不上；
    //   · `/privacy`         —— **注册/登录前必须能读到协议全文**，
    //     这是《个人信息保护法》与应用商店审核的硬要求。
    //     少了它，用户只能盲勾「已同意」，而点了条文又被打回登录页。
    if (loc == '/login' ||
        loc == '/register' ||
        loc == '/forgot-password' ||
        loc == '/server-setting' ||
        loc == '/privacy') {
      return null;
    }
    return '/login';
  }

  if (loc == '/login' || loc == '/register' || loc == '/splash') {
    return '/home';
  }

  // ── 管理后台：非管理员不得进入 ────────────────────────────────
  //
  // ⚠️ 这不是可靠的安全边界（服务端每个接口都有 @PreAuthorize，那才是），
  // 但少了它有两个实际问题：
  //   1. 普通用户深链/手输 `/admin` 能**看见后台界面本身**
  //      （有哪些页签、能干什么），只是每个请求都 403 —— 一屏错误，
  //      既像 App 坏了，也把不该暴露的结构暴露了；
  //   2. 只藏菜单入口是不够的：入口在「我的」页，而路由是公开可达的。
  //
  // 放在登录判定之后：未登录访问 /admin 仍然先被送去登录页（语义更清楚）。
  if (loc == '/admin' || loc.startsWith('/admin/')) {
    // 用类型判断而不是 `as dynamic`：这个函数是纯函数、被大量单测直接调用，
    // 传进来的 value 可能是任意类型（测试里就常用匿名对象），
    // 强转会在运行时抛异常，而守卫抛异常等于路由崩掉。
    final value = auth.value;
    final isAdmin = value is User && value.role == 1;
    if (!isAdmin) {
      return '/home';
    }
  }

  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) =>
        resolveRedirect(ref.read(authProvider), state.uri.path),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, __) => const HomePage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/leaderboard', builder: (_, __) => const LeaderboardPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/friends', builder: (_, __) => const FriendsPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfilePage())],
          ),
        ],
      ),
      GoRoute(path: '/activity', builder: (_, __) => const ActivityListPage()),
      GoRoute(
        path: '/start-run',
        builder: (_, state) => StartRunPage(type: (state.extra as String?) ?? 'run'),
      ),
      GoRoute(
        path: '/run-result',
        builder: (_, state) =>
            RunResultPage(activityId: state.extra as int),
      ),
      GoRoute(
        path: '/activity/:id',
        builder: (context, state) => ActivityDetailPage(
          activityId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/chat/:friendId',
        builder: (context, state) {
          // extra 兼容两种形式：纯昵称字符串（旧调用点），或
          // {'name':..., 'avatarUrl':...}，后者能让标题栏立刻显示头像不闪。
          final extra = state.extra;
          String name = '聊天';
          String? avatar;
          if (extra is String) {
            name = extra;
          } else if (extra is Map) {
            name = (extra['name'] as String?) ?? '聊天';
            avatar = extra['avatarUrl'] as String?;
          }
          return ChatPage(
            friendId: int.parse(state.pathParameters['friendId']!),
            friendName: name,
            friendAvatarUrl: avatar,
          );
        },
      ),
      // 聊天记录（微信式：聊天页右上角菜单进入）
      GoRoute(
        path: '/chat/:friendId/history',
        builder: (context, state) => ChatHistoryPage(
          friendId: int.parse(state.pathParameters['friendId']!),
          friendName: (state.extra as String?) ?? '聊天记录',
        ),
      ),
      GoRoute(path: '/friends/search', builder: (_, __) => const FriendsSearchPage()),
      GoRoute(path: '/goals', builder: (_, __) => const GoalsPage()),
      GoRoute(path: '/badges', builder: (_, __) => const BadgesPage()),
      // 合规页面：登录前即可访问（登录页与「我的」都有入口）。
      GoRoute(path: '/privacy', builder: (_, __) => const PrivacyPolicyPage()),
              GoRoute(path: '/profile/background', builder: (_, __) => const BackgroundMessagePage()),
      // 服务器地址设置：调试与换网络用，登录前即可访问
      // （换网络后可能连登录都进不去，所以入口必须在登录页）。
      GoRoute(
          path: '/server-setting',
          builder: (_, __) => const ServerSettingPage()),
      // 用户主页（看自己或看别人），类似微信的个人资料页。
      GoRoute(
        path: '/user/:id',
        builder: (context, state) => UserProfilePage(
          userId: int.parse(state.pathParameters['id']!),
        ),
      ),
      // 编辑资料：必须放在 /user/:id 之前？go_router 按静态段优先匹配，
      // '/profile/edit' 是静态路径，不会被 '/user/:id' 抢走。
      GoRoute(path: '/profile/edit', builder: (_, __) => const EditProfilePage()),
      GoRoute(
        path: '/profile/password',
        builder: (_, __) => const ChangePasswordPage(),
      ),
      GoRoute(
        path: '/chat-mute',
        builder: (_, __) => const ChatMuteSettingsPage(),
      ),
      // 忘记密码：**必须能在未登录状态访问**（用户就是登不上才来的）。
      // 路由守卫里它归在「公开路径」一类，见 resolveRedirect。
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordPage(),
      ),
      // 管理后台（找回密码 / 用户查询）。入口只在自己是管理员时显示，
      // 但服务端也会校验 —— 藏入口不是安全边界。
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminPage(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsPage(),
      ),
    ],
  );
});

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 与 App 图标、登录页、注册页同一个品牌标记。
              // 不用 Icons.directions_run —— 那是通用跑步小人，
              // 与桌面图标不是一回事，视觉上不统一。
              const BrandMark(size: 88),
              const SizedBox(height: AppSpacing.pageWide),
              const Text(
                '行迹',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppFontSize.splash,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // 网络异常时不无限转圈：给出可读原因与重试入口，
              // 令牌保持不变，重试成功即恢复登录态。
              if (auth.hasError) ...[
                const Text(
                  '网络连接失败，请检查网络后重试',
                  style: TextStyle(color: Colors.white, fontSize: AppFontSize.body),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => ref.read(authProvider.notifier).retry(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  child: const Text('重试'),
                ),
                // ⚠️ 「重新登录」是必须的出路。
                //
                // 本地残留的旧令牌会让 /me 失败，而重试会一直失败 ——
                // 结果是用户**永久卡在这一屏**，连登录页都进不去（真实发生过）。
                // 这个按钮清掉本地令牌并回到登录页，让用户能重新登入。
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: () async {
                    await ref.read(authProvider.notifier).logout();
                  },
                  child: const Text(
                    '重新登录（清空本地登录状态）',
                    style: TextStyle(color: Colors.white70, fontSize: AppFontSize.hint),
                  ),
                ),
              ] else
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
