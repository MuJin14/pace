import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/media_url.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/image_viewer.dart';
import '../../../core/widgets/scrollable_center.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/ws/global_ws_provider.dart';
import '../../../core/ws/ws_message.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/repositories/message_repository.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/friend_badge_provider.dart';
import '../providers/message_provider.dart';
import '../services/chat_notification_service.dart';
import '../utils/chat_time_grouping.dart';
import '../utils/emoji_catalog.dart';
import '../utils/notify_policy.dart';

/// 一对一聊天页：加载历史 + 订阅全局 WebSocket 实时收发。
///
/// 三态：加载中 / 错误（可重试）/ 空态（召唤语 + 「打个招呼」动作）。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.friendId,
    required this.friendName,
    this.friendAvatarUrl,
  });

  final int friendId;
  final String friendName;

  /// 从上一页带过来的头像，先渲染出来避免标题栏闪一下；
  /// 真正的头像由 userProfileProvider 拉取后覆盖（保证改过头像也能更新）。
  final String? friendAvatarUrl;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

/// 聊天页右上角菜单的动作。
enum _ChatMenuAction { profile, history }

/// 标题栏：头像 + 昵称，整块可点进对方主页（与微信一致）。
///
/// 头像优先用拉取到的 profile，其次用上一页传进来的，最后退回昵称首字。
class _TitleBar extends ConsumerWidget {
  const _TitleBar({
    required this.friendId,
    required this.fallbackName,
    this.fallbackAvatarUrl,
  });

