import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/server_address_storage.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';
import 'version_signal_interceptor.dart';

/// 当前生效的 API 基础地址（**同步可得** + 支持运行时修改）。
///
/// 优先级：本地保存的地址 > 编译期 `--dart-define` > 平台默认值。
///
/// ⚠️ **这里必须同步返回，不能用 AsyncNotifier。**
///
/// 曾经用 `AsyncNotifierProvider` 先 `await SharedPreferences`，导致：
///   - 首帧 `currentBaseUrl()` 拿到 null → 退回默认值
///   - 而启动链路（authProvider 读 token → 读地址 → 发 /me）要串好几次异步 I/O
///   - 结果是 **启动页明显多转好几秒**
///
/// 正确做法：**编译期地址本来就是同步可得的**，本地覆写只是可选增强。
/// 所以先用同步默认值立即就绪，再在后台把本地覆写读出来应用，
/// 启动路径完全不阻塞。
/// 已经不再使用的服务器地址前缀。
///
/// **为什么需要这个列表（真实事故）**：
/// 1.2.0 / 1.3.0 把编译期地址改成了 `https://api.hibiscus.wiki:8443`。
/// 后来那个域名被改成「仅 DNS」，导致手机上连的是服务器裸 IP，
/// 看到的是一张**Android 不信任的 Cloudflare 源站证书**，直接拒绝连接，
/// App 显示「网络问题」。
///
/// 而本地保存的地址**优先级高于编译期地址**，所以即使用户装了新包，
/// 只要旧地址还留在 shared_preferences 里，就依然连不上 ——
/// 表现为「更新后依然进不去」，用户完全无法自救。
///
/// 修法：启动时如果发现保存的地址是这些已知失效的地址，就**直接丢弃**，
/// 回落到编译期地址。只匹配明确的废弃前缀，不动用户自己填的其它地址。
const List<String> _retiredServerAddressPrefixes = <String>[
  'https://api.hibiscus.wiki', // 1.2.0–1.3.0 用过，现已不可靠
  'http://api.hibiscus.wiki',
];

bool _isRetiredAddress(String address) {
  final a = address.trim().toLowerCase();
  return _retiredServerAddressPrefixes.any(a.startsWith);
}

final serverBaseUrlProvider =
    NotifierProvider<ServerBaseUrlNotifier, String>(ServerBaseUrlNotifier.new);

class ServerBaseUrlNotifier extends Notifier<String> {
  @override
  String build() {
    // 立即返回同步默认值；随后异步加载本地覆写（通常是首次运行时的一两次）
    Future.microtask(_loadOverride);
    return AppConfig.baseUrl;
  }

  Future<void> _loadOverride() async {
    try {
      final saved = await ref.read(serverAddressStorageProvider).read();
      if (saved == null || saved.isEmpty) return;

      if (_isRetiredAddress(saved)) {
        // 丢弃失效地址并清除持久化，让后续启动也走编译期地址
        debugPrint('[网络] 已保存的地址 $saved 已废弃，回落到 ${AppConfig.baseUrl}');
        await ref.read(serverAddressStorageProvider).clear();
        if (state != AppConfig.baseUrl) state = AppConfig.baseUrl;
        return;
      }

      if (saved != state) {
        state = saved;
      }
    } catch (_) {
      // 本地存储不可用不影响使用，保持默认地址
    }
  }

  /// 保存并立即生效。传 null / 空串表示恢复默认。
  /// 返回 false 表示地址不合法。
  Future<bool> save(String? address) async {
    if (address == null || address.trim().isEmpty) {
      await ref.read(serverAddressStorageProvider).clear();
      state = AppConfig.baseUrl;
      return true;
    }
    final normalized = normalizeServerAddress(address);
    if (normalized == null) return false;
    await ref.read(serverAddressStorageProvider).write(normalized);
    state = normalized;
    return true;
  }
}

/// 读取当前地址（同步，永远有值）。
String currentBaseUrl(Object ref) => _readBase(ref) ?? AppConfig.baseUrl;

String? _readBase(Object ref) {
  try {
    if (ref is Ref) return ref.read(serverBaseUrlProvider);
    if (ref is WidgetRef) return ref.read(serverBaseUrlProvider);
  } catch (_) {
    // provider 尚未初始化时退回默认值
  }
  return null;
}

