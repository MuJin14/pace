package com.campusrun.server.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.server.entity.ChatPreference;
import com.campusrun.server.mapper.ChatPreferenceMapper;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * 聊天会话偏好（免打扰）。
 *
 * <p>只影响**服务端的离线推送**。在线时对方已经通过 WebSocket 收到消息，
 * 免打扰不该把消息丢掉 —— 消息照常落库、照常送达，只是不弹通知。
 * 「免打扰」的语义是「别打扰我」，不是「别联系我」。
 */
@Service
public class ChatPreferenceService {

    private final ChatPreferenceMapper chatPreferenceMapper;

    public ChatPreferenceService(ChatPreferenceMapper chatPreferenceMapper) {
        this.chatPreferenceMapper = chatPreferenceMapper;
    }

    /** 某用户所有被静音的会话对方 id。 */
    public List<Long> mutedFriendIds(Long userId) {
        if (userId == null) {
            return List.of();
        }
        return chatPreferenceMapper.selectMutedFriendIds(userId);
    }

    /**
     * 判断 userId 是否对与 friendId 的会话设置了免打扰。
     *
     * <p>注意方向：查的是「<b>接收方</b>是否静音了发送方」。
     * 发送方的设置与接收方无关。
     */
    public boolean isMuted(Long userId, Long friendId) {
        if (userId == null || friendId == null) {
            return false;
        }
        Long count = chatPreferenceMapper.selectCount(new LambdaQueryWrapper<ChatPreference>()
                .eq(ChatPreference::getUserId, userId)
                .eq(ChatPreference::getFriendId, friendId)
                .eq(ChatPreference::getMuted, 1));
        return count != null && count > 0;
    }

    /**
     * 设置 / 取消免打扰（幂等）。
     *
     * <p>用「查了再插或改」而不是 upsert：表上已有唯一键兜底，
     * 但显式分支更容易在读代码时看清语义，也便于将来加字段。
     */
    public void setMuted(Long userId, Long friendId, boolean muted) {
        List<ChatPreference> existing = chatPreferenceMapper.selectList(
                new LambdaQueryWrapper<ChatPreference>()
                        .eq(ChatPreference::getUserId, userId)
                        .eq(ChatPreference::getFriendId, friendId));

        int value = muted ? 1 : 0;
        if (existing.isEmpty()) {
            ChatPreference pref = new ChatPreference();
            pref.setUserId(userId);
            pref.setFriendId(friendId);
            pref.setMuted(value);
            chatPreferenceMapper.insert(pref);
            return;
        }

        ChatPreference pref = existing.get(0);
        if (pref.getMuted() != null && pref.getMuted() == value) {
            // 幂等：值没变就不写库，避免无意义的 updated_at 变动
            return;
        }
        pref.setMuted(value);
        chatPreferenceMapper.updateById(pref);
    }
}
