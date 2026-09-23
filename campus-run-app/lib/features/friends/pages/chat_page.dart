import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/config/app_config.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/chat_message.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/message_provider.dart';

/// 一对一聊天页：加载历史 + WebSocket 实时收发。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.friendId, required this.friendName});

  final int friendId;
  final String friendName;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _historyLoading = true;

  int get _myId => ref.read(authProvider).value?.userId ?? 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadHistory();
    await _connect();
  }

  Future<void> _loadHistory() async {
    try {
      final page = await ref.read(messageHistoryProvider(widget.friendId).future);
      // 后端按 messageId 倒序返回，转成旧→新用于展示。
      setState(() {
        _messages
          ..clear()
          ..addAll(page.list.reversed);
        _historyLoading = false;
      });
      _scrollToBottom();
    } catch (_) {
      setState(() => _historyLoading = false);
    }
  }

  Future<void> _connect() async {
    final token = await ref.read(tokenStorageProvider).read();
    if (token == null || token.isEmpty) return;
    final base = AppConfig.baseUrl;
    final ws = base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final channel = WebSocketChannel.connect(Uri.parse('$ws/ws?token=$token'));
    _channel = channel;
    _sub = channel.stream.listen(
      _onMessage,
      onError: (_) {},
      onDone: () {},
    );
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      _send({ 'type': 'heartbeat' });
    });
  }

  void _onMessage(dynamic data) {
    try {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      final type = map['type'];
      if (type == 'message') {
        final msg = ChatMessage.fromJson(map['data'] as Map<String, dynamic>);
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
      // 'ack' 为发送确认，乐观展示已足够，忽略即可。
    } catch (_) {}
  }

  void _send(Map<String, dynamic> envelope) {
    _channel?.sink.add(jsonEncode(envelope));
  }

  void _handleSend() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    // 乐观展示 + 通过 WebSocket 发送。
    setState(() {
      _messages.add(ChatMessage(
        messageId: -DateTime.now().millisecondsSinceEpoch,
        senderId: _myId,
        receiverId: widget.friendId,
        content: content,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _send({
      'type': 'message',
      'data': {'receiverId': widget.friendId, 'content': content},
    });
    _controller.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.friendName)),
      body: Column(
        children: [
          Expanded(
            child: _historyLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const _EmptyChat()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) =>
                            _Bubble(message: _messages[i], mine: _messages[i].senderId == _myId),
                      ),
          ),
          _InputBar(controller: _controller, onSend: _handleSend),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.content,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: mine ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              Formatters.timeOfEpoch(message.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: mine ? Colors.white.withValues(alpha: 0.7) : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        color: AppColors.card,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: '发消息…',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSend,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('还没有消息，打个招呼吧', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
    );
  }
}
