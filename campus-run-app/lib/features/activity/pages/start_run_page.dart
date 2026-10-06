import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/run_draft_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/coord_transform.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_metric_text.dart';
import '../../../data/models/track_point.dart';
import '../../../data/repositories/activity_repository.dart';
import '../utils/track_sampler.dart';
import '../widgets/track_map.dart';

/// 跑步/骑行记录页：真实 GPS 轨迹采集 + 距离/时长/配速 + 上传。
class StartRunPage extends ConsumerStatefulWidget {
  const StartRunPage({super.key, required this.type});

  final String type; // 'run' | 'ride'

  @override
  ConsumerState<StartRunPage> createState() => _StartRunPageState();
}

enum _Phase { checking, error, ready }

class _StartRunPageState extends ConsumerState<StartRunPage>
    with WidgetsBindingObserver {
  /// 精度过滤与抖动过滤的规则集中在 [TrackSampler]（可单测）。
  /// 页面里不再各写一份，避免"页面能跑但规则和测试不一致"。
  static const TrackSampler _sampler = TrackSampler();

  /// 增量累加器：录制过程中每来一个点调用一次，O(1)。
  ///
  /// 不能改成「每次全量重算」——一次长跑几万个点是 O(n²)，会明显卡顿。
  TrackDistanceAccumulator _distanceAcc = TrackDistanceAccumulator(_sampler);

  _Phase _phase = _Phase.checking;
  String _errorMessage = '';
  bool _isDeniedForever = false;

  /// 「去设置」按钮应该打开系统**位置信息**页（而不是应用权限页）。
  ///
  /// 两种失败需要去的地方不同：
  ///   · 权限被永久拒绝 → 应用的权限页；
  ///   · 系统定位开关没开 → 系统的位置信息页。
  /// 都归到 _isDeniedForever（都是「必须去系统设置」），
  /// 用这个标志区分去哪个页面。
  bool _openLocationSettings = false;

  StreamSubscription<Position>? _posSub;
  final MapController _mapController = MapController();
  bool _mapReady = false;

  final List<TrackPoint> _track = [];
  double _distanceMeters = 0;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _paused = false;
  bool _submitting = false;

  /// 墙钟计时：用真实时间差而不是「每秒 +1」。
  /// 每秒累加的做法在 App 被系统挂起时会停止走时，而用户还在跑 ——
  /// 结果时长偏短、配速偏快，且上报的 startTime 会晚于第一个轨迹点，
  /// 直接触发后端「开始时间超出时钟偏差」把整次运动判为无效。
  final Stopwatch _stopwatch = Stopwatch();

  /// 开始时间（第一个有效定位点的时间），上报时用它而不是推算。
  DateTime? _startedAt;

  /// 草稿落盘节流：每个点都写盘会有性能问题，2 秒一次足够。
  DateTime _lastDraftSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _draftChecked = false;

  bool get _isRun => widget.type == 'run';
  Color get _accent => _isRun ? AppColors.run : AppColors.ride;
  String get _title => _isRun ? '跑步中' : '骑行中';
  int get _typeCode => _isRun ? 1 : 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  /// App 从后台回到前台时校准计时：挂起期间 Stopwatch 仍按墙钟走（它会一直计时），
  /// 但保险起见在这里刷新一次显示，避免恢复瞬间数字是旧的。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_paused && mounted) {
      setState(() => _elapsed = _stopwatch.elapsed);
      // 恢复时立刻存一次草稿：系统随时可能再次回收进程
      _saveDraft(force: true);
    }
  }

  Future<void> _init() async {
    if (mounted) setState(() => _phase = _Phase.checking);
    if (kIsWeb) {
      _fail('网页版暂不支持定位，请使用手机 App');
      return;
    }
    // 先看有没有未完成的草稿（上次被系统回收/崩溃）
    await _restoreDraftIfAny();
    if (!mounted) return;
    final ok = await _requestPermission();
    if (!ok || !mounted) return;

    // ⚠️ 这里**不能**直接把界面切成 ready。
    //
    // 之前就是这么写的，结果是用户反馈「点开始跑步后要等很久」：
    // 权限一通过就显示完整的跑步界面（计时器在走、距离是 0、没有轨迹），
    // 而 `TrackSampler` 还在过滤精度不够的定位点 ——
    // **要等第一个「合格」点才有任何反应**，最坏 45 秒。
    // 界面看起来是「已经在跑」，但数据全是 0，比停在"正在获取定位…"更让人困惑。
    //
    // 现在：**保持在"正在获取定位…"**，由 `_onPosition` 收到首个合格点后
    // 再切 ready（见那里的 setState）。计时器也从那一刻才开始走，
    // 这样「用时」与「轨迹」天然对齐，不会出现"时间走了但没距离"。
    _startTracking();
  }

  /// 读取本地草稿。有则恢复轨迹与用时，让用户接着跑（或直接结束上传）。
  Future<void> _restoreDraftIfAny() async {
    if (_draftChecked) return;
    _draftChecked = true;
    try {
      final draft = await ref.read(runDraftStorageProvider).read();
      if (draft == null || draft.isEmpty || !mounted) return;
      // 只恢复同一运动类型的草稿，避免跑步页捡到骑行记录
      if (draft.type != _typeCode) return;

      final restored = <TrackPoint>[];
      for (final p in draft.points) {
        final tp = TrackPoint.fromJson(p);
        restored.add(tp);
      }
      if (restored.isEmpty) return;

      setState(() {
        _track
          ..clear()
          ..addAll(restored);
        _elapsed = Duration(milliseconds: draft.elapsedMs);
        _startedAt = DateTime.fromMillisecondsSinceEpoch(draft.startedAtMs);
        // 距离按恢复的轨迹重算，避免与已存值不一致。
        // 注意必须**重建累加器**，否则它还是空的，后续新增点的累计值会从 0 开始。
        _resetDistanceAccumulator();
        _distanceMeters = _distanceAcc.distance;
      });
      // 计时从已累计的时间继续
      _stopwatch
        ..reset()
        ..start();
      if (mounted) {
        _showMessage('已恢复上次未完成的运动（$_distanceText），可继续或直接结束');
      }
    } catch (_) {
      // 草稿不可用不影响开新的一次运动
    }
  }


  /// 把当前轨迹写入本地草稿（节流 2 秒）。
  void _saveDraft({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastDraftSave).inSeconds < 2) return;
    _lastDraftSave = now;
    final startedAt = _startedAt?.millisecondsSinceEpoch ?? 0;
    final draft = RunDraft(
      type: _typeCode,
      points: _track.map((p) => p.toJson()).toList(),
      elapsedMs: _elapsed.inMilliseconds,
      startedAtMs: startedAt,
    );
    // 不 await：写盘慢或失败都不能影响跑步本身。
    // 并发写可能乱序，但每次写的都是"当前更完整的轨迹"，后写覆盖前写即可。
    ref.read(runDraftStorageProvider).write(draft).catchError((Object _) {});
  }


  void _fail(String message, {bool deniedForever = false}) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = message;
      _isDeniedForever = deniedForever;
    });
  }

  /// 检查定位权限**并确认真的能拿到位置**。
  ///
  /// ⚠️ **刻意不用 `Geolocator.isLocationServiceEnabled()` 做前置拦截**。
  /// 实测（小米 MIUI，Android 15）：系统定位为高精度、应用已授「始终允许」、
  /// 微信/高德都能正常定位的情况下，这个接口仍返回 false，
  /// 把正常用户判成「未开定位服务」而完全无法使用。
  ///
  /// ⚠️ 但**也不能只看权限就放行**（这里出过问题）：
  /// 权限为「始终允许」只代表 App 被授权，不代表系统的定位开关是打开的。
  /// 系统开关关着时，之前的实现会一路走到 `_startTracking()` 然后**静默卡住**——
  /// 界面显示可以跑，但永远拿不到点，用户只能自己去设置里摸索。
  ///
  /// 正确做法：**先真取一次位置**。
  ///   · 拿到点 → 服务确实是开的，放行；
  ///   · 抛 `LocationServiceDisabledException` → 服务关了，
  ///     给出明确的「去开启」引导（含直接跳设置的按钮）。
  /// 这样既不误判，也不会静默失败。
  Future<bool> _requestPermission() async {
    try {
      var perm = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 10));
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 10));
      }
      if (perm != LocationPermission.whileInUse &&
          perm != LocationPermission.always) {
        _fail('未获得定位权限。请到「设置 → 应用 → 行迹 → 权限 → 位置信息」改为「始终允许」',
            deniedForever: perm == LocationPermission.deniedForever);
        return false;
      }

      // 权限有了，再确认系统定位服务**确实可用**。
      //
      // ⚠️ 这一步是「用真实取点代替会误报的预检查接口」，但第一版做错了，
      //    导致「点开始跑步后要等很久」：
      //
      //    · `desiredAccuracy: LocationAccuracy.low` —— 在 Android 上
      //      low 通常**不用 GPS**，而靠 Wi-Fi/基站做单次定位，
      //      反而比 high 更慢（且定位流本身用的是 high，等于白等一次）；
      //    · `timeLimit: 12 秒` —— 没定位到时最长要干等 12 秒，
      //      而这段时间结束后才真正开始追踪。
      //
      //    最坏情况：白等 12 秒 + 再等追踪出首个点。
      //
      // 现在的口径：**只用来区分「服务是否被关闭」，不追求拿到有效定位**。
      //   · 4 秒足够——服务开着时会很快返回（哪怕是缓存位置）；
      //   · 服务关着时 `LocationServiceDisabledException` 是**立即**抛出的，
      //     根本等不到超时，所以短超时不影响这个判断；
      //   · 超时/其它异常一律放行，由追踪流与它的 45 秒首点兜底
      //     （冷启动本来就可能要 30-60 秒，这里不该重复等待）。
      try {
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
      } on LocationServiceDisabledException {
        _failLocationServiceOff();
        return false;
      } on TimeoutException {
        // 超时不代表服务是关的（冷启动可能要 30-60 秒）。
        // 立刻放行，让追踪流开始等点 —— 不要在这里重复等待。
        debugPrint('[定位] 预热取点超时，立即放行（交给追踪流等首个点）');
      } catch (e) {
        debugPrint('[定位] 预热取点异常，立即放行: $e');
      }

      return true;
    } on TimeoutException {
      _fail('定位权限检查超时，请重试');
      return false;
    } catch (e) {
      _fail('定位权限检查失败：$e');
      return false;
    }
  }

  /// 系统定位服务未开启：给出明确原因 + 一键跳转设置。
  ///
  /// `Geolocator.openLocationSettings()` 会直接打开系统「位置信息」页，
  /// 比让用户自己翻设置少好几步 —— 用户反馈里说的
  /// 「说可以定位，结果还要自己手动去开」就是指这个多出来的摸索成本。
  void _failLocationServiceOff() {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = '手机的「位置信息」开关没有打开，无法记录轨迹。';
      // 复用 deniedForever 的语义位：都是「必须去系统设置才能解决」，
      // 让它决定按钮文案与动作，不必再加一个平行的布尔字段。
      _isDeniedForever = true;
      _openLocationSettings = true;
    });
  }

  /// 首个定位点的等待上限。
  ///
  /// **不能设太短**：GPS 冷启动（首次定位、需下载星历）常要 30-60 秒，
  /// 室内更久。原先 10 秒会把"还在搜星"的正常情况判成失败，
  /// 用户一进跑步页就报错。这里给 45 秒，并在界面上显示"正在定位…"，
  /// 让用户知道不是卡死了。
  static const Duration _firstFixTimeout = Duration(seconds: 45);

  void _startTracking() {
    _posSub?.cancel();

    // 计时器只用于超时兜底；每来一个点就重置，所以它衡量的是
    // "连续无定位的时间"，而不是总时长 —— 跑动中偶尔丢几秒不会误报。
    Timer? firstFix;
    void armFirstFix() {
      firstFix?.cancel();
      firstFix = Timer(_firstFixTimeout, () {
        if (!mounted || _track.isNotEmpty) return;
        _fail('45 秒内没有获取到定位。请确认：\n'
            '1. 已到室外或窗边（室内 GPS 常无法定位）\n'
            '2. 下拉通知栏的「定位」开关是亮的\n'
            '3. 设置 → 应用 → 行迹 → 权限 → 位置信息 = 始终允许');
      });
    }

    armFirstFix();

    _posSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen(
      (p) {
        firstFix?.cancel();
        firstFix = null;
        _onPosition(p);
      },
      onError: (Object e) {
        // 单次错误不再直接判死：重新武装超时并继续等，
        // 因为 MIUI/GMS 偶发会报一次错随后恢复正常。
        armFirstFix();
        debugPrint('[定位] 位置流错误（继续重试）：$e');
      },
      cancelOnError: false,
    );
  }

  /// 定位采样参数。
  ///
  /// 关键点：**必须带前台服务通知**，否则 App 切后台/锁屏后系统会暂停定位回调，
  /// 一次跑步会被截断成多条记录（跑步类 App 的致命体验问题）。
  /// Android 走前台服务 + 常驻通知；iOS 需要 Info.plist 的后台定位权限与
  /// Xcode 的 "Location updates" Background Mode。
  LocationSettings _locationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        // ⚠️ 必须为 true —— 这是国内 ROM（小米/华为等）能否定位的关键。
        //
        // geolocator 默认（false）走 Google Play Services 的
        // `LocationServices.getSettingsClient().checkLocationSettings()`，
        // 该调用一旦失败就直接报「The location service on the device is disabled」，
        // 尽管系统定位完全正常、微信/高德都能定位（实测小米 HyperOS 复现）。
        //
        // 设为 true 后改用 Android 原生 LocationManagerClient，
        // 其判断是 `isProviderEnabled(GPS) || isProviderEnabled(NETWORK)` —— 不依赖 GMS。
        forceLocationManager: true,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '行迹正在记录轨迹',
          notificationText: '锁屏或切后台也会继续记录，返回 App 即可查看',
          notificationChannelName: '运动轨迹记录',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
  }

  void _onPosition(Position p) {
    if (_paused || !mounted) return;
    // 还没切到 ready 说明这是**首个定位点**，或者是草稿恢复后的第一批点。
    // 不能像以前那样直接 `_phase != ready 就 return` —— 那样首个点会被丢掉，
    // 导致界面永远等不到「可以开始」的信号。
    if (_phase != _Phase.ready && _phase != _Phase.checking) return;

    final ts = p.timestamp.millisecondsSinceEpoch;
    // 精度过滤 + 抖动过滤统一走 TrackSampler（规则可单测，且与服务端同判据）。
    //
    // ⚠️ 距离由**增量累加器**给出，不要把点加进 _track 后再全量重算：
    // 一次长跑几万个点，分段全量重算是 O(n²)，会明显卡顿。
    final tp = TrackPoint(
      latitude: p.latitude,
      longitude: p.longitude,
      timestamp: ts,
      accuracy: p.accuracy.isFinite ? p.accuracy : null,
    );
    final before = _distanceMeters;
    final now = _distanceAcc.add(tp);
    // 点被精度过滤时不去记录轨迹，避免脏点画出乱线
    if (now == before && !_sampler.isAccuracyAcceptable(tp.accuracy)) {
      return;
    }

    _startedAt ??= DateTime.fromMillisecondsSinceEpoch(ts);

    // 首个**合格**定位点：从这里才真正开始跑步。
    //
    // 计时器也在此刻启动，保证「用时」和「轨迹」对齐 ——
    // 否则会出现「时间在走但距离一直是 0」的困惑画面。
    if (_phase == _Phase.checking) {
      setState(() => _phase = _Phase.ready);
      _startTimer();
    }

    setState(() {
      _distanceMeters = now;
      _track.add(tp);
    });
    _saveDraft();
    if (_mapReady) {
      // ⚠️ 必须转换坐标系后再移动地图。
      //
      // 高德瓦片是 **GCJ-02**（火星坐标），而 GPS 给的是 **WGS-84**，
      // 在国内两者相差几百米。`TrackMap` 画轨迹前已经转过（track_map.dart），
      // 但这里曾直接用 WGS-84 原始坐标 move() ——
      // 结果地图中心与圆点位置错开几百米：**圆点始终在屏幕外**，
      // 用户手动划过去后，下一个定位点又把地图拉回错误中心（表现为"位置被重置"）。
      final gcj = CoordTransform.wgs84ToGcj02(p.latitude, p.longitude);
      _mapController.move(gcj, _mapController.camera.zoom);
    }
  }

  /// 计时器只负责刷新显示，时间真值来自 [_stopwatch]（墙钟）。
  void _startTimer() {
    _timer?.cancel();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _stopwatch.elapsed);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    _elapsed = _stopwatch.elapsed;
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _stopTimer();
        // 累加器同样要重置：暂停期间的定位不记录，若保留窗口，
        // 恢复后第一个点会与暂停前的锚点组成一条横跨暂停期的弦。
        _resetDistanceAccumulator();
        _saveDraft(force: true); // 暂停时落盘，此刻状态最稳定
      } else {
        // 继续时不清空已累计用时：Stopwatch 的 elapsed 会接着累加
        _stopwatch.start();
        _startTimer();
      }
    });
  }

  /// 用**当前窗口内的尾部点**重建累加器状态。
  ///
  /// 为什么只喂尾部而不是全部轨迹：累加器只依赖「锚点 + 当前窗口」，
  /// 更早的点早已结算进 `_settled`，重新喂它们对结果没有影响，
  /// 但会让每次暂停/恢复都变成 O(n)（一次长跑几万个点，积少成多会卡）。
  ///
  /// 窗口取「最后一个点往前 coherenceWindowSeconds 秒」的那些点。
  void _resetDistanceAccumulator() {
    _distanceAcc = TrackDistanceAccumulator(_sampler);
    if (_track.isEmpty) return;
    final lastTs = _track.last.timestamp;
    final cutoffMs = lastTs - (_sampler.coherenceWindowSeconds * 1000).round();
    for (final p in _track) {
      if (p.timestamp >= cutoffMs) {
        _distanceAcc.add(p);
      }
    }
  }

  Future<void> _onEnd() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('结束运动'),
        content: Text('距离 $_distanceText\n时长 $_elapsedText'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('结束'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _stopTimer();
    await _submit();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_track.length < 2 || _elapsed.inSeconds < 1) {
      _showMessage('运动时间太短或轨迹点不足，未保存');
      return;
    }
    setState(() => _submitting = true);

    // 用真实开始时间，而不是「当前时间 - 累计时长」反推。
    // 反推在 App 被挂起过的情况下会算出偏晚的开始时间，
    // 一旦晚于第一个轨迹点，后端会判「未来时间戳」把整次运动作废。
    final endTime = DateTime.now().millisecondsSinceEpoch;
    final startTime = _startedAt?.millisecondsSinceEpoch ?? _track.first.timestamp;

    try {
      final activityId = await ref.read(activityRepositoryProvider).create(
            type: _typeCode,
            startTime: startTime,
            endTime: endTime,
            track: _track,
          );
      // 上传成功才清草稿：清早了会丢数据，清晚了下次会重复恢复
      await ref.read(runDraftStorageProvider).clear();
      if (!mounted) return;
      context.pushReplacement('/run-result', extra: activityId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // 上传失败必须保留草稿，让用户可以重试而不是重跑
      _showMessage(e is ApiException ? '$e.message（运动数据已保留，可重试上传）' : '上传失败，请重试');
    }
  }

  /// 离开确认：跑步中误触返回会丢掉整次运动，必须拦一次。
  Future<bool> _confirmLeave() async {
    if (_track.isEmpty || _submitting) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('要放弃这次运动吗？'),
        content: const Text('已记录的数据会保留在本地，下次进入可继续；'
            '但如果之后重新开始，这次的数据会被覆盖。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续运动'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('保留并离开'),
          ),
        ],
      ),
    );
    if (leave == true) {
      // 离开前把草稿写实，确保下次能恢复
      _saveDraft(force: true);
    }
    return leave == true;
  }

  Future<void> _openSettings() => Geolocator.openAppSettings();

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _distanceText => '${(_distanceMeters / 1000).toStringAsFixed(2)} km';

  String get _elapsedText {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get _paceText {
    if (_distanceMeters < 10 || _elapsed.inSeconds == 0) return '—';
    final spk = (_elapsed.inSeconds / (_distanceMeters / 1000.0)).round();
    return Formatters.pace(spk);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 跑步中误触返回会丢掉整次运动。canPop=false 把返回键接管，
      // 由 _confirmLeave 弹确认；用户选「保留并离开」后再手动退出。
      canPop: _track.isEmpty || _submitting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) {
          // 先落草稿再退出，确保下次能恢复
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: switch (_phase) {
          _Phase.checking => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.lg),
                  // GPS 冷启动搜星可能要几十秒，必须让用户知道在做什么，
                  // 否则会被当成"卡死"反复退出重进 —— 那反而让定位更慢。
                  Text('正在获取定位…',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: AppFontSize.body)),
                  const SizedBox(height: AppSpacing.sm),
                  Text('首次定位可能需 30 秒左右，建议在室外或窗边',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: AppFontSize.caption)),
                ],
              ),
            ),
          _Phase.error => _PermissionPrompt(
              icon: Icons.location_off,
              title: '无法获取定位',
              subtitle: _errorMessage,
              actionLabel: !_isDeniedForever
                  ? '重试'
                  : (_openLocationSettings ? '去开启定位' : '去设置'),
              onAction: !_isDeniedForever
                  ? _init
                  : (_openLocationSettings
                      ? () => Geolocator.openLocationSettings()
                      : _openSettings),
            ),
          _Phase.ready => _buildRunBody(),
        },
      ),
    );
  }

  Widget _buildRunBody() {
    return Column(
      children: [
        Expanded(child: _buildMap()),
        _buildStats(),
        _buildControls(),
      ],
    );
  }

  Widget _buildMap() {
    return TrackMap(
      track: _track,
      color: _accent,
      live: true,
      controller: _mapController,
      onMapReady: () => _mapReady = true,
      emptyText: '正在获取定位...',
      loading: true,
    );
  }

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          AppMetricText(
            value: (_distanceMeters / 1000).toStringAsFixed(2),
            unit: 'km',
            valueSize: AppFontSize.metricXl,
            unitSize: AppFontSize.unit,
            color: _accent,
            crossAxisAlignment: CrossAxisAlignment.center,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppMetricText(
            value: _elapsedText,
            valueSize: AppFontSize.display,
            color: AppColors.textPrimary,
            crossAxisAlignment: CrossAxisAlignment.center,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '配速 $_paceText',
            style: const TextStyle(
              fontSize: AppFontSize.title,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting ? null : _togglePause,
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: Text(_paused ? '继续' : '暂停'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ElevatedButton(
              onPressed: _submitting ? null : _onEnd,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('结束'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textHint),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: const TextStyle(
                fontSize: AppFontSize.headline,
                fontWeight: AppFontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
