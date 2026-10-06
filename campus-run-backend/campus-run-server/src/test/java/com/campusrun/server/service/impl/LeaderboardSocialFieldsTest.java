package com.campusrun.server.service.impl;

import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.LeaderboardEntryResponse;
import com.campusrun.server.enums.UserRelation;
import com.campusrun.server.mapper.LeaderboardMapper;
import com.campusrun.server.service.UserRelationResolver;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/**
 * 排行榜的社交化增强：relation + 与前后名的差距。
 *
 * <p>为什么值得测：
 * <ul>
 *   <li>**relation 错了会导致按钮错**（显示「加好友」但其实已是好友 → 点了报错）；</li>
 *   <li>**差距算错会误导用户**（位次是倒序的，减反了就变成「距上一名 -4000m」）；
 *       这是最容易写反的一处。</li>
 * </ul>
 */
@ExtendWith(MockitoExtension.class)
class LeaderboardSocialFieldsTest {

    @Mock
    private LeaderboardMapper leaderboardMapper;
    @Mock
    private UserRelationResolver relationResolver;

    private LeaderboardEntryResponse row(long userId, int distance) {
        LeaderboardEntryResponse r = new LeaderboardEntryResponse();
        r.setUserId(userId);
        r.setDistanceMeters(distance);
        return r;
    }

    private PageResponse<LeaderboardEntryResponse> board(List<LeaderboardEntryResponse> rows) {
        when(leaderboardMapper.countBoard(anyString(), anyString(), anyInt())).thenReturn((long) rows.size());
        when(leaderboardMapper.selectBoardPage(anyString(), anyString(), anyInt(), anyLong(), anyLong()))
                .thenReturn(new ArrayList<>(rows));
        return new LeaderboardServiceImpl(leaderboardMapper, relationResolver)
                .getBoard("weekly", null, 1, 1, 20, 99L);
    }

    @Test
    @DisplayName("差距方向正确：名次靠前的人距离更大，gapToAhead 是「我离上一名差多少」")
    void gapsAreComputedInTheRightDirection() {
        when(relationResolver.resolve(anyLong(), anyLong())).thenReturn(UserRelation.NONE);

        // 倒序：5000 > 4000 > 3000
        List<LeaderboardEntryResponse> rows = List.of(
                row(1, 5000), row(2, 4000), row(3, 3000));
        List<LeaderboardEntryResponse> list = board(rows).getList();

        // 第 1 名：没有上一名；领先第 2 名 1000
        assertNull(list.get(0).getGapToAheadMeters(), "第 1 名不应有「距上一名」");
        assertEquals(1000, list.get(0).getGapToBehindMeters());

        // 第 2 名：距上一名 1000；领先第 3 名 1000
        assertEquals(1000, list.get(1).getGapToAheadMeters());
        assertEquals(1000, list.get(1).getGapToBehindMeters());

        // 第 3 名：距上一名 1000；没有下一名
        assertEquals(1000, list.get(2).getGapToAheadMeters());
        assertNull(list.get(2).getGapToBehindMeters(), "最后一名不应有「领先」");
    }

    @Test
    @DisplayName("差距永远非负（避免出现「距上一名 -4000m」这种反向数字）")
    void gapsAreNeverNegative() {
        when(relationResolver.resolve(anyLong(), anyLong())).thenReturn(UserRelation.NONE);

        List<LeaderboardEntryResponse> list = board(List.of(row(1, 5000), row(2, 1000))).getList();

        for (LeaderboardEntryResponse r : list) {
            if (r.getGapToAheadMeters() != null) {
                assertEquals(true, r.getGapToAheadMeters() >= 0);
            }
            if (r.getGapToBehindMeters() != null) {
                assertEquals(true, r.getGapToBehindMeters() >= 0);
            }
        }
    }

    @Test
    @DisplayName("每条都带上 relation，且相对当前登录用户算")
    void relationsAreResolvedPerEntry() {
        when(relationResolver.resolve(99L, 1L)).thenReturn(UserRelation.SELF);
        when(relationResolver.resolve(99L, 2L)).thenReturn(UserRelation.FRIEND);
        when(relationResolver.resolve(99L, 3L)).thenReturn(UserRelation.PENDING_INCOMING);

        List<LeaderboardEntryResponse> list =
                board(List.of(row(1, 5000), row(2, 4000), row(3, 3000))).getList();

        assertEquals("self", list.get(0).getRelation());
        assertEquals("friend", list.get(1).getRelation());
        assertEquals("pending_incoming", list.get(2).getRelation());
    }

    @Test
    @DisplayName("currentUserId 为 null（内部调用）时不标注 relation，也不抛异常")
    void nullCurrentUserSkipsRelation() {
        when(leaderboardMapper.countBoard(anyString(), anyString(), anyInt())).thenReturn(1L);
        when(leaderboardMapper.selectBoardPage(anyString(), anyString(), anyInt(), anyLong(), anyLong()))
                .thenReturn(new ArrayList<>(List.of(row(1, 5000))));

        List<LeaderboardEntryResponse> list = new LeaderboardServiceImpl(leaderboardMapper, relationResolver)
                .getBoard("weekly", null, 1, 1, 20, null).getList();

        assertNull(list.get(0).getRelation());
        // 但差距仍应计算（与登录无关）
        assertNull(list.get(0).getGapToAheadMeters());
    }

    @Test
    @DisplayName("分页时本页第一条不会被误判成「第 1 名」")
    void pagedFirstRowIsNotTreatedAsChampion() {
        when(relationResolver.resolve(anyLong(), anyLong())).thenReturn(UserRelation.NONE);
        when(leaderboardMapper.countBoard(anyString(), anyString(), anyInt())).thenReturn(50L);
        when(leaderboardMapper.selectBoardPage(anyString(), anyString(), anyInt(), anyLong(), anyLong()))
                .thenReturn(new ArrayList<>(List.of(row(11, 3000), row(12, 2000))));

        List<LeaderboardEntryResponse> list = new LeaderboardServiceImpl(leaderboardMapper, relationResolver)
                .getBoard("weekly", null, 1, 5, 10, 99L).getList();

        // 第 5 页第一条真实名次是 41，不是第 1 名
        assertEquals(41L, list.get(0).getRank());
        assertNull(list.get(0).getGapToAheadMeters(),
                "前面的人不在本页结果里，不能凭空算出一个错误差距");
        assertEquals(1000, list.get(0).getGapToBehindMeters());
        assertEquals(1000, list.get(1).getGapToAheadMeters());
    }
}