  final int friendId;
  final String fallbackName;
  final String? fallbackAvatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(friendId)).value;
    final name = profile?.nickname ?? fallbackName;
    final avatar = profile?.avatarUrl ?? fallbackAvatarUrl;

    return InkWell(
      onTap: () => context.push('/user/$friendId'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(nickname: name, avatarUrl: avatar, size: 32),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: AppFontWeight.medium,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  final List<ChatMessage> _messages = [];

  /// 已读回执（后端 ChatMessageResponse.readAt）适配：字段缺失时集合为空，不影响渲染。
  final Set<int> _readIds = <int>{};

  StreamSubscription<WsMessage>? _sub;
  bool _historyLoading = true;
  String? _historyError;

  /// 图片上传中：用于禁用「+」按钮并显示进度，避免并发上传同一张图。
  bool _uploading = false;

  /// emoji / 贴图面板是否展开。
  bool _showEmojiPanel = false;

  /// 当前登录用户 id。
  ///
  /// **只用于事件回调**（如乐观消息的 senderId）—— 那里读取即时值是正确的。
  /// **渲染路径不要用它**：`ref.read` 不订阅登录态，首帧会拿到 0，
  /// 导致消息归属判断失真。渲染请用 `build()` 里 `ref.watch` 得到的 myId。
  // ⚠️ 兜底值用 -1（未知），**不用 0** —— 0 是合法用户 id（管理员）。
  // 用 0 兜底会让 0 号用户把自己的消息看成「别人发的」、或反之。
  int get _currentUserId =>
      ref.read(authProvider).value?.userId ?? kUnknownUserId;

  @override
  void initState() {
    super.initState();
    // 不能在 initState 内直接改 provider：此时正处于 widget tree 构建阶段，
    // Riverpod 会抛「Tried to modify a provider while the widget tree was building」。
    // 推迟到本帧结束后的微任务里执行（此处 ref 仍可用，因为 widget 还 mounted）。
    Future.microtask(() {
      if (!mounted) return;
      ref.read(currentChatFriendIdProvider.notifier).set(widget.friendId);
      // 打开会话即视为已读：清掉「社区页那一行」的未读红点。
      // 不在这里清的话，用户读完消息回到列表仍会看到红点，以为还有新消息。
      ref.read(friendBadgeProvider.notifier).clearFriend(widget.friendId);
      // ⚠️ 通知权限**不在这里申请**了。
      //
      // 原先的注释写着「此刻用户已经理解这个 App 会收到好友消息，同意率更高」，
      // 但那形成了一个死循环：不进聊天页 → 拿不到通知权限 → 收不到消息 →
      // 用户以为没人发消息 → 更不会进聊天页（用户反馈的正是这个现象）。
      // 现在统一在启动时申请，见 lib/app.dart 的 _ensurePermissions()。
      // 进入会话即清掉该好友的通知，避免「看着消息还留着通知」
      ChatNotificationService.instance.cancelFor(widget.friendId);
    });
    _sub = ref.read(globalWsProvider.notifier).messages.listen(_onWsMessage);
    _init();
  }

  Future<void> _init() async {
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() {
        _historyLoading = true;
        _historyError = null;
      });
    }
    try {
      ref.invalidate(messageHistoryProvider(widget.friendId));
      final page = await ref.read(messageHistoryProvider(widget.friendId).future);
      if (!mounted) return;
      // 后端按 messageId 倒序返回，转成旧→新用于展示。
      setState(() {
        _messages
          ..clear()
          ..addAll(page.list.reversed);
        // 拉取历史时后端已把「发给我的未读消息」标记为已读，据此回填「已读」态。
        _readIds
          ..clear()
          ..addAll(page.list
              .where((m) => m.readAt != null)
              .map((m) => m.messageId));
        _historyLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _historyError = e is ApiException ? e.message : '聊天记录加载失败，请稍后重试';
      });
    }
  }

  /// 右上角「三个点」菜单：看 TA 的主页 / 查聊天记录。
  void _onMenuAction(_ChatMenuAction action) {
    switch (action) {
      case _ChatMenuAction.profile:
        context.push('/user/${widget.friendId}');
      case _ChatMenuAction.history:
        context.push(
          '/chat/${widget.friendId}/history',
          extra: widget.friendName,
        );
    }
  }

  void _onWsMessage(WsMessage ws) {
    // 已读回执：后端把「对端读取了本会话」的消息 id 列表推给原发送方（即我方）。
    if (ws.type == WsEventType.readReceipt) {
      final ids = (ws.data?['messageIds'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList();
      if (ids == null || ids.isEmpty) return;
      setState(() => _readIds.addAll(ids));
      return;
    }

    if (ws.type != WsEventType.message) return;
    final data = ws.data;
    if (data == null) return;
    final msg = ChatMessage.fromJson(data);
    // 可选适配：消息体带 readAt 即视为对端已读（后端消息帧不含该字段时走不到这里）。
    final hasReceipt = data['readAt'] != null;
    // 只追加与本会话相关的消息（对端发来）。
    final related = msg.senderId == widget.friendId || msg.receiverId == widget.friendId;
    if (!hasReceipt && !related) return;
    setState(() {
      if (hasReceipt) _readIds.add(msg.messageId);
      if (related) _messages.add(msg);
    });
    if (related) _scrollToBottom();
  }

  /// 发送一条消息。
  ///
  /// [type] / [mediaUrl] 用于图片（2）与表情包（3）；文本消息不传（默认 1）。
  /// 乐观消息必须**带上同样的 type/mediaUrl**，否则在服务端回执到达前
  /// 会先按文本气泡渲染一次，视觉上闪一下再变成图片。
  Future<void> _sendContent(
    String content, {
    int? reuseId,
    int? type,
    String? mediaUrl,
  }) async {
    final tempId = reuseId ?? -DateTime.now().millisecondsSinceEpoch;
    setState(() {
      if (reuseId != null) {
        final i = _messages.indexWhere((m) => m.messageId == reuseId);
        if (i >= 0) _messages[i] = _messages[i].copyWith(failed: false);
      } else {
        _messages.add(ChatMessage(
          messageId: tempId,
          senderId: _currentUserId,
          receiverId: widget.friendId,
          content: content,
          type: type ?? 1,
          mediaUrl: mediaUrl,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    });
    _scrollToBottom();

    try {
      final real = await ref.read(globalWsProvider.notifier).sendMessage(
            receiverId: widget.friendId,
            content: content,
            // 文本消息不传 type，保持与旧版本一致的报文形态
            type: (type == null || type == 1) ? null : type,
            mediaUrl: mediaUrl,
          );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.messageId == tempId);
        if (i >= 0) _messages[i] = real;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.messageId == tempId);
        if (i >= 0) _messages[i] = _messages[i].copyWith(failed: true);
      });
    }
  }

  void _handleSend() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    _controller.clear();
    _sendContent(content);
  }

  /// 从相册选图 → 上传 → 发图片消息。
  ///
  /// 从相册选图并发送。
  Future<void> _pickAndSendImage() =>
      _pickAndSend(source: ImageSource.gallery);

  /// 拍照并发送。
  ///
  /// 与相册是**同一个方法**，只有 source 不同：压缩参数、上传、
  /// 错误处理、失败时不留脏消息这些逻辑必须完全一致，
  /// 分成两份实现迟早会漂移。
  Future<void> _takePhotoAndSend() =>
      _pickAndSend(source: ImageSource.camera);

  /// 选图/拍照 → 压缩 → 上传 → 发消息。
  ///
  /// 分两步（上传 + 发消息）而不是合成一个接口：
  /// 上传失败时**不产生任何消息**（用户只会看到「上传失败」），
  /// 比先插一条永远加载不出来的图片消息好得多。
  ///
  /// ⚠️ `maxWidth/maxHeight/imageQuality` 不是可选项：
  /// 手机原图动辄 4000×3000、8-12MB，而服务端上限 2MB。
  /// 不压缩会在上传阶段被拒，用户看到的是「图片发送失败」——
  /// 他只会以为是网络问题，反复重试。
  Future<void> _pickAndSend({required ImageSource source}) async {
    if (_uploading) return;
    final messenger = ScaffoldMessenger.of(context);
    // 选图/拍照前先收起面板，否则相机界面回来后面板还盖着
    _dismissPanels();
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked == null) return; // 用户取消

      setState(() => _uploading = true);
      final filename = picked.name.isEmpty ? 'chat.jpg' : picked.name;
      // 读字节再上传：Web 上 XFile.path 是 blob URL，MultipartFile.fromFile 不可用
      final bytes = await picked.readAsBytes();

      // 客户端先自检大小，避免白传一次 2MB 再被服务端拒。
      // 正常情况下 pickImage 压缩后远小于此值；这里兜底的是
      // 「imageQuality 在某些机型上不生效」的情况。
      const maxBytes = 2 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (!mounted) return;
        setState(() => _uploading = false);
        messenger.showSnackBar(const SnackBar(
          content: Text('图片太大（压缩后仍超过 2MB），请换一张或先裁剪'),
        ));
        return;
      }

      if (!mounted) return;
      final url = await ref
          .read(messageRepositoryProvider)
          .uploadChatImage(bytes, filename);
      if (!mounted) return;
      setState(() => _uploading = false);

      await _sendContent('', type: 2, mediaUrl: url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      messenger.showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '图片发送失败，请重试')),
      );
    }
  }

  /// 发送内置表情包（type=3）。
  ///
  /// 贴图是打包进 App 的静态资源，用 `asset:` 前缀表示 ——
  /// 与网络图片区分开，渲染时直接走 `AssetImage`，不需要走网络也不需要服务端上传。
  Future<void> _sendSticker(String assetName) async {
    setState(() => _showEmojiPanel = false);
    await _sendContent('', type: 3, mediaUrl: 'asset:$assetName');
  }

  /// 在当前光标处插入 emoji（文本消息，不是贴图）。
  ///
  /// 表情面板里的 emoji 走**文本消息**：它们是 Unicode 字符，
  /// 没必要为每个 emoji 单独存一张图；只有「表情包贴图」才需要 type=3。
  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    // 光标无效时（如首次聚焦）追加到末尾，而不是丢弃输入
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _inputFocus.requestFocus();
  }

  /// 空态动作：帮用户写好第一句招呼并聚焦输入框。
  void _draftGreeting() {
    const greeting = '你好，一起去跑步吗？';
    _controller.text = greeting;
    _controller.selection = TextSelection.collapsed(offset: greeting.length);
    _inputFocus.requestFocus();
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
    _sub?.cancel();
    // ⚠️⚠️ 「离开这个会话」必须在这里明确登记。
    //
    // 这条曾经是**注释承诺、代码缺失**，并因此造成了一个很难发现的 bug：
    //
    //   原文写着「清理改由 app.dart 的消息处理器负责」——
    //   但 app.dart 里根本没有那个逻辑。于是
    //   `currentChatFriendIdProvider` **只在进入聊天页时被 set，
    //   从来没有被清空过**。
    //
    //   后果：一旦打开过和某人的会话，App 就永远认为你还在看那个会话。
    //   之后 ta 发来的每条消息都被 decideNotifyAction 判为
    //   「正在看这个会话」→ 先加红点、随即立刻清掉 →
    //   **红点永远不亮**；而用户「点进去又能看到消息」（服务端数据是对的）。
    //
    //   表现极具误导性：看起来像「消息没收到」，真因却相反
    //   （收到了，但被当成已读吞掉了）。
    //
    // 为什么可以在这里调 ref：dispose 不在构建阶段，`ref.read` 是合法的；
    // initState 里用 Future.microtask 是因为那里处在构建阶段，两者不矛盾。
    // 用 clearIf 而不是 clear：万一用户已经进了另一个会话（快速切换），
    // 不能把新的会话标记误清掉。
    try {
      // ⚠️ 退出会话时**也要清红点**。
      //
      // 与 initState 里那次是两件事，缺一不可：
      //   · initState：进来时清掉「之前积累的」未读；
      //   · dispose  ：把「在这个会话里新收到的」也一并清掉 ——
      //     因为这些消息用户都已经看过了。
      //
      // 不做这一步的话：用户看完消息返回列表，那一行还挂着红点，
      // 看起来像「还有没读的」，实际是刚读过的。而红点一旦留在那里，
      // 下次有新消息会更加看不出来。
      ref.read(friendBadgeProvider.notifier).clearFriend(widget.friendId);
      // 「当前正在看的会话」标记同样要清：不清的话 App 会一直以为
      // 你还在看这个会话，之后该好友的消息会被判成「已在眼前」而不弹通知。
      ref.read(currentChatFriendIdProvider.notifier).clearIf(widget.friendId);
    } catch (e) {
      // 极端情况（ProviderScope 已拆）下清理会失败。不能因为清理失败就崩溃，
      // 但要留痕 —— 它会导致「该好友的红点清不掉」或「之后不弹通知」。
      debugPrint('[聊天] 退出会话时清理失败: $e');
    }
    _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 构建消息区。`myId` 由 [build] 传入（那里用 `ref.watch` 订阅了登录态），
  /// **不要**在这里再 `ref.read(authProvider)` —— 那只读一次、不订阅，
  /// 首次构建时登录态还没解析完就会拿到 null，进而把「我发的」全部误判为
  /// 「收到的」（见文件顶部说明的切账号 bug）。
  Widget _buildHistory(int myId) {
    if (_historyLoading) {
      return const ScrollableCenter(child: CircularProgressIndicator());
    }
    if (_historyError != null) {
      return ScrollableCenter(
        child: ErrorState(message: _historyError!, onRetry: _loadHistory),
      );
    }
    if (_messages.isEmpty) {
      return ScrollableCenter(
        child: EmptyState(
          icon: Icons.chat_bubble_outline,
          title: '开启第一句问候',
          subtitle: '和「${widget.friendName}」打个招呼，一起跑一段',
          actionLabel: '打个招呼',
          onAction: _draftGreeting,
        ),
      );
    }
    // 按 5 分钟间隔插入时间分隔条：
    // 连续对话不被打断，隔了一段时间再聊时才有一条时间标记，
    // 否则「昨天聊的」和「刚刚聊的」在视觉上连成一片，分不清上下文。
    final items = groupMessagesByTime(_messages);

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is ChatTimeSeparator) {
          return _TimeSeparator(timestamp: item.timestamp);
        }
        final msg = (item as ChatMessageItem).message;
        return _Bubble(
          message: msg,
          // 归属只由「消息自带 senderId」与「当前登录 userId」决定，
          // 与会话对象 friendId 无关。
          mine: msg.senderId == myId,
          read: _readIds.contains(msg.messageId),
          // ⚠️ 重试必须带上原来的 type / mediaUrl：
          // 少了它们，图片消息重试会变成一条**空的文本消息**（content 本来就是 ''），
          // 用户看到「重试成功」但对方收到的是空白 —— 比失败更糟。
          onRetry: msg.failed
              ? () => _sendContent(
                    msg.content,
                    reuseId: msg.messageId,
                    type: msg.type,
                    mediaUrl: msg.mediaUrl,
                  )
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 用 ref.watch（而不是 ref.read）订阅登录态：
    //  1. 订阅会在登录态解析完成后触发重建，消息归属才能拿到正确的 userId；
    //     ref.read 只读一次、不订阅，首帧 userId 为 null → 所有消息被判为「收到的」。
    //  2. 同设备切换账号时会重新构建，归属随之翻转。
    // 同上：0 是合法 id，兜底必须用 kUnknownUserId。
    final myId = ref.watch(authProvider).value?.userId ?? kUnknownUserId;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _TitleBar(
          friendId: widget.friendId,
          fallbackName: widget.friendName,
          fallbackAvatarUrl: widget.friendAvatarUrl,
        ),
        actions: [
          // 微信式：右上角「三个点」→ 看 TA 的主页 / 查聊天记录
          PopupMenuButton<_ChatMenuAction>(
            icon: const Icon(Icons.more_horiz),
            tooltip: '更多',
            onSelected: _onMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ChatMenuAction.profile,
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 18),
                    SizedBox(width: AppSpacing.sm),
                    Text('查看 TA 的主页'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.history,
                child: Row(
                  children: [
                    Icon(Icons.history, size: 18),
                    SizedBox(width: AppSpacing.sm),
                    Text('查看聊天记录'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            // 点消息区 = 收起表情面板 + 收起键盘。
            // 之前面板只能靠再按一次按钮关闭，用户点空白处没反应会以为「卡住了」。
            // 用 GestureDetector 而不是 InkWell：这里不需要水波纹，
            // 且 behavior 必须显式设成 translucent，否则空白区域收不到点击。
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissPanels,
              child: RefreshIndicator(
                onRefresh: _loadHistory,
                child: _buildHistory(myId),
              ),
            ),
          ),
          _InputBar(
            controller: _controller,
            focusNode: _inputFocus,
            onSend: _handleSend,
            onPickImage: _pickAndSendImage,
            onTakePhoto: _takePhotoAndSend,
            onToggleEmoji: _toggleEmojiPanel,
            uploading: _uploading,
            emojiPanelOpen: _showEmojiPanel,
          ),
          // 表情面板：展开时占据输入栏下方，不遮挡消息区
          if (_showEmojiPanel)
            _EmojiPanel(
              onEmoji: _insertEmoji,
              onSticker: _sendSticker,
              onClose: _dismissPanels,
            ),
        ],
      ),
    );
  }

  /// 收起表情面板与键盘。
  ///
  /// 空态检查放在这里而不是调用点：调用点有三处（点消息区、面板里的收起按钮、
  /// 发送消息后），每处都写判断容易漏，而且 setState 在已经收起时会多一次无谓重建。
  void _dismissPanels() {
    if (!_showEmojiPanel && !_inputFocus.hasFocus) return;
    setState(() => _showEmojiPanel = false);
    _inputFocus.unfocus();
  }

  /// 切换表情面板。
  ///
  /// 打开时**主动收起键盘**：两者同时出现会把消息区挤得只剩一条缝，
  /// 而且键盘会盖住面板（面板在 Column 下方）。
  void _toggleEmojiPanel() {
    final opening = !_showEmojiPanel;
    setState(() => _showEmojiPanel = opening);
    if (opening) {
      _inputFocus.unfocus();
    }
  }
}

