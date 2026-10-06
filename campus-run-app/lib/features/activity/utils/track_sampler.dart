import 'package:latlong2/latlong.dart';

import '../../../data/models/track_point.dart';

/// 轨迹采样过滤。
///
/// **为什么单独抽出来**：这是"定位准不准"的决定性环节，也是最容易写错、
/// 最需要测试的地方。放在页面里就只能靠真机试，抽成纯函数后可单测。
///
/// 两道过滤：
/// 1. **精度过滤**：误差过大的点直接不要。手机在楼下/树荫/高楼间误差常到 20-50m，
///    这种点会让轨迹"跳出去又跳回来"，一次抖动凭空产生上百米 ——
///    用户说的「定位不准」十有八九是它。
/// 2. **抖动过滤**：静止时 GPS 会持续小幅漂移，每个点都累加会让
///    「站着不动」也涨距离。
///
/// ⚠️ **必须与服务端 `GpsUtil` 保持同一套判据**。
/// 成绩用过滤值、反作弊用原始值这种口径不一致，曾让正常跑步被判超速作弊
/// （见 AGENTS.md「跑步核心链路」）。改这里的算法请同步改
/// `campus-run-backend/.../util/GpsUtil.java`。
class TrackSampler {
  const TrackSampler({
    this.maxAccuracyMeters = 30.0,
    this.coherenceWindowSeconds = 5.0,
    this.minStraightness = 0.6,
  });

  /// 精度阈值（米）：误差大于它的点不参与距离累加。
  final double maxAccuracyMeters;

  /// 方向一致性判据的窗口长度（秒）。
  final double coherenceWindowSeconds;

  /// 窗口内「净位移 ÷ 路径长度」的最低值，低于它视为抖动。
  final double minStraightness;

  static const Distance _distance = Distance();

  /// 两点间大圆距离（米）。
  double chord(TrackPoint a, TrackPoint b) => _distance.as(
        LengthUnit.Meter,
        LatLng(a.latitude, a.longitude),
        LatLng(b.latitude, b.longitude),
      );

  /// 精度是否可采信。
  bool isAccuracyAcceptable(double? accuracy) =>
      accuracy == null || !accuracy.isFinite || accuracy <= maxAccuracyMeters;

  /// 按规则计算整条轨迹的距离。
  ///
  /// **为什么用「滑窗方向一致性」而不是逐段位移阈值**：
  /// 逐段位移无法区分「慢走 1.4 m/s（每步 1.4 米）」与
  /// 「静止抖动（每步可达 2 米）」—— 两者单步位移处在同一量级。
  /// 旧实现要求「位移 ≥ 2 米 **或** 间隔 ≥ 5 秒」，
  /// 在 1 秒采样下慢走**两支都不满足**，于是每段都被丢弃、
  /// 整条轨迹距离**恰好为 0**（线上「运动记录为 0」的真实根因，
  /// 表现是「走路的人全为 0、跑步的人全部正常」）。
  ///
  /// 现在的判据对**速度不敏感**，因此慢走与快跑一视同仁。
  ///
  /// > 录制过程中请用 [TrackDistanceAccumulator]（增量、O(1)）；
  /// > 本方法用于「草稿恢复后重算」这种一次性场景。
  double totalDistance(Iterable<TrackPoint> points) {
    final acc = TrackDistanceAccumulator(this);
    for (final p in points) {
      acc.add(p);
    }
    return acc.distance;
  }
}

/// 增量距离累加器：录制时每来一个点调用一次 [add]，读取 [distance]。
///
/// 为什么不能用 [TrackSampler.totalDistance] 反复重算：录制过程中点会不断增加，
/// 每次都全量重算是 O(n²)，一次长跑几万个点会明显卡顿。
///
/// （Dart 不支持嵌套类，所以它必须在顶层。）
class TrackDistanceAccumulator {
  TrackDistanceAccumulator(this._sampler);

  final TrackSampler _sampler;

  /// 已结算的距离（不含当前窗口）。
  double _settled = 0;

  /// 当前窗口已认定的位移（窗口重置时清零）。
  ///
  /// 独立保存的原因：`_settled + 当前窗口净位移` 在**窗口刚被重置**的瞬间
  /// 会算出一个偏小的值（窗口里只剩 1 个点时净位移为 0），
  /// 表现为「距离突然回退」。用字段保存最后一次认定的结果，取值就稳定了。
  double _pending = 0;

  /// 当前窗口的锚点。
  TrackPoint? _anchor;

  /// 当前窗口内的原始点（用于算路径长度）。
  final List<TrackPoint> _window = [];

  /// 当前累计距离。
  double get distance => _settled + _pending;

  /// 追加一个定位点，返回最新累计距离。
  double add(TrackPoint p) {
    if (!_sampler.isAccuracyAcceptable(p.accuracy)) {
      // 脏点不采信，也不进入窗口（否则会拿脏点算出一大段位移）
      return distance;
    }
    final anchor = _anchor;
    if (anchor == null) {
      _anchor = p;
      _window.add(p);
      return distance;
    }
    _window.add(p);
    // 窗口一有新点就先把它的净位移算进来，界面上的数字才会跟着长
    _pending = _windowCoherent() ? _windowNet() : 0;

    final elapsed = (p.timestamp - anchor.timestamp) / 1000.0;
    if (elapsed <= 0) {
      // 时间戳缺失/倒流：退化处理，按弦长累加（保持老数据向后兼容）
      _settled += _sampler.chord(anchor, p);
      _reset(p);
      return distance;
    }
    if (elapsed < _sampler.coherenceWindowSeconds) {
      return distance; // 窗口未满，继续攒
    }
    // 窗口期满：把认定的位移结算进 _settled，并以当前点为新锚点开窗
    _settled += _pending;
    _reset(p);
    return distance;
  }

  void _reset(TrackPoint p) {
    _anchor = p;
    _pending = 0;
    _window
      ..clear()
      ..add(p);
  }

  double _windowNet() {
    if (_window.length < 2 || _anchor == null) return 0;
    return _sampler.chord(_anchor!, _window.last);
  }

  double _windowPath() {
    double path = 0;
    for (var i = 1; i < _window.length; i++) {
      path += _sampler.chord(_window[i - 1], _window[i]);
    }
    return path;
  }

  bool _windowCoherent() {
    if (_window.length < 2 || _anchor == null) return false;
    final net = _windowNet();
    if (net <= 0) return false;
    final path = _windowPath();
    if (path <= 0) return false;
    return net / path >= _sampler.minStraightness;
  }
}


