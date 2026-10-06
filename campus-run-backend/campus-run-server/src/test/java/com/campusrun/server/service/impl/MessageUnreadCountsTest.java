package com.campusrun.server.service.impl;

import com.campusrun.server.mapper.FriendshipMapper;
import com.campusrun.server.mapper.MessageMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 未读消息计数：客户端在登录后与回到前台时用它重建红点。
 *
 * <p><b>为什么必须存在（真实故障）</b>：客户端红点原本是纯内存态，
 * 只有 WebSocket 实时到达才会 +1。设备离线（或被顶下线）期间收到的消息，
 * 登录后完全没有提示 —— 用户不知道有人给自己发过消息。
 *
 * <p>这里守两条容易被改坏的性质：
 *   <ol>
 *     <li>用**一次** GROUP BY 查询，不是按好友逐个查（几十个好友时会有明显延迟）；</li>
 *     <li>过滤掉 0 与非法行，避免客户端拿到无意义的红点数据。</li>
 *   </ol>
 */
@ExtendWith(MockitoExtension.class)
class MessageUnreadCountsTest {

    @Mock
    private MessageMapper messageMapper;

    /**
     * 未读接口返回的是**完整快照**（所有好友都在，未读为 0 也给 0），
     * 所以实现里会查一次好友列表。不 stub 它会直接 NPE。
     */
    @Mock
    private FriendshipMapper friendshipMapper;

    private MessageServiceImpl service;

    @BeforeEach
    void setUp() {
        // 只测未读计数，其余依赖传 null（这些方法不会被调用）
        service = new MessageServiceImpl(messageMapper, friendshipMapper, null, null, null);
    }

    @org.junit.jupiter.api.BeforeEach
    void stubFriendship() {
        org.mockito.Mockito.lenient()
                .when(friendshipMapper.selectAcceptedFriendIds(org.mockito.ArgumentMatchers.anyLong()))
                .thenReturn(java.util.List.of());
    }

    private static Map<String, Object> row(long senderId, long cnt) {
        return Map.of("senderId", senderId, "cnt", cnt);
    }

    @Test
    @DisplayName("把 [senderId, cnt] 行转成 friendId -> 未读数")
    void convertsRows() {
        when(messageMapper.countUnreadBySender(7L))
                .thenReturn(List.of(row(11L, 3L), row(22L, 1L)));

        Map<Long, Integer> result = service.unreadCounts(7L);

        assertEquals(2, result.size());
        assertEquals(3, result.get(11L));
        assertEquals(1, result.get(22L));
    }

    @Test
    @DisplayName("只查一次数据库（不是按好友逐个查）")
    void queriesOnce() {
        when(messageMapper.countUnreadBySender(anyLong()))
                .thenReturn(List.of(row(11L, 1L), row(22L, 2L), row(33L, 3L)));

        service.unreadCounts(7L);

        verify(messageMapper).countUnreadBySender(7L);
    }

    @Test
    @DisplayName("返回的是完整快照：好友未读为 0 也要出现（值为 0）")
    void includesFriendsWithZeroUnread() {
        // ⚠️ 这条断言在早期是反过来的（要求把 0 过滤掉）。
        //
        // 后来发现那样会导致**僵尸红点**：客户端无法区分
        //   「这个好友没有未读了」 与 「这次请求没查到这个好友」，
        // 于是本地已经记下的红点永远不会被清掉 ——
        // 点进去读过、切出去又冒出来。
        //
        // 现在返回完整快照：所有好友都在，未读为 0 给 0。
        // 客户端据此可以把「不在快照里」当作「没有未读」处理。
        when(friendshipMapper.selectAcceptedFriendIds(7L))
                .thenReturn(List.of(11L, 22L, 33L));
        when(messageMapper.countUnreadBySender(7L))
                .thenReturn(List.of(row(11L, 0L), row(22L, 2L)));

        Map<Long, Integer> result = service.unreadCounts(7L);

        assertTrue(result.containsKey(11L), "未读为 0 的好友也必须在快照里");
        assertEquals(0, result.get(11L));
        assertEquals(2, result.get(22L));
        assertTrue(result.containsKey(33L), "没有任何消息的好友也要出现（0）");
        assertEquals(0, result.get(33L));
    }

    @Test
    @DisplayName("已解除好友关系但有未读的人也要保留（否则那条会话的红点会凭空消失）")
    void keepsUnreadFromNonFriends() {
        when(friendshipMapper.selectAcceptedFriendIds(7L)).thenReturn(List.of(11L));
        when(messageMapper.countUnreadBySender(7L))
                .thenReturn(List.of(row(99L, 5L)));

        Map<Long, Integer> result = service.unreadCounts(7L);

        assertEquals(5, result.get(99L), "历史会话的未读不能丢");
        assertEquals(0, result.get(11L));
    }

    @Test
    @DisplayName("userId 为 null 时返回空，不查库")
    void nullUser_returnsEmpty() {
        assertTrue(service.unreadCounts(null).isEmpty());
    }

    @Test
    @DisplayName("没有未读时返回空 Map（客户端据此不显示红点）")
    void noUnread_returnsEmpty() {
        when(messageMapper.countUnreadBySender(7L)).thenReturn(List.of());
        assertTrue(service.unreadCounts(7L).isEmpty());
    }

    @Test
    @DisplayName("容忍缺字段的脏行，不抛异常（SQL 别名变更不该让接口 500）")
    void toleratesMalformedRows() {
        // ⚠️ 不能用 Map.of：它不接受 null 值，而「字段存在但为 null」
        // 正是这里要覆盖的情况（SQL 别名写错或行数据异常）。
        java.util.Map<String, Object> nullValues = new java.util.HashMap<>();
        nullValues.put("senderId", null);
        nullValues.put("cnt", null);

        when(messageMapper.countUnreadBySender(7L)).thenReturn(List.of(
                Map.of("senderId", 11L),                 // 缺 cnt
                Map.of("cnt", 5L),                       // 缺 senderId
                nullValues,
                row(22L, 2L)));

        Map<Long, Integer> result = service.unreadCounts(7L);

        assertEquals(1, result.size(), "只有合法行应当被保留");
        assertEquals(2, result.get(22L));
    }
}
