import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/app_version_repository.dart';
import '../platform/app_version.dart';

/// 读取服务端下发在任何响应上的「更新信号」。
///
/// **为什么需要它（真实故障）**：原来的更新提示靠客户端**启动时主动查一次**
/// `/api/v1/app/version`。这个模式有两个致命弱点，实际都出了事故：
///
///   1. 检查被写在登录后的主界面里 → **没登录的用户永远不知道有新版本**；
///   2. 弹窗那一步 context 用错、异常被 catch-all 吞掉 →
///      **更新弹窗从来没出现过**。
///
/// 现在服务端在**每一个** API 响应上附带 `X-App-Latest` 等响应头
/// （见后端 `AppVersionHeaderFilter`），只要 App 还连着服务器
/// （能登录、能刷列表），它就一定会收到更新信号 —— 不再依赖客户端记得去查。
///
/// 这一层与「启动时主动查一次」并存：
///   · 启动检查负责**尽早**提示（用户还没点任何东西就能看到）；
///   · 响应头负责**兜底**（万一启动那次失败/被跳过，任何后续请求都能补上）。
class VersionSignalInterceptor extends Interceptor {
  VersionSignalInterceptor({this.currentVersion});

  /// 当前 App 版本；为 null 时自行从 [PackageInfo] 读（异步，仅一次）。
  final String? currentVersion;

  /// 服务端下发最新版本的响应头。
  static const String headerLatest = 'x-app-latest';

  /// 服务端下发的强制更新下限。
  static const String headerMinSupported = 'x-app-min-supported';

  /// 服务端要求强制更新的标记。
  static const String headerUpdateRequired = 'x-app-update-required';

  /// 客户端上报自身版本的请求头（服务端据此判断是否需要 426）。
  static const String headerClientVersion = 'X-App-Version';

  /// 收到更新信号时调用。由 `app.dart` 在启动时注册。
  ///
  /// 用回调而不是让拦截器直接依赖 UI，是为了避免
  /// `dio_client.dart → app.dart → dio_client.dart` 的循环依赖。
  static void Function(AppVersionInfo info, {required bool required})? onUpdate;

  String? _resolved;
  bool _versionLoaded = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 带上自身版本，服务端才能判断是否低于强制更新下限。
    // 这是**尽力而为**：读不到就不带，服务端会当作旧客户端、只发版本头不拦截。
    final v = currentVersion ?? _resolved;
    if (v != null && v.isNotEmpty) {
      options.headers[headerClientVersion] = v;
      handler.next(options);
      return;
    }
    if (_versionLoaded) {
      handler.next(options);
      return;
    }
    _versionLoaded = true;
    // 用原生桥而不是 package_info_plus：后者在本项目里曾长期未被注册进
    // 构建，导致版本号永远是 null（见 AppVersion 的说明）。
    AppVersion.read().then((v) {
      _resolved = v;
      if (v.isNotEmpty) options.headers[headerClientVersion] = v;
      handler.next(options);
    }).catchError((Object e) {
      debugPrint('[更新] 读取自身版本失败，本次不带版本头: $e');
      handler.next(options);
    });
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _handle(response.headers, response.requestOptions.uri.toString());
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 426（强制更新）走的是 error 分支，也要处理，否则强制更新形同虚设。
    final resp = err.response;
    if (resp != null) {
      _handle(resp.headers, err.requestOptions.uri.toString());
    }
    handler.next(err);
  }

  void _handle(Headers headers, String uri) {
    final cb = onUpdate;
    if (cb == null) return;

    final latest = headers.value(headerLatest)?.trim() ?? '';
    if (latest.isEmpty) return;

    final required = headers.value(headerUpdateRequired)?.trim() == 'true';
    final minSupported = headers.value(headerMinSupported)?.trim() ?? '';

    final mine = currentVersion ?? _resolved;
    if (mine == null || mine.isEmpty) {
      // 还不知道自己的版本：启动检查那条路径会处理，这里不猜。
      return;
    }
    if (!isVersionNewer(latest, mine)) return;

    debugPrint('[更新] 服务端信号: latest=$latest 本机=$mine '
        'required=$required uri=$uri');

    cb(
      AppVersionInfo(
        latest: latest,
        minSupported: minSupported,
        changelog: '',
        apkReady: true,
        // 下载地址交给既有的版本接口提供：响应头里只放「有更新」这件事，
        // 不塞 URL（头字段不适合承载长地址，也避免与接口两处维护）。
        apkUrl: null,
        apkSizeBytes: null,
      ),
      required: required,
    );
  }
}