/// 把 baseUrl 同步为「当前地址」的拦截器。
///
/// **为什么需要它**：`BaseOptions.baseUrl` 在构造 Dio 时就固定了，
/// 用户在设置页改了地址后，已存在的 Dio 实例（以及别处缓存的引用）不会自动更新。
/// 每次请求前重写一次，最省事且不会留下陈旧引用。
///
/// ⚠️ **实现要点：必须同时清空 `queryParameters`。**
///
/// Dio 的 `RequestOptions.uri`（options.dart）是这样拼的：
///
/// ```dart
/// String url = path;                       // 若已是 http(s) 开头则不再拼 baseUrl
/// final query = urlEncodeQueryMap(queryParameters, listFormat);
/// if (query.isNotEmpty) url += (url.contains('?') ? '&' : '?') + query;
/// ```
///
/// 也就是说 **query 是无条件追加的**。只改 `path` 而不清 `queryParameters`，
/// 参数仍会被拼第二遍，URL 变成
/// `?scope=daily&type=1&...&scope=daily&type=1&...`；
/// Spring 把同名参数绑定成 `"daily,daily"`，
/// `LeaderboardScope.fromCode("daily,daily")` 返回 null → 400「榜单维度不合法」，
/// 前端只显示一句「参数错误」。（这个 bug 真实发生过，排查了很久。）
class BaseUrlInterceptor extends Interceptor {
  BaseUrlInterceptor(this._ref);

  final Ref _ref;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final base = currentBaseUrl(_ref);
    final parsed = Uri.parse(base);
    // 把 path + query 拼成完整 URL；scheme/host/port 换成当前地址
    final full = Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: options.uri.path,
      queryParameters:
          options.uri.queryParameters.isEmpty ? null : options.uri.queryParameters,
    );

    options.baseUrl = '';
    options.path = full.toString();
    // 关键：query 已经并进 path，必须清空，否则 Dio 会再追加一次
    options.queryParameters = const {};

    // 排查网络问题时必须能看到「最终请求的真实 URL」——
    // 否则只会看到一句「网络连接失败」，无法区分是地址拼错还是真连不通。
    //
    // body 也要打：真机上出现过「注册报 400 参数错误，但 curl 同样的
    // 参数能成功」—— 没有 body 日志时完全无法判断是内容不对、
    // 还是 Content-Type / 编码不对。
    final bodyPreview = options.data == null
        ? ''
        : '  body=${options.data}  content-type=${options.contentType}';
    debugPrint('[网络] 请求 → ${options.method} ${options.path}$bodyPreview');
    handler.next(options);
  }

  /// 连不上时自动回退到编译期地址。
  ///
  /// **为什么需要**：地址来自三处（本地保存 / 编译期 / 平台默认），
  /// 任何一处失效都会让 App 完全打不开，而用户看到的只是一句「网络问题」，
  /// 既不知道原因、也没有自救入口 —— 1.3.0 就发生过这件事。
  ///
  /// 只在**连接类错误**时回退（超时 / DNS / 连接被拒 / 证书被拒），
  /// 业务错误（4xx/5xx）不动：那说明服务器是通的，换地址没有意义。
  ///
  /// 回退**不写入本地存储**：用户可能是主动指向另一台服务器，
  /// 只是那台临时不可用，不应该永久改掉他的选择。
  /// 同一条请求只回退一次，避免在两个地址之间来回打转。
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final fallback = AppConfig.baseUrl;
    final current = currentBaseUrl(_ref);
    final alreadyTried = err.requestOptions.extra['triedFallback'] == true;

    final isConnectivityIssue = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout;

    if (!isConnectivityIssue || alreadyTried || current == fallback) {
      handler.next(err);
      return;
    }

    debugPrint('[网络] $current 连不上（${err.type}），回退到 $fallback 重试');

    final retry = err.requestOptions;
    retry.extra['triedFallback'] = true;
    // 用绝对地址覆盖（path 在 onRequest 里已被改写成完整 URL）
    final parsed = Uri.parse(fallback);
    final original = Uri.parse(retry.path);
    retry.path = Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: original.path,
      queryParameters: original.queryParameters.isEmpty ? null : original.queryParameters,
    ).toString();

    _ref.read(dioProvider).fetch(retry).then(
          (r) => handler.resolve(r),
          onError: (Object e) => handler.next(err),
        );
  }
}

/// 把「哪个请求失败、失败原因是什么」打到日志。
///
/// **为什么必要**：UI 上只会显示一句「参数错误」或「网络连接失败」，
/// 排查时无法知道是哪个接口、后端返回了什么。缺少这层日志时，
/// 只能靠猜（本次排查就因此绕了很久）。
class ErrorLogInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final body = err.response?.data;
    debugPrint('[网络] 失败 ← ${err.requestOptions.uri} '
        'type=${err.type} status=$status body=$body');
    // 响应头也要打：真机上出现过「请求没到自己的服务器，却收到了一个
    // {"code":400} 响应」——只有状态码和 body 时无法判断是谁回的。
    // Server / Via / X-Powered-By 这类头能直接指出响应方。
    if (err.response != null) {
      final h = err.response!.headers;
      debugPrint('[网络] 响应头 server=${h.value('server')} '
          'via=${h.value('via')} ct=${h.value('content-type')} '
          'powered=${h.value('x-powered-by')} '
          'date=${h.value('date')} len=${h.value('content-length')}');
      debugPrint('[网络] 响应头全部: ${h.map}');
    }
    handler.next(err);
  }
}

