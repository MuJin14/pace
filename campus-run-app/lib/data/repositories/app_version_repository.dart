import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';

/// 服务端返回的版本信息。
class AppVersionInfo {
  const AppVersionInfo({
    required this.latest,
    required this.minSupported,
    required this.changelog,
    required this.apkReady,
    required this.apkUrl,
    required this.apkSizeBytes,
    this.apkSha256,
  });

  /// 最新版本号；**空串表示服务端没有发布新版本**，客户端应直接跳过。
  final String latest;

  /// 低于它的版本强制更新（空串 = 从不强制）。
  final String minSupported;

  final String changelog;

  /// 服务端是否已放好 APK 文件。为 false 时即使版本号更新也**不该**提示，
  /// 否则用户点了下载会拿到 404。
  final bool apkReady;

  final String? apkUrl;
  final int? apkSizeBytes;

  /// APK 的 sha256（小写十六进制）；服务端未提供时为 null。
  ///
  /// **用途**：下载前校验本地已存在的安装包是不是**就是这一版**，
  /// 是就直接装，不必重下。用户反馈过「同意授权后点重试又下载一遍」——
  /// 54MB 重下既慢又费流量，而这个判断只需要一次本地哈希。
  final String? apkSha256;

  /// 是否有可下载的新版本。
  bool get hasDownloadableUpdate => latest.isNotEmpty && apkReady && apkUrl != null;

  /// 体积的可读文案（用于「约 52 MB」这类提示）。
  String get sizeLabel {
    final bytes = apkSizeBytes;
    if (bytes == null || bytes <= 0) return '未知大小';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    // ⚠️ 校验值必须把「空串」规整成 null。
    //
    // 留一个空串会在下游变成「有校验值但永远匹配不上」：
    // 本地算出的哈希与 '' 比较恒为不等 → 每次都判定本地包无效 →
    // 用户每次重试都被重下 54MB。正是这个 bug 的原始症状。
    // 规整成 null 后会正确退化为「按文件大小校验」。
    final rawHash = (json['apkSha256'] as String?)?.trim().toLowerCase();
    return AppVersionInfo(
      latest: (json['latest'] as String?)?.trim() ?? '',
      minSupported: (json['minSupported'] as String?)?.trim() ?? '',
      changelog: (json['changelog'] as String?) ?? '',
      apkReady: json['apkReady'] as bool? ?? false,
      apkUrl: json['apkUrl'] as String?,
      apkSizeBytes: (json['apkSizeBytes'] as num?)?.toInt(),
      apkSha256: (rawHash == null || rawHash.isEmpty) ? null : rawHash,
    );
  }
}

final appVersionRepositoryProvider = Provider<AppVersionRepository>((ref) {
  return AppVersionRepository(ref.read(dioProvider));
});

class AppVersionRepository {
  AppVersionRepository(this._dio);

  final Dio _dio;

  /// 查询服务端发布的最新版本。
  Future<AppVersionInfo> fetchLatest() async {
    final resp = await _dio.get('/api/v1/app/version');
    final data = resp.data;
    if (data is! Map || data['code'] != 0) {
      throw StateError('版本接口返回异常');
    }
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) {
      throw StateError('版本接口缺少 data');
    }
    return AppVersionInfo.fromJson(payload);
  }
}

/// 语义化版本比较：返回 a 是否比 b **更新**。
///
/// 抽成纯函数是为了可单测 —— 这里出错会导致「永远提示更新」
/// 或「永远不提示」，而这两种都很难在真机上第一时间发现。
///
/// 规则：按 `.` 切分逐段比较数字；段数不同时缺失段按 0 处理
/// （`1.1` 与 `1.1.0` 视为相同）。非数字段一律当 0，
/// 保证 `1.0.0+3`（Flutter 的 build 后缀）不会让比较崩掉。
bool isVersionNewer(String candidate, String current) {
  int parse(String s, int i) {
    final parts = s.split('.');
    if (i >= parts.length) return 0;
    //  tolerated: "1.0.0+3" -> 取 "+" 前的数字部分
    final digits = RegExp(r'^\d+').stringMatch(parts[i].trim());
    return digits == null ? 0 : int.tryParse(digits) ?? 0;
  }

  final len = [candidate.split('.').length, current.split('.').length].reduce(
    (a, b) => a > b ? a : b,
  );
  for (var i = 0; i < len; i++) {
    final a = parse(candidate, i);
    final b = parse(current, i);
    if (a > b) return true;
    if (a < b) return false;
  }
  return false;
}