/// emoji 与表情包面板。
///
/// 两组内容：
/// - **emoji**：插入到输入框（文本消息），用 Unicode 字符，不需要上传；
/// - **表情包**：直接发送（type=3），指向内置贴图资源。
///
/// 项目当前未附带贴图文件，`stickerAssets` 为空时**自动隐藏贴图分组**，
/// 而不是显示一堆加载失败的破图。
class _EmojiPanel extends StatefulWidget {
  const _EmojiPanel({
    required this.onEmoji,
    required this.onSticker,
    this.onClose,
  });

  final ValueChanged<String> onEmoji;
  final ValueChanged<String> onSticker;

  /// 收起面板。面板本身不持有 `_showEmojiPanel`，由父层传入。
  final VoidCallback? onClose;

  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<_EmojiPanel> {
  /// 是否切到「表情包」页签。
  bool _stickersTab = false;

  @override
  Widget build(BuildContext context) {
    final showStickers = hasStickers && _stickersTab;
    return Container(
      height: 200,
      color: AppColors.surface,
      child: Column(
        children: [
          Row(
            children: [
              if (hasStickers) ...[
                _PanelTab(
                  label: '表情',
                  selected: !_stickersTab,
                  onTap: () => setState(() => _stickersTab = false),
                ),
                _PanelTab(
                  label: '表情包',
                  selected: _stickersTab,
                  onTap: () => setState(() => _stickersTab = true),
                ),
              ] else
                // 没有贴图资源时不显示页签，但保留标题位置，
                // 避免面板看起来「上面空一块」
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    '表情',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const Spacer(),
              // 显式的收起入口。之前只能靠再按一次输入栏的表情按钮，
              // 用户点空白处没反应就以为「面板下不去了」。
              if (widget.onClose != null)
                IconButton(
                  tooltip: '收起',
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary),
                  onPressed: widget.onClose,
                ),
            ],
          ),
          Expanded(
            child: showStickers
                ? _StickerGrid(
                    onTap: widget.onSticker,
                  )
                : _EmojiGrid(onTap: widget.onEmoji),
          ),
        ],
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.body,
                fontWeight: selected ? AppFontWeight.bold : AppFontWeight.regular,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Container(
              height: 2,
              width: 20,
              color: selected ? AppColors.primary : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

/// emoji 网格：按分组展示，带分组标题。
class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      children: [
        for (final entry in emojiGroups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              entry.key,
              style: const TextStyle(
                fontSize: AppFontSize.caption,
                color: AppColors.textHint,
              ),
            ),
          ),
          Wrap(
            children: [
              for (final emoji in entry.value)
                InkWell(
                  onTap: () => onTap(emoji),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 表情包网格：点击直接发送。
class _StickerGrid extends StatelessWidget {
  const _StickerGrid({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final asset in stickerAssets)
          InkWell(
            onTap: () => onTap(asset),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Image.asset(
                'assets/stickers/$asset',
                fit: BoxFit.contain,
                // 贴图缺失时显示占位而不是崩溃
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 时间分隔条：微信风格的居中灰字胶囊。
///
/// 只在相邻消息间隔 > 5 分钟（或会话开头）出现，见 [groupMessagesByTime]。
class _TimeSeparator extends StatelessWidget {
  const _TimeSeparator({required this.timestamp});

  final int timestamp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.smLg),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            formatChatSeparator(timestamp),
            style: const TextStyle(
              fontSize: AppFontSize.hint,
              color: AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.read,
    this.onRetry,
  });

  final ChatMessage message;
  final bool mine;

  /// 对端已读（可选适配：无回执时恒为 false）。
  final bool read;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final metaColor = mine
        ? AppColors.onPrimary.withValues(alpha: 0.7)
        : AppColors.textHint;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.gap10),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gap14,
          vertical: AppSpacing.gap10,
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.md),
            topRight: const Radius.circular(AppRadius.md),
            bottomLeft: Radius.circular(mine ? AppRadius.md : AppRadius.xs),
            bottomRight: Radius.circular(mine ? AppRadius.xs : AppRadius.md),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 媒体消息与文本消息分别渲染：
            // 图片/贴图不应该包在文字气泡内边距里，否则四周会多出一圈留白。
            if (message.isImage || message.isSticker)
              _MediaContent(message: message, mine: mine)
            else
              Text(
                message.content,
                style: TextStyle(
                  fontSize: AppFontSize.body,
                  height: 1.35,
                  color: mine ? AppColors.onPrimary : AppColors.textPrimary,
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.failed) ...[
                  InkWell(
                    onTap: onRetry,
                    child: Text(
                      '发送失败，点击重试',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: AppFontWeight.bold,
                        color: mine ? AppColors.onPrimary : AppColors.danger,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.gap6),
                ],
                Text(
                  Formatters.timeOfEpoch(message.timestamp),
                  style: TextStyle(fontSize: AppFontSize.caption, color: metaColor),
                ),
                if (mine && read && !message.failed) ...[
                  const SizedBox(width: AppSpacing.gap6),
                  Text(
                    '已读',
                    style: TextStyle(fontSize: AppFontSize.caption, color: metaColor),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 媒体消息内容（图片 / 表情包）。
///
/// 两种来源：
/// - `asset:` 前缀 → 内置贴图资源（`AssetImage`）；
/// - 其它 → 服务端上传后的 URL（`NetworkImage`）。
///
/// 刻意**不使用** `Image.network`：它在真机弱网下会先失败再重试，
/// 控制台刷一堆异常；`Image(image: NetworkImage(...))` 配合 `errorBuilder`
/// / `loadingBuilder` 能给出明确的加载态与失败占位。
class _MediaContent extends ConsumerWidget {
  const _MediaContent({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  bool get _isAsset => (message.mediaUrl ?? '').startsWith('asset:');

  String get _assetPath => (message.mediaUrl ?? '').replaceFirst('asset:', '');

  /// 媒体地址为空时的文案。
  ///
  /// 空 URL 有两种来源，必须区分，否则用户会把正常策略当成故障：
  ///   · **保留策略过期** —— 后端到期后删文件并把 media_url 置空
  ///     （保留消息，避免聊天记录凭空少几条）。这是预期行为；
  ///   · 脏数据 —— 异常情况，值得反馈。
  ///
  /// 用**时间**来分辨：既然 URL 已经没了，能用的证据只剩「这条消息多久了」。
  /// 比保留期还老 → 预期过期；否则 → 当成数据异常。
  ///
  /// ⚠️ 这里的天数是**客户端认为的**保留期。若后端把
  /// `app-media.retention-days` 改短，这里应同步改，否则会出现
  /// 「文件其实已经删了、但 App 还显示 [图片]」的窗口期。
  /// 纯展示文案，判断偏差不影响任何数据。
  static const int _retentionDays = 90;

  String _emptyMediaLabel() {
    final ts = message.timestamp;
    final expired = ts > 0 &&
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(ts))
                .inDays >=
            _retentionDays;
    if (expired) {
      return message.isImage ? '[图片已过期]' : '[表情已过期]';
    }
    return message.isImage ? '[图片]' : '[表情]';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = message.mediaUrl;
    // 媒体地址缺失（数据异常或旧数据）：显示明确占位，不留白块
    if (url == null || url.isEmpty) {
      return Text(
        _emptyMediaLabel(),
        style: TextStyle(
          fontSize: AppFontSize.body,
          color: mine ? AppColors.onPrimary : AppColors.textSecondary,
        ),
      );
    }

    // 服务端存的是绝对地址（域名写死在库里）。那个域名一旦对客户端不可达，
    // 图片就全部加载失败 —— 而 App 本身连得上服务器。
    // 统一改写成当前连接地址（表情包走 asset:，不受影响）。
    final resolvedUrl = resolveMediaUrl(ref, url);

    // 缩略图优先。
    //
    // 服务端上行带宽只有约 0.2–0.46 MB/s，而这里是**列表**：
    // 直接拉原图每张要 5–10 秒，一屏几张就是几十秒，用户感受是「图片加载巨慢」。
    // 400px 缩略图通常 20–40KB，快两个数量级。
    // 内置贴图（asset:）不走服务器，这里会拿到 null 而回退原地址。
    final thumbUrl = resolveThumbUrl(ref, url, width: message.isSticker ? 160 : 400);
    final listUrl = thumbUrl ?? resolvedUrl ?? url;

    // 贴图（表情包）比图片小：它是「表情」而不是「照片」
    final maxSide = message.isSticker ? 120.0 : 220.0;

    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxSide, maxHeight: maxSide * 1.4),
        child: _isAsset
            ? Image.asset(
                _assetPath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _broken(mine),
              )
            : Image.network(
                listUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return SizedBox(
                    width: 120,
                    height: 120,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress.expectedTotalBytes == null
                            ? null
                            : progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => _broken(mine),
              ),
      ),
    );

    // ⚠️ 缩略图必须可点开。
    //
    // 之前这里是个「死」缩略图：220×308 的裁切展示，用户既看不清、
    // 也拿不到原图 —— 收到一张图却无法放大、无法保存，
    // 等于图片功能只做了一半。
    //
    // 内置贴图不挂点击：它本来就是表情，尺寸固定、没有「原图」可看。
    if (_isAsset) return thumbnail;

    final heroTag = 'chat-media-${message.messageId}';
    return GestureDetector(
      // 点开看**原图**：缩略图放大会很糊，用户要的是能看清、能保存
      onTap: () =>
          showImageViewer(context, url: resolvedUrl ?? url, heroTag: heroTag),
      child: Hero(tag: heroTag, child: thumbnail),
    );
  }

  /// 加载失败占位：明确告诉用户「图挂了」，而不是留一个空白气泡。
  Widget _broken(bool mine) {
    return Container(
      width: 120,
      height: 120,
      color: mine ? AppColors.primaryDark : AppColors.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: mine ? AppColors.onPrimary : AppColors.textHint,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '图片加载失败',
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: mine ? AppColors.onPrimary : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onPickImage,
    required this.onTakePhoto,
    required this.onToggleEmoji,
    required this.uploading,
    required this.emojiPanelOpen,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onTakePhoto;
  final VoidCallback onToggleEmoji;

  /// 图片上传中：禁用「+」并显示进度，避免重复上传。
  final bool uploading;

  /// 表情面板是否展开 —— 用来把按钮图标切成「键盘」，
  /// 让用户一眼看出「再按一次会回到键盘」。
  final bool emojiPanelOpen;

  /// 「+」的选项菜单。
  ///
  /// 之前「+」直接开相册，**没有拍照入口** —— 聊天里想随手拍一张
  /// （比如约跑时发定位截图）只能先切到系统相机、拍完再回来选图。
  /// 微信的做法是先弹一个小面板让用户选，这里对齐。
  Future<void> _showAttachSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close, color: AppColors.textSecondary),
              title: const Text('取消'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (picked == 'camera') {
      onTakePhoto();
    } else if (picked == 'gallery') {
      onPickImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.gap10,
          AppSpacing.md,
          AppSpacing.gap10,
        ),
        color: AppColors.card,
        child: Row(
          children: [
            // 「+」：拍照 / 从相册选图
            _RoundIconButton(
              icon: Icons.add_circle_outline,
              tooltip: '发送图片',
              busy: uploading,
              onTap: uploading ? null : () => _showAttachSheet(context),
            ),
            // 表情：切换 emoji / 贴图面板；展开时图标变键盘，暗示再按一次收起
            _RoundIconButton(
              icon: emojiPanelOpen
                  ? Icons.keyboard_alt_outlined
                  : Icons.emoji_emotions_outlined,
              tooltip: emojiPanelOpen ? '收起表情' : '表情',
              onTap: onToggleEmoji,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: '发消息…',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.smLg,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSend,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.smLg),
                  child: Icon(Icons.send, color: AppColors.onPrimary, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入栏的圆形图标按钮（「+」与表情）。
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 22, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
