package com.campusrun.server.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.server.entity.Friendship;
import com.campusrun.server.enums.FriendshipStatus;
import com.campusrun.server.enums.UserRelation;
import com.campusrun.server.mapper.FriendshipMapper;
import org.springframework.stereotype.Component;

/**
 * 计算「当前用户 ↔ 目标用户」的关系。
 *
 * <p>抽成独立组件的原因：搜索结果、用户主页、好友列表三处都要用同一套判定规则。
 * 如果各自实现，很容易出现「主页显示可以聊天、搜索结果显示还要加好友」这类不一致。
 *
 * <p>判定顺序（先到先得）：自己 → 已是好友 → 我发出的待处理 → 对方发给我的待处理 → 无关系。
 */
@Component
public class UserRelationResolver {

    private final FriendshipMapper friendshipMapper;

    public UserRelationResolver(FriendshipMapper friendshipMapper) {
        this.friendshipMapper = friendshipMapper;
    }

    public UserRelation resolve(Long me, Long target) {
        if (me == null || target == null) {
            return UserRelation.NONE;
        }
        if (me.equals(target)) {
            return UserRelation.SELF;
        }

        Friendship outgoing = selectOne(me, target);
        if (outgoing != null && isAccepted(outgoing)) {
            return UserRelation.FRIEND;
        }
        if (outgoing != null && isPending(outgoing)) {
            return UserRelation.PENDING_OUTGOING;
        }

        Friendship incoming = selectOne(target, me);
        if (incoming != null && isAccepted(incoming)) {
            return UserRelation.FRIEND;
        }
        if (incoming != null && isPending(incoming)) {
            return UserRelation.PENDING_INCOMING;
        }

        return UserRelation.NONE;
    }

    private Friendship selectOne(Long userId, Long friendId) {
        return friendshipMapper.selectOne(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getUserId, userId)
                .eq(Friendship::getFriendId, friendId)
                .last("LIMIT 1"));
    }

    private boolean isAccepted(Friendship f) {
        return Integer.valueOf(FriendshipStatus.ACCEPTED.getCode()).equals(f.getStatus());
    }

    private boolean isPending(Friendship f) {
        return Integer.valueOf(FriendshipStatus.PENDING.getCode()).equals(f.getStatus());
    }
}
