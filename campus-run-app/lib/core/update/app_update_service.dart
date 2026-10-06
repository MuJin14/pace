import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/app_version_repository.dart';
import '../platform/app_version.dart';
import '../platform/install_permission.dart';

/// 自更新的状态机。
enum UpdateStage {
  /// 空闲（还没检查 / 已检查且无更新）。
  idle,

  /// 正在下载 APK。
  downloading,

  /// 下载完成，已交给系统安装器。
  readyToInstall,

  /// 出错了，[UpdateStatus.message] 里有原因。
  failed,
}

/// 一次更新流程的完整状态。
@immutable
class UpdateStatus {
  const UpdateStatus({
    this.stage = UpdateStage.idle,
    this.received = 0,
    this.total = 0,
    this.message,
  });

  final UpdateStage stage;

  /// 已下载字节数。
  final int received;

  /// 总字节数；服务端未给出 `Content-Length` 时为 0（此时进度条显示不确定态）。
  final int total;

  final String? message;

  /// 下载进度 0.0–1.0；[total] 未知时返回 null。
  double? get progress {
    if (total <= 0) return null;
    final p = received / total;
    return p.clamp(0.0, 1.0);
  }

  String get receivedLabel => _mb(received);

  String get totalLabel => _mb(total);

  static String _mb(int bytes) {
    if (bytes <= 0) return '0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 检查更新 + 下载 APK + 交给系统安装器。
///
/// **为什么必须由用户点「安装」**：Android 8.0 起禁止应用静默自安装。
/// 我们只能把 APK 下好、再用 [OpenFilex] 唤起系统安装器 ——
/// 最后那一下确认由用户完成（微信、淘宝同样如此）。
/// 首次还会跳系统设置要求授权「安装未知应用」，这一步无法绕过，
/// 所以失败时要给出**明确的指引**而不是一句「安装失败」。
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  /// 单独建一个 Dio：下载 52MB 包需要**长超时**，
  /// 不能复用业务接口那个短超时实例（会在下载中途被掐断）。
  Dio? _downloadDio;

  /// 正在进行的下载，便于取消（用户点「稍后」时不该继续占流量）。
  CancelToken? _cancelToken;

  /// 本机版本号，如 `1.9.3`；读不到返回空串。
  ///
  /// 失败**必须**留下日志：这个函数曾经因为 package_info_plus 没被注册
  /// 而永远返回空，配合上游的静默失败，表现是「更新弹窗永远不出现、
  /// 日志里什么都没有」。见 AppVersion 的说明。
  Future<String> currentVersion() => AppVersion.read();

  /// 查询是否有可下载的新版本。
  ///
  /// 任何异常都返回 null（**静默失败**）：检查更新是锦上添花，
  /// 不能因为服务端没配好就让用户看到报错弹窗。
  Future<AppVersionInfo?> checkForUpdate(
      AppVersionRepository repo, String currentVersion) async {
    // ⚠️⚠️ 本机版本未知时**必须**直接放弃，绝不能继续比较。
    //
    // 这是一个真实踩到的坑：`isVersionNewer('9.9.9', '')` 返回 **true** ——
    // 因为空串按 "." 切分后每一段都解析成 0，于是「任何版本都比它新」。
    //
    // 后果：只要 `AppVersion.read()` 返回空串（原生桥异常、ROM 限制等），
    // **所有用户**都会被告知「发现新版本」，而他们可能已经是最新版 ——
    // 一个读取故障直接升级成全量误报。
    //
    // 这条守卫比看起来重要：它把「不知道」和「比它新」区分开了。
    if (currentVersion.isEmpty) {
      debugPrint('[update] 本机版本号为空，跳过更新检查（不能拿空版本去比较）');
      return null;
    }

    try {
      final info = await repo.fetchLatest();
      if (!info.hasDownloadableUpdate) return null;
      if (!isVersionNewer(info.latest, currentVersion)) return null;
      return info;
    } catch (e) {
      debugPrint('[update] 检查更新失败（已忽略）: $e');
      return null;
    }
  }

  /// 本地已有的安装包能不能直接用（就是 [info] 描述的那一版）。
  ///
  /// 判定优先级：
  ///   1. 有 `sha256` → 必须完全一致（最严格，能发现下到一半的残包）；
  ///   2. 只有大小 → 比大小；
  ///   3. 两者都没有 → 不敢复用，返回 false（宁可重下，也不装一个来路不明的包）。
  Future<bool> _isUsablePackage(String path, AppVersionInfo info) async {
    try {
      final f = File(path);
      if (!await f.exists()) return false;

      final expectedHash = info.apkSha256;
      if (expectedHash != null && expectedHash.isNotEmpty) {
        final actual = await _sha256Of(f);
        final ok = actual == expectedHash;
        if (!ok) {
          debugPrint('[更新] 本地安装包校验值不符，将重新下载'
              '（期望 $expectedHash，实际 $actual）');
        }
        return ok;
      }

      final expectedSize = info.apkSizeBytes;
      if (expectedSize != null && expectedSize > 0) {
        return await f.length() == expectedSize;
      }

      // 服务端既没给校验值也没给大小：无法确认这个包是不是完整/正确的那一版。
      return false;
    } catch (e) {
      debugPrint('[更新] 检查本地安装包失败，将重新下载: $e');
      return false;
    }
  }

  /// 分块计算文件 sha256（小写十六进制）。
  ///
  /// 分块而不是一次性 `readAsBytes`：包有 54MB，全读进内存在中低端机上
  /// 可能直接触发 OOM —— 一个「省流量」的优化反而把 App 搞崩就得不偿失了。
  Future<String> _sha256Of(File f) async {
    final digest = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(digest);
    await for (final chunk in f.openRead()) {
      input.add(chunk);
    }
    input.close();
    return digest.events.single.toString();
  }

  /// 「差一步授权」的统一文案与状态。
  ///
  /// 抽出来是因为它现在有**两个**触发点：下载完成后、以及复用本地包时。
  /// 两处文案必须一致，否则用户会以为遇到了两种不同的问题。
  ///
  /// `onProgress` 由调用方传入：它是 `downloadAndInstall` 的参数，
  /// 不是这个类的方法。
  String _permissionNeeded(void Function(UpdateStatus) onProgress) {
    const msg = '安装包已下载完成，但系统还不允许行迹安装应用。'
        '点「去授权」开启「允许安装未知应用」后即可继续，不需要重新下载。';
    onProgress(const UpdateStatus(stage: UpdateStage.failed, message: msg));
    return msg;
  }

  /// 下载 APK 并唤起安装器。
  ///
  /// [onProgress] 会在下载过程中被频繁调用，调用方据此更新进度条。
  /// 返回 null 表示成功（已唤起安装器），否则返回给用户看的错误文案。
  Future<String?> downloadAndInstall(
    AppVersionInfo info, {
    required void Function(UpdateStatus) onProgress,
  }) async {
    final url = info.apkUrl;
    if (url == null || url.isEmpty) return '没有可用的下载地址';

    _cancelToken = CancelToken();
    try {
      final dir = await getApplicationSupportDirectory();
      // 固定文件名：重复下载直接覆盖，不在缓存目录里堆一堆 APK。
      // 放在 support 目录而不是临时目录：某些 ROM 会主动清理 cache，
      // 下载到一半被清掉会表现为「安装包解析失败」。
      final savePath = '${dir.path}/campus-run-update.apk';

      // ⚠️⚠️ 先看本地是不是**已经有这一版**的安装包，有就直接装。
      //
      // 用户反馈：下载完成 → 系统要求授权「安装未知应用」→ 同意后点「重试」，
      // 结果 54MB **又下了一遍**。
      //
      // 原来的代码在这里**无条件删除**旧文件，于是「重试」只能重下。
      // 但那个包其实完好无损地躺在磁盘上 —— 只是缺一个安装授权而已。
      //
      // 校验方式优先用服务端给的 sha256（最严格）；没有就退化为比大小。
      // 大小相同但内容不同的概率极低，而这里的目标只是「别让用户白等 54MB」，
      // 不值得为此拒绝一切降级路径。
      if (await _isUsablePackage(savePath, info)) {
        debugPrint('[更新] 本地已有这一版的安装包，跳过下载直接安装');
        onProgress(UpdateStatus(
          stage: UpdateStage.readyToInstall,
          received: info.apkSizeBytes ?? 0,
          total: info.apkSizeBytes ?? 0,
        ));
        if (!await InstallPermission.isAllowed()) {
          return _permissionNeeded(onProgress);
        }
        return await _installAndCleanup(savePath);
      }

      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      onProgress(const UpdateStatus(stage: UpdateStage.downloading));

      await _dio.download(
        url,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          onProgress(UpdateStatus(
            stage: UpdateStage.downloading,
            received: received,
            total: total,
          ));
        },
      );

      onProgress(UpdateStatus(stage: UpdateStage.readyToInstall));

      // ⚠️ 唤起安装器**之前**先确认「允许安装未知应用」。
      //
      // 缺这一步时，用户点完成功下载、却什么都不发生：
      // manifest 少了 REQUEST_INSTALL_PACKAGES 会被系统静默拒绝；
      // 即使用户在授权页点了「拒绝」，open_filex 也可能仍返回成功。
      // 两种情况都不报错，用户只会看到「点了没反应」。
      //
      // 下载已经完成，所以这里的失败文案要说清「已经下好了，只差授权」——
      // 否则用户会以为又要重新下载。
      if (!await InstallPermission.isAllowed()) {
        return _permissionNeeded(onProgress);
      }

      return await _installAndCleanup(savePath);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        onProgress(const UpdateStatus(stage: UpdateStage.idle, message: '已取消'));
        return null; // 主动取消不算错误
      }
      final msg = _describeDownloadError(e);
      onProgress(UpdateStatus(stage: UpdateStage.failed, message: msg));
      return msg;
    } catch (e) {
      final msg = '下载失败：$e';
      onProgress(UpdateStatus(stage: UpdateStage.failed, message: msg));
      return msg;
    } finally {
      _cancelToken = null;
    }
  }

  /// 唤起安装器，并在交给系统之后删掉安装包。
  ///
  /// ## 为什么装完要删
  ///
  /// 54MB 的 APK 在安装完成后已经没有任何用处：
  ///   · 留着白占空间，用户不会知道去哪清；
  ///   · 系统安装器**已经把文件读走并复制到自己的目录**，此时删除安全；
  ///   · 万一安装失败（用户取消等），下次更新会重新下载 —— 这点代价可以接受，
  ///     好过长期占着几十 MB。
  ///
  /// ⚠️ 只在**成功唤起安装器**之后删。给用户看的「去授权」路径不能删，
  /// 否则他授权回来点重试又得重下 54MB —— 那正是刚修掉的问题。
  Future<String?> _installAndCleanup(String path) async {
    final error = await _install(path);
    // ⚠️⚠️ 这里**不能**删安装包，哪怕安装看起来已经交出去了。
    //
    // 用户反馈过「下载完装不上」，根因就是这里曾经删得太早：
    //
    //   OpenFilex.open() 返回 done 只表示 **Intent 已交给系统**，
    //   并不代表安装器已经读完文件。54MB 的包，安装器要花几秒去读并复制，
    //   而我们这边一返回就删除 → 安装器读到一半文件没了 → 安装失败。
    //
    // 这个 bug 的隐蔽之处在于：它**只在包比较大时暴露**，
    // 而且日志里看不出异常（删除本身是成功的）。
    //
    // 正确的回收时机是**下次启动**（见 cleanupStalePackage）——
    // 那时安装早已结束，即便用户取消安装，重新下载也只是代价而非故障。
    return error;
  }

  /// 清掉历史遗留的安装包。
  ///
  /// 在启动时调用。用途是回收**旧版本**留下的文件 ——
  /// 比如修复「重试会重下」之前，用户手机里可能存着好几个下载到一半的包。
  ///
  /// [olderThan] 保证不会误删**刚刚下载好、正等着用户授权**的那个包：
  /// 那种情况用户可能过几分钟才回来点安装。
  Future<void> cleanupStalePackage({
    Duration olderThan = const Duration(hours: 6),
  }) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/campus-run-update.apk');
      if (!await f.exists()) return;
      final age = DateTime.now().difference(await f.lastModified());
      if (age < olderThan) return;
      final size = await f.length();
      await f.delete();
      debugPrint('[更新] 清理陈旧安装包（${size ~/ 1024 ~/ 1024} MB，'
          '已存放 ${age.inHours} 小时）');
    } catch (e) {
      debugPrint('[更新] 清理陈旧安装包失败（已忽略）: $e');
    }
  }

  /// 取消正在进行的下载。
  void cancel() {
    final token = _cancelToken;
    if (token != null && !token.isCancelled) token.cancel('用户取消');
  }

  Dio get _dio => _downloadDio ??= Dio(BaseOptions(
        // 下载 52MB：不给总超时，只给它足够长的「无数据」容忍时间。
        // receiveTimeout 设成 30 秒——超过 30 秒一个字节都没收到才算断流。
        receiveTimeout: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 20),
        followRedirects: true,
      ));

  /// 唤起系统安装器。
  ///
  /// 返回 null 表示已成功把安装界面交给系统；否则返回可读的错误说明。
  Future<String?> _install(String path) async {
    try {
      final result = await OpenFilex.open(path);
      switch (result.type) {
        case ResultType.done:
          return null;
        case ResultType.permissionDenied:
          // 最常见的情况：用户还没在这个手机上允许「安装未知应用」。
          // 必须给出**可操作**的指引，否则用户只会觉得「点了没反应」。
          return '系统不允许安装。请到「设置 → 应用 → 行迹 → 安装未知应用」'
              '里允许后再试一次。';
        case ResultType.fileNotFound:
          return '安装包不存在或已被系统清理，请重新下载。';
        case ResultType.noAppToOpen:
          return '这台设备上没有可用的安装程序。';
        default:
          return result.message.isEmpty ? '无法打开安装程序。' : result.message;
      }
    } catch (e) {
      return '无法打开安装程序：$e';
    }
  }

  /// 把 Dio 的异常翻译成人能看懂的话。
  ///
  /// 原始信息是 `DioException [connection error]: ...` 这种，
  /// 对用户毫无意义。
  String _describeDownloadError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '下载超时，请检查网络后重试。';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络后重试。';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) return '服务器上还没有可下载的安装包。';
        return '服务器返回错误（$code），请稍后重试。';
      default:
        return '下载失败，请稍后重试。';
    }
  }
}
