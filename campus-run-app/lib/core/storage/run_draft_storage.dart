import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 进行中运动的本地草稿。
///
/// **为什么必须有这个东西**：轨迹原先只存在内存里（`List<TrackPoint>`）。
/// 用户跑 5 公里时切后台被系统回收、或 App 崩溃、或手滑返回，
/// 整次运动**彻底消失且无法恢复** —— 这是跑步类 App 最不可接受的失败。
/// 有了草稿，重进 App 就能恢复并继续。
class RunDraft {
  const RunDraft({
    required this.type,
    required this.points,
    required this.elapsedMs,
    required this.startedAtMs,
  });

  /// 1=跑步 2=骑行
  final int type;

  final List<Map<String, dynamic>> points;

  /// 已累计用时（毫秒，不含暂停）。
  final int elapsedMs;

  /// 开始时间（毫秒时间戳），用于上报时的 startTime。
  final int startedAtMs;

  bool get isEmpty => points.isEmpty;

  /// 草稿的有效期。超过它就不该被恢复，直接丢弃。
  ///
  /// ## 为什么（真实故障：一次正常跑步被判无效）
  ///
  /// 用户反馈：「原本应该是个合格的时间，结果开始时间给我定位到昨天了，
  /// 导致成绩无效」。
  ///
  /// 原来恢复草稿时**只比对运动类型**，不看时间。于是昨天草稿里的轨迹点
  /// 会被并进今天这条轨迹 —— 数据库里三条被作废的记录都是这个成因
  /// （轨迹跨 17.9 小时、点均间隔 1742 秒，中间大段根本没在记录）。
  ///
  /// ## 为什么取 6 小时
  ///
  /// 要覆盖「跑完忘了点结束，晚上回来点结束」这种正当场景；
  /// 又要拦住「隔天再开跑还把昨天的点接上」。6 小时足够宽裕，且远小于跨天。
  static const Duration maxAge = Duration(hours: 6);

  /// 草稿存放了多久；无法判定时返回 null（按「不过期」处理，保守）。
  ///
  /// [nowMillis] 可注入，便于测试 —— 用 `DateTime.now()` 的话测试只能靠
  /// 「构造一个刚好 6 小时零 1 毫秒前的时间戳」，既脆弱又会随执行时间漂移。
  ///
  /// ⚠️ 时钟被改到过去会得到负值：那说明不可信，返回 null（不过期），
  /// 而不是因为这个把用户的草稿误删。
  Duration? ageAt(int nowMillis) {
    if (startedAtMs <= 0) return null;
    final ageMs = nowMillis - startedAtMs;
    if (ageMs < 0) return null;
    return Duration(milliseconds: ageMs);
  }

  /// 是否已过期（超过 [maxAge]）。
  bool isExpiredAt(int nowMillis) {
    final age = ageAt(nowMillis);
    return age != null && age > maxAge;
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'points': points,
        'elapsedMs': elapsedMs,
        'startedAtMs': startedAtMs,
      };

  static RunDraft? fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    if (rawPoints is! List) return null;
    return RunDraft(
      type: (json['type'] as num?)?.toInt() ?? 1,
      points: rawPoints
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      startedAtMs: (json['startedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 草稿存储抽象，便于测试替换为内存实现。
abstract class RunDraftStorage {
  Future<RunDraft?> read();
  Future<void> write(RunDraft draft);
  Future<void> clear();
}

class PrefsRunDraftStorage implements RunDraftStorage {
  PrefsRunDraftStorage([Future<SharedPreferences>? prefs])
      : _prefs = prefs ?? SharedPreferences.getInstance();

  static const String _key = 'active_run_draft';

  final Future<SharedPreferences> _prefs;

  @override
  Future<RunDraft?> read() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return RunDraft.fromJson(decoded);
    } catch (_) {
      // 草稿损坏不应让跑步页打不开：当作没有草稿，用户重新开始即可
      return null;
    }
  }

  @override
  Future<void> write(RunDraft draft) async {
    final prefs = await _prefs;
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_key);
  }
}

/// 内存实现：测试与「不落盘」场景使用。
class InMemoryRunDraftStorage implements RunDraftStorage {
  RunDraft? _draft;

  @override
  Future<RunDraft?> read() async => _draft;

  @override
  Future<void> write(RunDraft draft) async => _draft = draft;

  @override
  Future<void> clear() async => _draft = null;
}

final runDraftStorageProvider =
    Provider<RunDraftStorage>((ref) => PrefsRunDraftStorage());
