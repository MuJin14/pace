package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.exception.ForbiddenException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.response.ActivitySummaryResponse;
import com.campusrun.server.dto.response.UserBadgeResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.enums.UserRelation;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.mapper.UserStatsMapper;
import com.campusrun.server.service.ActivityService;
import com.campusrun.server.service.BadgeService;
import com.campusrun.server.service.UserRelationResolver;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 查看他人运动数据 / 勋章墙的权限边界。
 *
 * <p>核心不变式：**只有好友（或自己）能看**，且非好友要抛 403 而不是返回空列表 ——
 * 返回空会让前端把「没权限」渲染成「TA 没有记录」，既误导用户也让排查困难。
 */
@ExtendWith(MockitoExtension.class)
class UserSocialDataPermissionTest {

    @Mock
    private UserMapper userMapper;
    @Mock
    private UserStatsMapper userStatsMapper;
    @Mock
    private UserRelationResolver relationResolver;
    @Mock
    private ActivityService activityService;
    @Mock
    private BadgeService badgeService;

    private UserServiceImpl service() {
        return new UserServiceImpl(userMapper, userStatsMapper, relationResolver,
                activityService, badgeService);
    }

    private void targetExists() {
        User user = new User();
        user.setId(7L);
        when(userMapper.selectById(7L)).thenReturn(user);
    }

    @Test
    @DisplayName("是好友：可以看运动记录")
    void friend_canReadActivities() {
        targetExists();
        when(relationResolver.resolve(1L, 7L)).thenReturn(UserRelation.FRIEND);
        when(activityService.page(anyLong(), any(), anyLong(), anyLong()))
                .thenReturn(new PageResponse<>(0L, 1L, 10L, List.<ActivitySummaryResponse>of()));

        PageResponse<ActivitySummaryResponse> result =
                service().listUserActivities(1L, 7L, null, 1, 10);

        assertEquals(0L, result.getTotal());
        verify(activityService).page(7L, null, 1, 10);
    }

    @Test
    @DisplayName("看自己：允许")
    void self_canReadActivities() {
        targetExists();
        when(relationResolver.resolve(7L, 7L)).thenReturn(UserRelation.SELF);
        when(activityService.page(anyLong(), any(), anyLong(), anyLong()))
                .thenReturn(new PageResponse<>(0L, 1L, 10L, List.<ActivitySummaryResponse>of()));

        assertEquals(0L, service().listUserActivities(7L, 7L, null, 1, 10).getTotal());
    }

    @Test
    @DisplayName("不是好友：抛 Forbidden（HTTP 403），且不去查数据")
    void stranger_getsForbidden_andNoQuery() {
        targetExists();
        when(relationResolver.resolve(1L, 7L)).thenReturn(UserRelation.NONE);

        // 断言 ForbiddenException 而不是 BusinessException：
        // 它会被全局处理器映射成 HTTP 403，调用方仅凭状态码即可区分「没权限」与「没数据」
        assertThrows(ForbiddenException.class,
                () -> service().listUserActivities(1L, 7L, null, 1, 10));

        verify(activityService, never()).page(anyLong(), any(), anyLong(), anyLong());
    }

    @Test
    @DisplayName("只有申请关系（未通过）：同样被拒")
    void pendingRelation_getsForbidden() {
        targetExists();
        when(relationResolver.resolve(1L, 7L)).thenReturn(UserRelation.PENDING_OUTGOING);

        assertThrows(ForbiddenException.class,
                () -> service().listUserActivities(1L, 7L, null, 1, 10));
    }

    @Test
    @DisplayName("勋章墙同样只对好友开放")
    void badges_onlyForFriends() {
        targetExists();
        when(relationResolver.resolve(1L, 7L)).thenReturn(UserRelation.FRIEND);
        when(badgeService.listMine(7L)).thenReturn(List.<UserBadgeResponse>of());

        assertEquals(0, service().listUserBadges(1L, 7L).size());

        when(relationResolver.resolve(2L, 7L)).thenReturn(UserRelation.NONE);
        assertThrows(ForbiddenException.class, () -> service().listUserBadges(2L, 7L));
        verify(badgeService, never()).listMine(2L);
    }

    @Test
    @DisplayName("目标用户不存在：抛 USER_NOT_FOUND（先于权限判断）")
    void targetNotFound() {
        when(userMapper.selectById(99L)).thenReturn(null);

        assertEquals(ErrorCode.USER_NOT_FOUND.getCode(),
                assertThrows(BusinessException.class,
                        () -> service().listUserActivities(1L, 99L, null, 1, 10)).getCode());
    }
}
