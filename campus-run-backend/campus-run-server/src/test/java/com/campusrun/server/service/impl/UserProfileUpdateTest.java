package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.request.UpdateProfileRequest;
import com.campusrun.server.dto.response.UserInfoResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.UserMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 编辑资料。
 *
 * <p>核心语义：**字段为 null = 不修改**。客户端只想改头像时会漏传昵称，
 * 如果实现成「null 就覆盖」，用户的昵称会被静默清空。
 */
@ExtendWith(MockitoExtension.class)
class UserProfileUpdateTest {

    @Mock
    private UserMapper userMapper;

    private User existing() {
        User user = new User();
        user.setId(1L);
        user.setUniqueId("04231786");
        user.setNickname("旧昵称");
        user.setPhone("13800138000");
        user.setAvatarUrl("http://old.png");
        return user;
    }

    @Test
    @DisplayName("只改昵称时头像保持不动")
    void updateNicknameOnly_keepsAvatar() {
        when(userMapper.selectById(1L)).thenReturn(existing());
        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setNickname("新昵称");

        UserInfoResponse resp = new UserServiceImpl(userMapper).updateProfile(1L, req);

        assertEquals("新昵称", resp.getNickname());
        assertEquals("http://old.png", resp.getAvatarUrl(), "未传 avatarUrl 不应被清空");
    }

    @Test
    @DisplayName("只改头像时昵称保持不动")
    void updateAvatarOnly_keepsNickname() {
        when(userMapper.selectById(1L)).thenReturn(existing());
        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setAvatarUrl("http://new.png");

        UserInfoResponse resp = new UserServiceImpl(userMapper).updateProfile(1L, req);

        assertEquals("旧昵称", resp.getNickname(), "未传 nickname 不应被清空");
        assertEquals("http://new.png", resp.getAvatarUrl());
    }

    @Test
    @DisplayName("传空串头像 = 清空头像，回到昵称首字兜底")
    void emptyAvatar_clearsAvatar() {
        when(userMapper.selectById(1L)).thenReturn(existing());
        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setAvatarUrl("   ");

        UserInfoResponse resp = new UserServiceImpl(userMapper).updateProfile(1L, req);

        assertNull(resp.getAvatarUrl());
    }

    @Test
    @DisplayName("昵称首尾空格会被裁掉；全空格视为非法")
    void nicknameIsTrimmed() {
        when(userMapper.selectById(1L)).thenReturn(existing());
        UpdateProfileRequest ok = new UpdateProfileRequest();
        ok.setNickname("  跑者甲  ");
        assertEquals("跑者甲", new UserServiceImpl(userMapper).updateProfile(1L, ok).getNickname());

        UpdateProfileRequest blank = new UpdateProfileRequest();
        blank.setNickname("   ");
        assertEquals(ErrorCode.PARAM_ERROR.getCode(),
                assertThrows(BusinessException.class,
                        () -> new UserServiceImpl(userMapper).updateProfile(1L, blank)).getCode());
    }

    @Test
    @DisplayName("更新会落库（不是只改内存对象）")
    void updateIsPersisted() {
        when(userMapper.selectById(1L)).thenReturn(existing());
        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setNickname("持久化");

        new UserServiceImpl(userMapper).updateProfile(1L, req);

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userMapper).updateById(captor.capture());
        assertEquals("持久化", captor.getValue().getNickname());
    }

    @Test
    @DisplayName("用户不存在抛 USER_NOT_FOUND")
    void userNotFound() {
        when(userMapper.selectById(9L)).thenReturn(null);
        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setNickname("x");

        assertEquals(ErrorCode.USER_NOT_FOUND.getCode(),
                assertThrows(BusinessException.class,
                        () -> new UserServiceImpl(userMapper).updateProfile(9L, req)).getCode());
    }
}
