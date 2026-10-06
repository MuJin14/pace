package com.campusrun.server.service;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.ChatMessageResponse;

import java.util.List;

public interface MessageService {

    /**
     * 发送消息：落库后若对方在线则推送，否则留作离线消息。
     *
     * @param senderId   发送方用户 ID
     * @param receiverId 接收方用户 ID
     * @param content    消息内容
     * @return 消息体（含投递状态）
     * @throws BusinessException 内容为空或超长、对方不是好友
     */
    ChatMessageResponse sendMessage(Long senderId, Long receiverId, String content);

    /**
     * 发送任意类型的消息（文本 / 图片 / 表情包）。
     *
     * <p>类型约束由服务端强制，不信任客户端：
     * <ul>
     *   <li>文本（type=1）：content 非空且不超长，mediaUrl 必须是空（避免"文本里塞图"绕过校验）</li>
     *   <li>图片 / 表情包（type=2/3）：mediaUrl 必填，content 可空</li>
     *   <li>未知 type：按参数错误拒绝，而不是静默当文本处理</li>
     * </ul>
     *
     * @param senderId   发送方用户 ID
     * @param receiverId 接收方用户 ID
     * @param content    文本内容，媒体消息可为 null
     * @param type       消息类型码，见 {@link com.campusrun.server.enums.MessageType}
     * @param mediaUrl   媒体地址，媒体消息必填
     * @return 消息体（含投递状态）
     * @throws BusinessException 类型与参数不匹配、对方不是好友
     */
    ChatMessageResponse sendMessage(Long senderId, Long receiverId, String content,
                                    Integer type, String mediaUrl);

    /**
     * 将用户的离线消息逐批推送，成功后标记已投递。
     *
     * @param userId 接收方用户 ID
     */
    void pushOfflineMessages(Long userId);

    /**
     * 分页查询与某好友的聊天记录，按时间倒序。
     *
     * 读取历史即视为「已读」：查询前会把该会话中「好友发给当前用户且未读」的消息置为已读，
     * 并向好友推送 {@code read_receipt} 已读回执；因此返回的条目里 readAt 可能刚被写入。
     *
     * @param userId   当前用户 ID
     * @param friendId 好友用户 ID
     * @param beforeId 游标消息 ID，返回该 ID 之前的消息，可为 null 表示最新
     * @param size     条数
     * @return 聊天记录分页列表
     */
    PageResponse<ChatMessageResponse> history(Long userId, Long friendId, Long beforeId, long size);

    /**
     * 显式标记一批消息为已读（拉取历史已自动标记，此接口用于精确补标）。
     *
     * 语义约定：
     * - 只有消息的接收方（receiverId == userId）才有权标记，且只影响「别人发给我」的消息，
     *   自己发出的消息永远不会被自己标记为已读；
     * - 传入了任何一条不属于当前用户接收的消息，整批拒绝并抛 {@code FORBIDDEN}；
     * - 幂等：已读消息不会被重复写入 readAt，重复调用返回 0；
     * - 标记成功后向各发送方推送 {@code read_receipt}，对方离线时静默忽略。
     *
     * @param userId     当前用户 ID（必须是消息接收方）
     * @param messageIds 消息 ID 列表，可为空（空则直接返回 0）
     * @return 本次实际由未读变为已读的消息条数
     * @throws BusinessException 存在不属于当前用户接收的消息（403）
     */
    int markRead(Long userId, List<Long> messageIds);

    /**
     * 当前用户「按好友分组的未读数」。
     *
     * <p>客户端在**登录后**与**回到前台**时调用，用来重建未读红点。
     *
     * <p>为什么需要它：红点原本只靠 WebSocket 实时累加，是纯内存态。
     * 设备离线期间收到的消息登录后没有任何提示 —— 用户不知道有人找过自己。
     *
     * @return friendId -> 未读条数；只包含未读 > 0 的好友
     */
    java.util.Map<Long, Integer> unreadCounts(Long userId);
}
