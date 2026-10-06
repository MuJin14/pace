package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.response.UserInfoResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.UserMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserServiceImplTest {

    @Mock
    private UserMapper userMapper;

    @Test
    void getCurrentUser_userExists_mapsAllFields() {
        User user = new User();
        user.setId(1L);
        user.setUniqueId("CR-00001234");
        user.setNickname("小明");
        user.setPhone("13800138000");
        user.setAvatarUrl("http://img/1.png");
        LocalDateTime createdAt = LocalDateTime.of(2026, 9, 1, 10, 0);
        user.setCreatedAt(createdAt);
        when(userMapper.selectById(1L)).thenReturn(user);

        UserInfoResponse response = new UserServiceImpl(userMapper).getCurrentUser(1L);

        assertEquals(1L, response.getUserId());
        assertEquals("CR-00001234", response.getUniqueId());
        assertEquals("小明", response.getNickname());
        assertEquals("13800138000", response.getPhone());
        assertEquals("http://img/1.png", response.getAvatarUrl());
        assertEquals(createdAt, response.getCreatedAt());
    }

    @Test
    void getCurrentUser_userNotFound_throwsUserNotFound() {
        when(userMapper.selectById(1L)).thenReturn(null);

        BusinessException ex = assertThrows(BusinessException.class,
                () -> new UserServiceImpl(userMapper).getCurrentUser(1L));
        assertEquals(ErrorCode.USER_NOT_FOUND.getCode(), ex.getCode());
    }

    @Test
    void deleteAccount_clearsAllUserDataThenUserRow() {
        User user = new User();
        user.setId(7L);
        when(userMapper.selectById(7L)).thenReturn(user);

        new UserServiceImpl(userMapper).deleteAccount(7L);

        // 七张子表都要清，最后才删主表；漏掉任一张都会留下孤儿数据（也是合规问题）。
        var order = inOrder(userMapper);
        order.verify(userMapper).deleteActivities(7L);
        order.verify(userMapper).deleteFriendships(7L);
        order.verify(userMapper).deleteMessages(7L);
        order.verify(userMapper).deleteLeaderboardStats(7L);
        order.verify(userMapper).deleteGoals(7L);
        order.verify(userMapper).deleteUserBadges(7L);
        order.verify(userMapper).deleteUserStats(7L);
        order.verify(userMapper).deleteById(7L);
    }

    @Test
    void deleteAccount_userNotFound_throwsAndDeletesNothing() {
        when(userMapper.selectById(7L)).thenReturn(null);

        BusinessException ex = assertThrows(BusinessException.class,
                () -> new UserServiceImpl(userMapper).deleteAccount(7L));
        assertEquals(ErrorCode.USER_NOT_FOUND.getCode(), ex.getCode());
        verify(userMapper, never()).deleteActivities(7L);
        verify(userMapper, never()).deleteById(7L);
    }
}
