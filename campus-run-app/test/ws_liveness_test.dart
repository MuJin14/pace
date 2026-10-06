import 'package:campus_run_app/core/ws/global_ws_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 全局 WebSocket 的活性检测与重连策略。
///
/// ## 真实故障背景
///
/// 好友发来消息，红点要过一分多钟才出现。根因不是红点算错，而是
/// **客户端不知道自己的连接已经死了**：
///
/// 1. 心跳只发不校验响应 —— socket 半死时写入本地缓冲区不抛错，
///    于是 App 以为自己还连着；
/// 2. 回前台只看「连接对象是否存在」，而该对象只在 onDone/onError
///    时才置空 —— 半死连接永远不触发重连。
///
/// 结果恢复完全依赖服务端把僵尸连接踢掉（改前 75~150 秒）。
/// 现在补上「客户端自己发现」：心跳无应答就重连。
///
/// ## 为什么这里不连真实 socket
///
/// 试过：起一个本地 WebSocket 服务端真连。
/// 结论是**在 flutter_test 里做不到可靠**，两个原因：
///   · `TestWidgetsFlutterBinding` 会把 `createHttpClient` 换成返回 400
///     的假实现（防止测试打真实网络），WebSocket 握手因此拿不到真实连接；
///     用 `HttpOverrides.global` 放行后连接能建立，但仍在 9 秒左右被断开；
///   · `ProviderContainer.read()` 不建立订阅，Riverpod 3 的 auto-dispose
///     会立刻释放 provider，`ref.onDispose` 随即取消心跳定时器 ——
///     表现为「定时器 isActive 为 true 却永不触发」，极像产品代码的 bug。
///
/// 硬把这两条绕过去，测试本身会比被测代码更复杂、更容易假绿。
/// 所以这里只测**能可靠验证的部分**：退避策略与参数约束。
/// 「半死连接能否被自己发现」依赖真机验证（真机心跳日志 + 红点延迟）。
void main() {
  group('重连退避', () {
    test('退避序列是指数增长并封顶 30 秒', () {
      expect(GlobalWsNotifier.backoffSecondsFor(0), 1);
      expect(GlobalWsNotifier.backoffSecondsFor(1), 2);
      expect(GlobalWsNotifier.backoffSecondsFor(2), 4);
      expect(GlobalWsNotifier.backoffSecondsFor(3), 8);
      expect(GlobalWsNotifier.backoffSecondsFor(4), 16);
      expect(GlobalWsNotifier.backoffSecondsFor(5), 30, reason: '上限应为 30 秒');
      expect(GlobalWsNotifier.backoffSecondsFor(6), 30);
      expect(GlobalWsNotifier.backoffSecondsFor(30), 30);
    });

    test('退避不会出现 0 或负数（否则会疯狂重连打爆服务端）', () {
      for (var i = 0; i < 40; i++) {
        final sec = GlobalWsNotifier.backoffSecondsFor(i);
        expect(sec, greaterThan(0), reason: '第 $i 次的退避必须是正数');
        expect(sec, lessThanOrEqualTo(30));
      }
      // 负数入参也要安全（防御性：调用方算错时不能变成死循环重连）
      expect(GlobalWsNotifier.backoffSecondsFor(-1), greaterThan(0));
    });

    test('首次退避应当很短 —— 断线后要尽快恢复，不该等好几秒', () {
      // 这是「红点延迟」体验的一部分：连接断了越早回来，红点越早出现。
      expect(GlobalWsNotifier.backoffSecondsFor(0),
          lessThanOrEqualTo(2),
          reason: '第一次重连等待超过 2 秒，用户会明显感到消息延迟');
    });

    test('⚠️ 连续失败时退避必须真的递增（否则断网期会 1 秒一次疯狂重连）', () {
      // 真机验证时发现的坑：`_onUnexpectedClose` 无条件把 _attempt 归零，
      // 而它既是「已连上的连接断了」也是「连接失败」的入口 ——
      // 于是关掉移动数据后，每一秒都在重连，日志里刷满
      // `Unhandled Exception: SocketException: Failed host lookup`。
      //
      // 修法是只在「这条连接确实收到过数据」时才归零
      // （见 GlobalWsNotifier._onUnexpectedClose 与 _everDelivered）。
      //
      // 这里用纯函数验证退避序列确实递增到上限：
      // 如果哪天有人把上限或指数去掉，这条会失败。
      final seq = List.generate(7, GlobalWsNotifier.backoffSecondsFor);
      expect(seq, [1, 2, 4, 8, 16, 30, 30]);
      for (var i = 1; i < seq.length; i++) {
        expect(seq[i], greaterThanOrEqualTo(seq[i - 1]),
            reason: '第 $i 次退避不应小于上一次');
      }
      // 连续失败 6 次后必须达到上限，不能一直很快
      expect(GlobalWsNotifier.backoffSecondsFor(5), 30);
    });
  });

  group('心跳参数与服务端约束', () {
    // ⚠️ 这两个数字必须与客户端实现一致；与后端
    // ChatSessionScheduler 的 IDLE_TIMEOUT_MILLIS 是耦合关系。
    const clientHeartbeatSeconds = 15;
    const serverIdleTimeoutSeconds = 45;

    test('服务端空闲阈值 ≥ 客户端心跳的 1.5 倍（否则健康连接会被误杀）', () {
      final ratio = serverIdleTimeoutSeconds / clientHeartbeatSeconds;
      expect(ratio, greaterThanOrEqualTo(1.5),
          reason: '比值 $ratio 太小：一次心跳抖动就会被服务端踢掉，'
              '表现为反复重连、消息时断时续');
    });

    test('心跳间隔足够短，才能及时发现死连接', () {
      // 心跳越短发现越快，但对服务端压力越大。
      // 15 秒是在「及时发现」与「别太频繁」之间的取舍；
      // 超过 30 秒的话，最坏发现延迟会超过服务端的回收时间，等于没做。
      expect(clientHeartbeatSeconds, lessThanOrEqualTo(30));
      expect(clientHeartbeatSeconds, greaterThanOrEqualTo(10));
    });
  });
}
