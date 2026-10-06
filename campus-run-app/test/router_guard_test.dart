import 'package:campus_run_app/core/router/app_router.dart';
import 'package:campus_run_app/data/models/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 路由守卫的测试。
///
/// **为什么值得单独测**：这里曾经有一个死锁 —— 网络异常时守卫强制跳回
/// `/splash`，而「修改服务器地址」的入口在 `/login` 上。结果是：
/// 服务器地址填错或换了网络后，App 永远停在启动页一个「重试」按钮上，
/// 用户无法自救，**只能卸载重装**。开发过程中反复踩到这个坑。
void main() {
  group('resolveRedirect 网络异常时不能死锁', () {
    // 模拟 authProvider 的网络错误态
    final errorState = AsyncError<dynamic>(
      Exception('网络连接失败'),
      StackTrace.empty,
    );

    test('错误态下允许停留在启动页（展示重试）', () {
      expect(resolveRedirect(errorState, '/splash'), isNull);
    });

    test('错误态下允许进入登录页（这里有改地址入口）', () {
      expect(resolveRedirect(errorState, '/login'), isNull);
    });

    test('错误态下允许进入服务器设置页（唯一的自救出口）', () {
      expect(resolveRedirect(errorState, '/server-setting'), isNull);
    });

    test('错误态下访问业务页会被送去登录页（而不是锁死在启动页）', () {
      // 关键：返回 /login 而不是 /splash —— 登录页才有改地址入口
      expect(resolveRedirect(errorState, '/home'), '/login');
      expect(resolveRedirect(errorState, '/leaderboard'), '/login');
      expect(resolveRedirect(errorState, '/friends'), '/login');
      expect(resolveRedirect(errorState, '/start-run'), '/login');
    });

    test('错误态下注册页也被送去登录页', () {
      expect(resolveRedirect(errorState, '/register'), '/login');
    });

    test('错误态下协议页仍要可达', () {
      // 真实 bug：登录页上有《用户协议与隐私政策》入口，
      // 但未登录（或网络异常）时点它会被守卫弹回登录页 ——
      // 用户根本读不到条文，只能盲勾「已同意」，
      // 这既不合理也过不了应用商店审核。
      expect(resolveRedirect(errorState, '/privacy'), isNull);
    });
  });

  group('resolveRedirect 加载中', () {
    test('加载中停留在启动页', () {
      expect(resolveRedirect(const AsyncLoading<dynamic>(), '/splash'), isNull);
    });

    test('加载中从其它页面回到启动页', () {
      expect(resolveRedirect(const AsyncLoading<dynamic>(), '/home'), '/splash');
    });
  });

  group('resolveRedirect 已登录 / 未登录', () {
    test('未登录时去登录页与注册页都放行', () {
      const notLoggedIn = AsyncData<dynamic>(null);
      expect(resolveRedirect(notLoggedIn, '/login'), isNull);
      expect(resolveRedirect(notLoggedIn, '/register'), isNull);
    });

    test('未登录时协议页必须放行（注册/登录前要能读全文）', () {
      // 这是《个人信息保护法》与应用商店审核的硬要求：
      // 注册/登录前必须能查阅协议与隐私政策。
      // 少了这条，用户只能盲勾同意 —— 而且点了条文没反应，看起来像 App 坏了。
      const notLoggedIn = AsyncData<dynamic>(null);
      expect(resolveRedirect(notLoggedIn, '/privacy'), isNull);
    });

    test('已登录时协议页也放行（从「我的」页进入）', () {
      final loggedIn = AsyncData<dynamic>({'userId': 1});
      expect(resolveRedirect(loggedIn, '/privacy'), isNull);
    });

    test('未登录时访问业务页跳登录页', () {
      const notLoggedIn = AsyncData<dynamic>(null);
      expect(resolveRedirect(notLoggedIn, '/home'), '/login');
      expect(resolveRedirect(notLoggedIn, '/profile'), '/login');
    });

    test('已登录时从登录页/启动页回首页', () {
      final loggedIn = AsyncData<dynamic>({'userId': 1});
      expect(resolveRedirect(loggedIn, '/login'), '/home');
      expect(resolveRedirect(loggedIn, '/splash'), '/home');
      expect(resolveRedirect(loggedIn, '/register'), '/home');
    });

    test('已登录时业务页正常放行', () {
      final loggedIn = AsyncData<dynamic>({'userId': 1});
      expect(resolveRedirect(loggedIn, '/home'), isNull);
      expect(resolveRedirect(loggedIn, '/start-run'), isNull);
      expect(resolveRedirect(loggedIn, '/server-setting'), isNull);
    });

  group('resolveRedirect 管理后台：非管理员不得进入', () {
    // 背景：/admin 的路由是公开可达的，而菜单入口只在「我的」页按 role 隐藏。
    // 少了守卫这一层，普通用户深链/手输 /admin 就能**看见后台界面本身**，
    // 只是每个请求都 403 —— 一屏错误，既像 App 坏了，也暴露了不该暴露的结构。

    User admin(int role) => User(
          userId: 1,
          uniqueId: '00000001',
          nickname: '测试',
          phone: '13800138000',
          role: role,
        );

    test('管理员可以进入 /admin', () {
      final auth = AsyncData<dynamic>(admin(1));
      expect(resolveRedirect(auth, '/admin'), isNull);
      // 子路径同样放行（将来加 /admin/xxx 时不会误挡）
      expect(resolveRedirect(auth, '/admin/users'), isNull);
    });

    test('普通用户被挡回首页', () {
      final auth = AsyncData<dynamic>(admin(0));
      expect(resolveRedirect(auth, '/admin'), '/home');
      expect(resolveRedirect(auth, '/admin/users'), '/home');
    });

    test('未登录访问 /admin 先去登录页（语义比直接回家清楚）', () {
      const auth = AsyncData<dynamic>(null);
      // 未登录分支先命中，返回 /login；这比「跳到 /home 又被踢回 /login」清晰
      expect(resolveRedirect(auth, '/admin'), '/login');
    });

    test('已登录但拿不到角色信息时按非管理员处理（安全默认）', () {
      // 老接口不返回 role、或状态对象类型不对时，必须**拒绝**而不是放行
      final legacyShape = AsyncData<dynamic>({'userId': 1});
      expect(resolveRedirect(legacyShape, '/admin'), '/home');
    });

    test('普通用户的其它页面不受影响', () {
      final auth = AsyncData<dynamic>(admin(0));
      expect(resolveRedirect(auth, '/home'), isNull);
      expect(resolveRedirect(auth, '/profile'), isNull);
      expect(resolveRedirect(auth, '/forgot-password'), isNull);
    });
  });
  });
}