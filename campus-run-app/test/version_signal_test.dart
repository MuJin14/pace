import 'package:campus_run_app/core/network/version_signal_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 服务端「更新信号」响应头的解析。
///
/// **为什么值得单独测**：这是「服务端主动推送更新」这条链路的入口。
/// 它一旦静默失效（头名拼错、大小写没处理、判定反了），
/// 表现就是「有新版本但从不提示」——而这正是用户报过的问题，
/// 而且没有任何报错，极难定位。
///
/// 这里用真实的 [Response]/[DioException] 组装，覆盖响应与错误两条分支：
/// 强制更新走的是 **426**，也就是 error 分支 —— 只测 onResponse 会漏掉它。
void main() {
  late List<({String latest, bool required})> received;

  setUp(() {
    received = [];
    VersionSignalInterceptor.onUpdate = (info, {required required}) {
      received.add((latest: info.latest, required: required));
    };
  });

  tearDown(() => VersionSignalInterceptor.onUpdate = null);

  /// 造一个带版本头的响应。
  Response<dynamic> resWith(Map<String, String> headers) {
    final ro = RequestOptions(path: '/api/v1/user/me', baseUrl: 'http://x');
    return Response<dynamic>(
      requestOptions: ro,
      statusCode: 200,
      headers: Headers.fromMap(
        headers.map((k, v) => MapEntry(k, [v])),
      ),
    );
  }

  group('响应头解析', () {
    test('latest 比本机新 -> 触发回调', () async {
      final i = VersionSignalInterceptor(currentVersion: '1.7.2');
      final futures = <Future<void>>[];
      final handler = _CapturingHandler();
      i.onResponse(
        resWith({
          VersionSignalInterceptor.headerLatest: '1.7.3',
          VersionSignalInterceptor.headerUpdateRequired: 'true',
        }),
        handler,
      );
      expect(handler.errored, isNull);
      expect(received.length, 1, reason: '应当识别出新版本');
      expect(received.first.latest, '1.7.3');
      expect(received.first.required, isTrue);
      expect(futures, isEmpty);
    });

    test('latest 与本机相同 -> 不触发', () {
      final i = VersionSignalInterceptor(currentVersion: '1.7.3');
      i.onResponse(
        resWith({VersionSignalInterceptor.headerLatest: '1.7.3'}),
        _CapturingHandler(),
      );
      expect(received, isEmpty, reason: '已是最新版不该打扰用户');
    });

    test('latest 比本机旧 -> 不触发（服务端回滚后不该提示降级）', () {
      final i = VersionSignalInterceptor(currentVersion: '1.8.0');
      i.onResponse(
        resWith({VersionSignalInterceptor.headerLatest: '1.7.3'}),
        _CapturingHandler(),
      );
      expect(received, isEmpty);
    });

    test('没有版本头 -> 不触发（旧服务端没有这个头）', () {
      final i = VersionSignalInterceptor(currentVersion: '1.7.2');
      i.onResponse(resWith({'content-type': 'application/json'}), _CapturingHandler());
      expect(received, isEmpty);
    });

    test('版本头为空串 -> 不触发', () {
      final i = VersionSignalInterceptor(currentVersion: '1.7.2');
      i.onResponse(
        resWith({VersionSignalInterceptor.headerLatest: ''}),
        _CapturingHandler(),
      );
      expect(received, isEmpty);
    });

    test('update-required 不是 true 时按普通更新处理', () {
      final i = VersionSignalInterceptor(currentVersion: '1.7.2');
      i.onResponse(
        resWith({
          VersionSignalInterceptor.headerLatest: '1.7.3',
          VersionSignalInterceptor.headerUpdateRequired: 'false',
        }),
        _CapturingHandler(),
      );
      expect(received.length, 1);
      expect(received.first.required, isFalse);
    });

    test('头名大小写不敏感（HTTP 规定）', () {
      final i = VersionSignalInterceptor(currentVersion: '1.7.2');
      i.onResponse(
        resWith({'X-App-Latest': '1.7.3'}),
        _CapturingHandler(),
      );
      expect(received.length, 1, reason: 'Headers 应当无视大小写');
    });
  });

  group('426 走 error 分支也必须被处理', () {
    test('强制更新的 426 响应同样触发回调', () {
      final i = VersionSignalInterceptor(currentVersion: '1.0.0');
      final ro = RequestOptions(path: '/api/v1/user/me', baseUrl: 'http://x');
      final err = DioException(
        requestOptions: ro,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: ro,
          statusCode: 426,
          headers: Headers.fromMap({
            VersionSignalInterceptor.headerLatest: ['1.9.0'],
            VersionSignalInterceptor.headerUpdateRequired: ['true'],
          }),
        ),
      );
      i.onError(err, _CapturingErrorHandler());
      expect(received.length, 1,
          reason: '强制更新返回 426，只实现 onResponse 会漏掉它');
      expect(received.first.latest, '1.9.0');
      expect(received.first.required, isTrue);
    });

    test('普通网络错误（无响应）不触发', () {
      final i = VersionSignalInterceptor(currentVersion: '1.0.0');
      final ro = RequestOptions(path: '/x', baseUrl: 'http://x');
      i.onError(
        DioException(requestOptions: ro, type: DioExceptionType.connectionError),
        _CapturingErrorHandler(),
      );
      expect(received, isEmpty);
    });
  });

  group('未知本机版本时不猜', () {
    test('读不到本机版本 -> 不触发（避免误报「有新版本」）', () {
      final i = VersionSignalInterceptor(currentVersion: null);
      // 未调用 onRequest，因此 _resolved 仍为 null
      i.onResponse(
        resWith({VersionSignalInterceptor.headerLatest: '9.9.9'}),
        _CapturingHandler(),
      );
      expect(received, isEmpty,
          reason: '不知道自己是哪个版本时不该弹窗，交给启动检查那条路径');
    });
  });
}

/// 捕获 handler 的最终动作，用于确认拦截器没有把请求「吃掉」。
class _CapturingHandler extends ResponseInterceptorHandler {
  Object? errored;

  @override
  void next(Response<dynamic> response) {}

  @override
  void reject(DioException error, [bool callFollowingErrorInterceptor = false]) {
    errored = error;
  }

  @override
  void resolve(Response<dynamic> response) {}
}

class _CapturingErrorHandler extends ErrorInterceptorHandler {
  @override
  void next(DioException err) {}

  @override
  void reject(DioException error, [bool callFollowingErrorInterceptor = false]) {}

  @override
  void resolve(Response<dynamic> response) {}
}
