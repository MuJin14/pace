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
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _attempt = 0;
  bool _manualClose = false;
  bool _connecting = false;

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
      if (_channel != null) {
        if (_heartbeat == null) _startHeartbeat();
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
      final ws = AppConfig.baseUrl
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
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _failAllPending('连接已断开');
  }

  void _onUnexpectedClose() {
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
    final exp = _attempt;
    _attempt = _attempt + 1;
    final v = 1 << exp; // 1 / 2 / 4 / 8 / 16 / 32…
    return v > 30 ? 30 : v;
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      _sendEnvelope({'type': 'heartbeat'});
    });
  }

  // ── 收发 ────────────────────────────────────────────────────
  void _onData(dynamic raw) {
    final text = raw is String ? raw : raw.toString();
    final ws = WsMessage.tryParse(text);
    if (ws == null) return;
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
