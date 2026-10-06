package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.server.dto.response.UserProfileResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.entity.UserStats;
import com.campusrun.server.enums.UserRelation;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.mapper.UserStatsMapper;
import com.campusrun.server.service.UserRelationResolver;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

/**
 * 用户主页。
 *
 * <p>重点固化两点：
 * <ol>
 *   <li>**绝不返回手机号** —— 主页对任何搜到的人可见，泄露手机号是隐私事故。</li>
 *   <li>relation 由服务端算，客户端据此决定「发消息 / 添加 / 通过验证」。</li>
 * </ol>
 */
@ExtendWith(MockitoExtension.class)
class UserProfileServiceTest {

    @Mock
    private UserMapper userMapper;
    @Mock
    private UserStatsMapper userStatsMapper;
    @Mock
    private UserRelationResolver relationResolver;

    private User existingUser() {
        User user = new User();
        user.setId(7L);
        user.setUniqueId("04231786");
        user.setNickname("跑者乙");
        user.setPhone("13900139000");
        user.setAvatarUrl("http://img/7.png");
        user.setCreatedAt(LocalDateTime.of(2026, 9, 1, 10, 0));
        return user;
    }

    @Test
    @DisplayName("主页返回昵称/ID/头像/加入时间，且不含手机号")
    void getProfile_mapsFieldsButNeverPhone() {
        when(userMapper.selectById(7L)).thenReturn(existingUser());
        when(relationResolver.resolve(1L, 7L)).thenReturn(UserRelation.FRIEND);

        UserProfileResponse resp = new UserServiceImpl(userMapper, userStatsMapper, relationResolver)
                .getProfile(1L, 7L);

        assertEquals(7L, resp.getUserId());
        assertEquals("04231786", resp.getUniqueId());
        assertEquals("跑者乙", resp.getNickname());
        assertEquals("http://img/7.png", resp.getAvatarUrl());
        assertEquals(LocalDateTime.of(2026, 9, 1, 10, 0), resp.getCreatedAt());
        assertEquals("friend", resp.getRelation());

        // UserProfileResponse 本身没有 phone 字段；这里用反射兜底断言，
        // 防止将来有人「顺手」把手机号加进 DTO 而没人发现。
        boolean hasPhoneField = java.util.Arrays.stream(UserProfileResponse.class.getDeclaredFields())
                .anyMatch(f -> f.getName().toLowerCase().contains("phone"));
        assertFalse(hasPhoneField, "主页 DTO 不应包含手机号字段（他人可见，属隐私泄露）");
    }

    @Test
    @DisplayName("带出运动汇总，缺失时保持 0 而不报错")
    void getProfile_includesStats() {
        when(userMapper.selectById(7L)).thenReturn(existingUser());
        when(relationResolver.resolve(1L, 7L)).thenReturn(UserRelation.NONE);
        UserStats stats = new UserStats();
        stats.setUserId(7L);
        stats.setTotalDistanceMeters(18899);
        stats.setTotalActivityCount(7);
        stats.setStreakDays(2);
        when(userStatsMapper.selectById(7L)).thenReturn(stats);

        UserProfileResponse resp = new UserServiceImpl(userMapper, userStatsMapper, relationResolver)
                .getProfile(1L, 7L);

        assertEquals(18899, resp.getTotalDistanceMeters());
        assertEquals(7, resp.getTotalActivityCount());
        assertEquals(2, resp.getStreakDays());
        assertEquals("none", resp.getRelation());
    }

    @Test
    @DisplayName("看自己时 relation=self")
    void getProfile_self() {
        when(userMapper.selectById(7L)).thenReturn(existingUser());
        when(relationResolver.resolve(7L, 7L)).thenReturn(UserRelation.SELF);

        UserProfileResponse resp = new UserServiceImpl(userMapper, userStatsMapper, relationResolver)
                .getProfile(7L, 7L);

        assertEquals("self", resp.getRelation());
    }

    @Test
    @DisplayName("用户不存在抛 USER_NOT_FOUND")
    void getProfile_userNotFound() {
        when(userMapper.selectById(99L)).thenReturn(null);

        BusinessException e = assertThrows(BusinessException.class,
                () -> new UserServiceImpl(userMapper, userStatsMapper, relationResolver)
                        .getProfile(1L, 99L));
        assertEquals(com.campusrun.common.result.ErrorCode.USER_NOT_FOUND.getCode(), e.getCode());
    }
}
