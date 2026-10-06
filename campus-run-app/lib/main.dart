import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/friends/services/chat_notification_service.dart';

/// 全局异常日志。
///
/// **为什么需要**：真机上出现过「启动即显示网络异常，但日志里什么都没有」——
/// 没有这层兜底时，任何未捕获异常（尤其是异步链里的）都只表现为
/// 一句面向用户的「网络连接失败」，排查时完全无从下手。
///
/// 统一打上 `[崩溃]` 前缀，方便 `adb logcat | grep 崩溃` 一眼捞出来。
void _installGlobalErrorLogging() {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[崩溃] FlutterError: ${details.exception}');
    debugPrint('[崩溃] 位置: ${details.library} ${details.context}');
    debugPrint('[崩溃] 堆栈: ${details.stack}');
    previous?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[崩溃] 未捕获异步异常: $error');
    debugPrint('[崩溃] 堆栈: $stack');
    return false; // 不吞掉，保留默认行为
  };
}

void main() {
  // 通知插件初始化需要 platform channel，必须先确保绑定就绪。
  // 用 `ensureInitialized` 而不是让 runApp 触发 —— 后者在插件调用时
  // 绑定可能还没建立，会抛「Binding has not yet been initialized」。
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorLogging();
  debugPrint('[启动] main() 开始');

  // 通知初始化**不 await**：它是增强能力，失败也不该拖慢或阻断启动。
  // 服务内部已 swallow 异常并保证幂等。
  ChatNotificationService.instance.init();

  debugPrint('[启动] 即将 runApp');
  runApp(ProviderScope(
    observers: [_LoggingProviderObserver()],
    child: const App(),
  ));
  debugPrint('[启动] runApp 已调用');
}

/// 记录 provider 的错误与状态变化。
///
/// **为什么需要**：真机上出现过「启动即显示网络异常」，而 FlutterError /
/// PlatformDispatcher 的全局钩子**都抓不到** —— 因为这是 Riverpod
/// provider 内部捕获的异步异常，它会变成 `AsyncError` 而不上报全局。
/// 没有这层观测时，UI 上只有一句面向用户的「网络连接失败」，
/// 完全看不出是哪个 provider、什么原因。
///
/// ⚠️ Riverpod 3 的 `ProviderObserver` 是 `base` 类，子类必须声明
/// `final`/`base`/`sealed`；且 `providerDidFail` 的签名是
/// `(ProviderObserverContext, Object, StackTrace)`（旧版是
/// `(ProviderBase, Object, StackTrace, ProviderContainer)`）。
final class _LoggingProviderObserver extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('[崩溃] provider 失败: ${context.provider.name ?? context.provider.runtimeType}');
    debugPrint('[崩溃] 原因: $error');
    debugPrint('[崩溃] 堆栈: $stackTrace');
  }
}
