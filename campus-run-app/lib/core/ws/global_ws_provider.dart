import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/models/chat_message.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'ws_message.dart';

/// 连接状态。
enum GlobalWsStatus { disconnected, connecting, connected }

/// 发送失败异常。
class WsSendException implements Exception {
  const WsSendException(this.message);

  final String message;

  @override
  String toString() => 'WsSendException: $message';
}

/// 全局 WebSocket 单例：登录态存续期间保持连接，断线指数退避重连，
/// 并用 App 生命周期管理避免后台疯狂重连。
final globalWsProvider =
    NotifierProvider<GlobalWsNotifier, GlobalWsStatus>(GlobalWsNotifier.new);

/// 所有收到的 WebSocket 事件的广播流，供页面/根监听订阅。
final wsMessageStreamProvider = StreamProvider<WsMessage>((ref) {
  ref.watch(globalWsProvider);
  return ref.read(globalWsProvider.notifier).messages;
});

class GlobalWsNotifier extends Notifier<GlobalWsStatus>
    with WidgetsBindingObserver {
  /// 心跳间隔。
  ///
  /// ⚠️ 这个值与服务端的空闲回收阈值（`ChatSessionScheduler`，当前 45 秒）
  /// **是耦合的**：服务端只要超过阈值没收到任何消息就会认为连接已死。
  /// 改这里必须同步看那边，倍率保持在 1.5 以上，否则会出现
  /// 「心跳稍慢就被服务端踢掉」→ 反复重连。
  static const Duration _heartbeatInterval = Duration(seconds: 15);

  /// 发出心跳后，等待 pong 的最长时间。
  ///
  /// 超过这个时间还没等到 pong，就判定连接已死并主动重连。
  ///
  /// ## 为什么必须有这个判断（真实故障）
  ///
  /// 原来的心跳**只发不校验**：每 25 秒往 socket 里写一帧就完事，
  /// 从不检查有没有回音。而 socket 半死时（对端消失、NAT 超时、
  /// 运营商回收），写入本地缓冲区**不会抛错** ——
  /// 于是 App 以为自己还连着，实际上什么也收不到。
  ///
  /// 表现就是：好友发了消息，红点要过一分多钟才出现
  /// （因为恢复完全依赖服务端把僵尸连接踢掉）。
  ///
  /// 现在只要一次心跳没有应答就重连，把「发现」的主动权拿回客户端。
  static const Duration _pongTimeout = Duration(seconds: 8);

  /// 判定「该连接已死」的检查周期（比 pong 超时更细，以便及时响应）。
  static const Duration _livenessCheckInterval = Duration(seconds: 3);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _liveness;
  Timer? _reconnect;
  int _attempt = 0;
  bool _manualClose = false;
  bool _connecting = false;

  /// 发出心跳的时刻；收到 pong 后清空。
  ///
  /// null 表示「当前没有待应答的心跳」。
  DateTime? _awaitingPongSince;

  /// 测试用的地址覆盖。
  ///
  /// 测试要验证的是**连接管理逻辑**（心跳、活性判定、重连），
  /// 而这些只有连一条真实的 socket 才有意义。真连生产地址当然不行，
  /// 所以留一个出口让测试指向本地起的假服务端。
  ///
  /// ⚠️ 与 `ExternalLink.debugForceSupported` 同一套路：
  /// 显式开关，而不是靠 `Platform.isAndroid` 之类的环境判断 ——
  /// 那种判断在测试里恒为 false，会让测试**永远走不到真实分支**
  /// （版本号读取上踩过这个坑）。
  @visibleForTesting
  static String? debugUrlOverride;

  /// 是否应该在后台**停止重连**。
  ///
  /// ⚠️ 恒为 false，且**故意做成常量而不是可变字段**。
  ///
  /// 历史上这里是 `bool _suspended`，在 `AppLifecycleState.paused` 时置为 true，
  /// 于是 App 退到后台就停止重连、连接被回收后不再恢复，
  /// **后台期间的消息全部丢失**（用户反馈的「后台不存在时收不到消息」）。
  ///
  /// 保留这个名字是为了让 `_scheduleReconnect` 的守卫读起来仍然自解释；
  /// 做成常量可以避免以后有人又把它设成 true —— 那会把通知功能再次废掉。
  static const bool _shouldSuspendReconnect = false;

  final _messagesController = StreamController<WsMessage>.broadcast();
  final List<_PendingSend> _pending = [];

  Stream<WsMessage> get messages => _messagesController.stream;

  @override
  GlobalWsStatus build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _manualClose = true;
      _teardown();
      _messagesController.close();
    });

    ref.listen(authProvider, (_, next) {
      if (next.value != null) {
        connect();
      } else {
        _manualClose = true;
        disconnect();
      }
    });

    // 冷启动时若已登录（token 持久化）直接连接；connect 自带幂等保护。
    if (ref.read(authProvider).value != null) {
      connect();
    }
    return GlobalWsStatus.disconnected;
  }

  /// App 生命周期变化 —— **后台不再断开 WebSocket**。
  ///
  /// ## 为什么改（真实故障）
  ///
  /// 原来的 `paused` 分支是：
  ///
  /// ```dart
  /// _suspended = true;
  /// _heartbeat?.cancel();     // 停心跳
  /// _reconnect?.cancel();     // 停重连
  /// ```
  ///
  /// 意图是「省电，别在后台疯狂重连」。但实际后果是：
  /// App 一退到后台就停止心跳与重连，连接被运营商 NAT / 服务器回收后
  /// **再也不会恢复**，于是后台期间收到的消息**全部丢失**，
  /// 直到用户切回前台才补连。
  ///
  /// 用户反馈的「后台不存在的时候也收不到消息」正是这个。
  /// 而消息通知的全部意义就在于「App 不在前台时提醒你」——
  /// 现在这样等于把通知功能废掉了（app.dart 里确实调用了
  /// showMessage，但消息根本到不了客户端）。
  ///
  /// ## 现在的行为
  ///
  /// - `paused` / `inactive` / `hidden`：**保持连接与心跳**。
  ///   Android 在 App 处于后台时仍允许已建立的 TCP 连接收发数据，
  ///   所以消息能到达并触发系统通知；
  /// - `resumed`：连接断了才重连（保持原有逻辑）；
  /// - `detached`：什么都不做，进程即将结束。
  ///
  /// ## 耗电问题的处理
  ///
  /// 省电的顾虑是合理的，但正确的做法是**退避**而不是**停掉**：
  /// 心跳间隔 30 秒、TCP keepalive 由系统托管，空闲连接的耗电可忽略；
  /// 而重连本来就有指数退避上限（见 _scheduleReconnect），
  /// 不会出现「后台疯狂重连」。
  ///
  /// ⚠️ 仍然无法覆盖的情况：用户在最近任务里**划掉** App，
  /// 或系统因内存/省电策略杀掉进程 —— 那时没有任何进程在跑，
  /// 只有服务端推送（FCM 等）才能唤醒。这条限制见 docs/site.md。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ⚠️ 回前台时**不能**只看「连接对象是否存在」。
      //
      // 原来的写法是 `if (_channel != null) { ... } else { connect(); }`，
      // 而 `_channel` 只在 `_teardown()` 里被置空 —— 后者只在
      // `onDone` / `onError` 时才触发。半死连接不会触发它们，
      // 于是这个分支**几乎永远走不到**，App 带着一条死连接回到前台，
      // 消息和红点都要等服务端把连接踢掉才恢复。
      //
      // 现在改成：立即发一次心跳做**活性探测**。
      // 收不到 pong 就由 [_liveness] 判定为死连接并重建 ——
      // 这样回前台最多 8 秒就能恢复，而不是原来的 75~150 秒。
      if (_channel != null) {
        if (_heartbeat == null) _startHeartbeat();
        _probeLivenessNow();
      } else if (!_manualClose && ref.read(authProvider).value != null) {
        _reconnect?.cancel();
        _reconnect = null;
        _attempt = 0;
        connect();
      }
      return;
    }

    if (state == AppLifecycleState.detached) {
      // 进程即将结束，不做任何事
      return;
    }

    // paused / inactive / hidden：**保持连接**。
    // 只确保心跳还在跑（某些 ROM 在后台会清掉定时器，这里补一次，幂等）。
    if (_channel != null && _heartbeat == null) {
      _startHeartbeat();
    }
  }

  /// 立刻发一次心跳，并把连接标记为「待应答」。
  ///
  /// 回前台时调用：不等下一个心跳周期，马上确认这条连接是否还活着。
  void _probeLivenessNow() {
    _awaitingPongSince = DateTime.now();
    _sendEnvelope({'type': 'heartbeat'});
  }

  // ── 连接管理 ────────────────────────────────────────────────
  Future<void> connect() async {
    if (_channel != null && state == GlobalWsStatus.connected) return;
    if (_connecting) return;
    _connecting = true;
    try {
      _manualClose = false;
      _reconnect?.cancel();
      _reconnect = null;

      final token = await ref.read(tokenStorageProvider).read();
      if (token == null || token.isEmpty) {
        state = GlobalWsStatus.disconnected;
        return;
      }

      state = GlobalWsStatus.connecting;
      // 新连接尚未收到任何数据 —— 重置标记，
      // 否则「上一次连接活过」会让这一次的失败重试也走「立刻重连」，
      // 退避又失效了。
      _everDelivered = false;
      final ws = debugUrlOverride ??
          AppConfig.baseUrl
              .replaceFirst('https://', 'wss://')
              .replaceFirst('http://', 'ws://');
      final channel = WebSocketChannel.connect(Uri.parse('$ws/ws?token=$token'));
      _channel = channel;
      _sub = channel.stream.listen(
        _onData,
        onError: (Object _) => _onUnexpectedClose(),
        onDone: _onUnexpectedClose,
        cancelOnError: false,
      );
      _startHeartbeat();
      state = GlobalWsStatus.connected;
      _attempt = 0;
    } catch (_) {
      state = GlobalWsStatus.disconnected;
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void disconnect() {
    _teardown();
    state = GlobalWsStatus.disconnected;
  }

  void _teardown() {
    _reconnect?.cancel();
    _reconnect = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _liveness?.cancel();
    _liveness = null;
    _awaitingPongSince = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _failAllPending('连接已断开');
  }

  void _onUnexpectedClose() {
    // ⚠️⚠️ 只在「这条连接**确实通过数据**」时才重置退避。
    //
    // 这里的坑：`_onUnexpectedClose` 既是「已连上的连接断掉了」的入口，
    // 也是「连接失败」的入口 —— 两者混在一起，无条件 `_attempt = 0`
    // 会让失败重试永远停在 1 秒一次：断网期间每 1 秒重连一次，
    // **指数退避完全失效**，网络恢复的瞬间还可能形成重连风暴。
    //
    // 正确的区分方式不是看「为什么断」，而是看「它有没有真的活过」：
    //   · 活过（收到过数据）→ 是意外掉线，要**尽快**恢复，重置退避；
    //   · 没活过（一直失败）→ 是连不上，要**退避**，别给服务端添压。
    //
    // 真机上验证过：关掉移动数据后，日志里反复出现
    // `Unhandled Exception: SocketException: Failed host lookup`，
    // 每次都走这里 —— 就是无条件重置退避造成的。
    if (_everDelivered) _attempt = 0;
    _teardown();
    state = GlobalWsStatus.disconnected;
    if (!_manualClose) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualClose || _shouldSuspendReconnect) return;
    if (_reconnect != null) return;
    final sec = _nextBackoffSeconds();
    _reconnect = Timer(Duration(seconds: sec), () {
      _reconnect = null;
      connect();
    });
  }

  int _nextBackoffSeconds() {
    final sec = backoffSecondsFor(_attempt);
    _attempt = _attempt + 1;
    return sec;
  }

  /// 第 [attempt] 次重连应等待的秒数：1 / 2 / 4 / 8 / 16 / 30（上限 30）。
  ///
  /// 抽成静态纯函数是为了能直接测 —— 退避曲线只看代码不容易判断对错，
  /// 而它出问题时的现象（「断线后要等很久才恢复」）很容易被误判成网络问题。
  @visibleForTesting
  static int backoffSecondsFor(int attempt) {
    final v = 1 << (attempt < 0 ? 0 : attempt);
    return v > 30 ? 30 : v;
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      _heartbeatTicks++;
      // 上一轮的心跳还没等到 pong：说明这条连接已经不中用了。
      // 直接重建，不要再往上叠新的心跳。
      if (_awaitingPongSince != null) {
        _onUnexpectedClose();
        return;
      }
      _awaitingPongSince = DateTime.now();
      _sendEnvelope({'type': 'heartbeat'});
    });

    // 活性看门狗：比心跳更频繁地检查「待应答」是否已超时。
    //
    // ⚠️ 必须独立于心跳定时器：只用「下次心跳时才发现」的话，
    // 发现延迟会叠加上一整个心跳周期（15 秒），而这里 3 秒一查，
    // 判定精度由 [_pongTimeout] 决定。
    _liveness?.cancel();
    _liveness = Timer.periodic(_livenessCheckInterval, (_) {
      final since = _awaitingPongSince;
      if (since == null) return;
      if (DateTime.now().difference(since) <= _pongTimeout) return;
      debugPrint('[WS] 心跳无应答超过 ${_pongTimeout.inSeconds} 秒，判定连接已死，重建');
      _onUnexpectedClose();
    });
  }

  /// 是否正在等 pong。测试用。
  @visibleForTesting
  bool get awaitingPong => _awaitingPongSince != null;

  /// 心跳是否在跑（定时器活着）。测试用 ——
  /// 「发出去了但定时器没跑」和「定时器跑了但发不出去」是两种完全不同的故障。
  @visibleForTesting
  bool get heartbeatActive => _heartbeat?.isActive ?? false;

  /// 已发出/已尝试的心跳次数。测试用。
  @visibleForTesting
  int get heartbeatTicks => _heartbeatTicks;
  int _heartbeatTicks = 0;

  /// 当前这条连接是否**真的收到过数据**。
  ///
  /// 用来区分两种「断开」：连上之后掉线（要立刻重连），
  /// 和压根连不上（要退避）。见 [_onUnexpectedClose]。
  bool _everDelivered = false;

  // ── 收发 ────────────────────────────────────────────────────
  void _onData(dynamic raw) {
    final text = raw is String ? raw : raw.toString();
    final ws = WsMessage.tryParse(text);
    if (ws == null) return;
    // 收到任何一帧都说明这条连接是活的 —— 不局限于 pong。
    // 消息本身就在流动时，没必要因为 pong 被延迟而误判为死连接。
    //
    // 同时记下「这条连接确实活过」：它决定断开后是立刻重连还是退避
    // （见 _onUnexpectedClose）。
    _everDelivered = true;
    _awaitingPongSince = null;
    if (ws.type == WsEventType.ack || ws.type == WsEventType.error) {
      _settlePending(ws);
    }
    _messagesController.add(ws);
  }

  /// 发送聊天消息，返回服务端回执（含真实 messageId）。
  ///
  /// 用 clientMsgId 与 ack/error 精确配对（见 [_settlePending]），
  /// 不再依赖 FIFO —— FIFO 在「ack 与 error 乱序到达」或「某一帧丢失」时会错配，
  /// 把 A 的失败算到 B 头上、或让 A 永久挂起到超时。
  ///
  /// [type] 与 [mediaUrl] 用于图片（2）与表情包（3）消息；
  /// 文本消息保持不传，报文形态与旧版本完全一致。
  Future<ChatMessage> sendMessage({
    required int receiverId,
    required String content,
    int? type,
    String? mediaUrl,
  }) {
    if (_channel == null || state != GlobalWsStatus.connected) {
      return Future.error(const WsSendException('网络未连接'));
    }
    final clientMsgId = _nextClientMsgId();
    final completer = Completer<ChatMessage>();
    final timer = Timer(const Duration(seconds: 10), () {
      _pending.removeWhere((p) => p.completer == completer);
      if (!completer.isCompleted) {
        completer.completeError(const WsSendException('发送超时'));
      }
    });
    _pending.add(_PendingSend(clientMsgId, completer, timer));
    _sendEnvelope({
      'type': 'message',
      'data': {
        'receiverId': receiverId,
        'content': content,
        'clientMsgId': clientMsgId,
        // 只在有值时带上：文本消息的报文与旧版本字节一致
        if (type != null) 'type': type,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
      },
    });
    return completer.future;
  }

  int _clientMsgSeq = 0;

  String _nextClientMsgId() {
    _clientMsgSeq += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_clientMsgSeq';
  }

  void _settlePending(WsMessage ws) {
    if (_pending.isEmpty) return;
    final id = ws.data?['clientMsgId'] as String?;
    // 优先按 clientMsgId 精确匹配；兼容性兜底：没有 id 时退化为最早一条。
    int index = id == null ? 0 : _pending.indexWhere((p) => p.clientMsgId == id);
    if (index < 0) index = 0;
    final p = _pending.removeAt(index);
    p.timer.cancel();
    if (ws.type == WsEventType.ack) {
      final data = ws.data;
      if (data == null) {
        if (!p.completer.isCompleted) {
          p.completer.completeError(const WsSendException('服务器响应异常'));
        }
      } else if (!p.completer.isCompleted) {
        p.completer.complete(ChatMessage.fromJson(data));
      }
    } else {
      final msg = ws.data?['message'] as String? ?? '发送失败';
      if (!p.completer.isCompleted) {
        p.completer.completeError(WsSendException(msg));
      }
    }
  }

  void _sendEnvelope(Map<String, dynamic> envelope) {
    try {
      _channel?.sink.add(jsonEncode(envelope));
    } catch (_) {}
  }

  void _failAllPending(String reason) {
    for (final p in _pending) {
      p.timer.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(WsSendException(reason));
      }
    }
    _pending.clear();
  }
}

class _PendingSend {
  _PendingSend(this.clientMsgId, this.completer, this.timer);

  /// 客户端生成的关联 id：后端会在 ack/error 里原样回显，
  /// 用它精确配对「哪一次发送」，而不是按 FIFO 猜（乱序或丢包时 FIFO 会错配）。
  final String clientMsgId;
  final Completer<ChatMessage> completer;
  final Timer timer;
}