/// 幂等请求的自动重试。
///
/// **为什么需要（真实故障）**：用户反馈「进聊天记录，第二次失败、第三次成功、
/// 第四次又失败」—— 典型的偶发失败。
///
/// 原因是这台服务器的上行带宽只有约 0.2–0.46 MB/s，而
/// `receiveTimeout` 只有 10 秒，**且整个链路没有任何重试**。
/// 网络抖一下、或者服务端当时正好在压一个较大的查询，
/// 用户就直接看到「聊天记录加载失败」，只能手动再点一次。
///
/// 什么时候值得重试：
///   · 连接/读写超时、连接被重置 —— 纯网络抖动，重试通常就好了；
///   · 502/503/504 —— 网关或上游临时不可用。
///
/// 什么时候**绝不能**重试：
///   · 4xx（除 408/429）—— 参数或权限问题，重试一百次也一样，
///     只会浪费用户流量和时间；
///   · 已带 `Authorization` 的 POST/PUT/DELETE —— 大多数不幂等
///     （重复发消息、重复提交运动记录都是真实后果）。
///     所以默认只重试 GET/HEAD/OPTIONS。
class RetryInterceptor extends Interceptor {
  RetryInterceptor(
    this._dioProvider, {
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
  });

  final Dio Function() _dioProvider;
  final int maxAttempts;
  final Duration baseDelay;

  static const String _attemptKey = '_campusRunAttempt';

  static const Set<String> _idempotentMethods = {'GET', 'HEAD', 'OPTIONS'};

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_attemptKey] as int?) ?? 1;

    if (attempt >= maxAttempts || !_shouldRetry(err, options)) {
      handler.next(err);
      return;
    }

    // 指数退避：400ms → 800ms。加抖动避免同一时刻的请求整齐重试。
    final delay = Duration(
      milliseconds: baseDelay.inMilliseconds * (1 << (attempt - 1)) +
          (DateTime.now().microsecond % 150),
    );
    debugPrint('[网络] 第 $attempt 次失败（${err.type}），'
        '${delay.inMilliseconds}ms 后重试 ← ${options.uri}');
    await Future<void>.delayed(delay);

    options.extra[_attemptKey] = attempt + 1;
    try {
      final response = await _dioProvider().fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      // 递归交给本拦截器继续处理（attempt 已自增，到上限自然停止）
      handler.next(e);
    }
  }

  bool _shouldRetry(DioException err, RequestOptions options) {
    // 只重试幂等方法。带 Authorization 的写请求一律不重试 ——
    // 重复发消息 / 重复上传运动记录都是用户能直接看到的后果。
    final method = options.method.toUpperCase();
    if (!_idempotentMethods.contains(method)) return false;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = err.response?.statusCode ?? 0;
        // 502/503/504 是网关或上游临时不可用；
        // 408/429 是明确「稍后再试」。
        return code == 502 || code == 503 || code == 504 ||
            code == 408 || code == 429;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return false;
    }
  }
}

/// Dio 单例 provider：全项目复用同一个客户端与拦截器链。
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: currentBaseUrl(ref),
      connectTimeout: const Duration(seconds: 10),
      // 10 秒对「列表接口」够，但对**上传/下载大图**偏紧：
      // 服务器上行只有约 0.2–0.46 MB/s，一张 2MB 的图要 5–10 秒，
      // 正好卡在超时边缘。所以这里放宽到 20 秒，配合自动重试一起兜底。
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );
  // 顺序重要：先重写 baseUrl，再走鉴权，保证 401 刷新也用到正确地址
  dio.interceptors.add(BaseUrlInterceptor(ref));
  dio.interceptors.add(AuthInterceptor(ref.read(tokenStorageProvider)));
  // 鉴权之后、日志之前：401 刷新不算「可重试的网络故障」，
  // 让 AuthInterceptor 先处理完，这里只兜网络抖动与 5xx。
  //
  // ⚠️ 直接传 `dio` 而不是 `() => ref.read(dioProvider)` —— 后者会让
  //    dioProvider 依赖自己，形成顶层循环，Dart 无法推断类型（实测报错
  //    "depends on itself through the cycle"）。实例本身就是同一个。
  dio.interceptors.add(RetryInterceptor(() => dio));
  // 更新信号：读服务端在**每个**响应上带的 X-App-Latest 等头。
  // 放在最后——它只读响应头，不参与请求改写，也不该影响重试判定。
  dio.interceptors.add(VersionSignalInterceptor());
  // 放最后：前面的拦截器都已处理完，这里记录的是最终失败原因
  dio.interceptors.add(ErrorLogInterceptor());
  debugPrint('[网络] 初始地址 ${currentBaseUrl(ref)}');
  return dio;
});
