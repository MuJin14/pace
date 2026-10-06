import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_version_repository.dart';

/// 「有一个可下载的新版本」这个事实。
///
/// ## 为什么单独抽成 provider，而不是启动时直接弹窗
///
/// 原先的实现是：启动检查 → 发现新版本 → **直接弹对话框**。
/// 实测这有两个问题（用户反馈）：
///
///   1. **打扰**：冷启动就弹一个"要更新吗"，而用户此刻往往只是想
///      看一眼步数。这个 App 又没有强制更新需求，弹窗的收益很低；
///   2. **容易被当成广告关掉**：用户条件反射地点「稍后」，
///      之后再也没有入口 —— 等于更新提示形同虚设。
///
/// 现在改成**把更新提示放进右上角的通知里**：
///   · 有新版 → 铃铛出现红点；
///   · 用户点进通知 → 看到「发现新版本 x.y.z」这一条；
///   · 点这一条才弹更新对话框。
///
/// 这样既不打扰，也不会被误关掉 —— 因为入口一直在通知页里。
///
/// ⚠️ 唯一的例外是**强制更新**：低于 `minSupported` 时仍然直接弹窗，
/// 因为那时继续用旧版本会出问题（接口不兼容等），不能等用户自己发现。
/// 是否强制由 [PendingUpdate.mandatory] 表达，弹窗层据此决定能否关闭。
class PendingUpdate {
  const PendingUpdate({required this.info, required this.mandatory});

  /// 完整版本信息（含 apkUrl / 体积 / 更新说明），点「立即更新」时要用。
  final AppVersionInfo info;

  /// 是否强制更新（本机版本低于服务端的 minSupported）。
  ///
  /// 为 true 时仍然**直接弹窗**且不可关闭 —— 见类注释里的说明。
  final bool mandatory;

  /// 便于展示的版本号。
  String get latest => info.latest;
}

/// 当前待处理的更新；没有新版本时为 null。
///
/// 由 `app.dart` 在启动检查与「服务端主动下发更新信号」两条路径上写入
/// （见 `VersionSignalInterceptor.onUpdate`）。
final pendingUpdateProvider =
    NotifierProvider<PendingUpdateNotifier, PendingUpdate?>(
        PendingUpdateNotifier.new);

class PendingUpdateNotifier extends Notifier<PendingUpdate?> {
  @override
  PendingUpdate? build() => null;

  /// 记录「发现新版本」。同一个版本重复调用不会重复触发重建，
  /// 避免通知列表无谓刷新。
  void found(AppVersionInfo info, {required bool mandatory}) {
    if (state?.latest == info.latest && state?.mandatory == mandatory) return;
    state = PendingUpdate(info: info, mandatory: mandatory);
  }

  /// 更新已完成或用户已装上新版本后清空。
  void clear() => state = null;
}
