package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.server.dto.request.ChangePasswordRequest;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.UserMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 修改密码。
 *
 * <p>覆盖的关键行为：
 * <ol>
 *   <li>旧密码错误 → 1003，且**不写库**（不能因为校验失败留下半个改动）</li>
 *   <li>新密码过短 → 400</li>
 *   <li>新密码与旧密码相同 → 400（否则「改密」等于没改）</li>
 *   <li>成功 → 新哈希可被新密码验通、旧密码验不通</li>
 *   <li>成功 → **写入 tokenInvalidBefore**，这是「改密即踢下线」的唯一依据</li>
 * </ol>
 */
class ChangePasswordTest {

    private static final long USER_ID = 1L;
    private static final String OLD_PASSWORD = "oldSecret123";
    private static final String NEW_PASSWORD = "newSecret456";

    private UserMapper userMapper;
    private PasswordEncoder passwordEncoder;
    private UserServiceImpl service;
    private User stored;

    @BeforeEach
    void setUp() {
        userMapper = mock(UserMapper.class);
        passwordEncoder = new BCryptPasswordEncoder();
        service = new UserServiceImpl(userMapper, passwordEncoder);

        stored = new User();
        stored.setId(USER_ID);
        stored.setNickname("Mujin");
        stored.setPasswordHash(passwordEncoder.encode(OLD_PASSWORD));
        when(userMapper.selectById(USER_ID)).thenReturn(stored);
    }

    private ChangePasswordRequest request(String oldPwd, String newPwd) {
        ChangePasswordRequest r = new ChangePasswordRequest();
        r.setOldPassword(oldPwd);
        r.setNewPassword(newPwd);
        return r;
    }

    @Test
    @DisplayName("旧密码错误 → 抛 1003，且不写库、不吊销令牌")
    void wrongOldPasswordRejected() {
        assertThatThrownBy(() -> service.changePassword(USER_ID, request("wrongPwd", NEW_PASSWORD)))
                .isInstanceOf(BusinessException.class)
                .satisfies(e -> assertThat(((BusinessException) e).getCode()).isEqualTo(1003));

        // 校验失败绝不能留下副作用
        verify(userMapper, never()).updateById(any(User.class));
    }

    @Test
    @DisplayName("新密码过短 → 抛 400（与注册的下限一致）")
    void tooShortNewPasswordRejected() {
        assertThatThrownBy(() -> service.changePassword(USER_ID, request(OLD_PASSWORD, "short")))
                .isInstanceOf(BusinessException.class)
                .satisfies(e -> assertThat(((BusinessException) e).getCode()).isEqualTo(400));

        verify(userMapper, never()).updateById(any(User.class));
    }

    @Test
    @DisplayName("新密码与旧密码相同 → 抛 400，避免「改密」等于没改")
    void samePasswordRejected() {
        assertThatThrownBy(() -> service.changePassword(USER_ID, request(OLD_PASSWORD, OLD_PASSWORD)))
                .isInstanceOf(BusinessException.class)
                .satisfies(e -> assertThat(((BusinessException) e).getCode()).isEqualTo(400));

        verify(userMapper, never()).updateById(any(User.class));
    }

    @Test
    @DisplayName("成功：新密码可用、旧密码失效")
    void successUpdatesHash() {
        service.changePassword(USER_ID, request(OLD_PASSWORD, NEW_PASSWORD));

        assertThat(passwordEncoder.matches(NEW_PASSWORD, stored.getPasswordHash())).isTrue();
        assertThat(passwordEncoder.matches(OLD_PASSWORD, stored.getPasswordHash())).isFalse();
        verify(userMapper).updateById(stored);
    }

    @Test
    @DisplayName("成功：写入 tokenInvalidBefore —— 这是旧 refresh token 失效的唯一依据")
    void successRevokesOldTokens() {
        assertThat(stored.getTokenInvalidBefore()).isNull();

        service.changePassword(USER_ID, request(OLD_PASSWORD, NEW_PASSWORD));

        assertThat(stored.getTokenInvalidBefore())
                .as("改密必须写入令牌失效时间，否则 30 天有效的 refresh token 仍可用")
                .isNotNull();
    }

    @Test
    @DisplayName("用户不存在 → 抛 1002")
    void userNotFound() {
        when(userMapper.selectById(USER_ID)).thenReturn(null);

        assertThatThrownBy(() -> service.changePassword(USER_ID, request(OLD_PASSWORD, NEW_PASSWORD)))
                .isInstanceOf(BusinessException.class)
                .satisfies(e -> assertThat(((BusinessException) e).getCode()).isEqualTo(1002));
    }

    @Test
    @DisplayName("未装配 PasswordEncoder 时明确报错，而不是抛 NPE")
    void missingEncoderFailsLoudly() {
        UserServiceImpl noEncoder = new UserServiceImpl(userMapper);

        assertThatThrownBy(() -> noEncoder.changePassword(USER_ID, request(OLD_PASSWORD, NEW_PASSWORD)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("密码服务不可用");
    }
}
