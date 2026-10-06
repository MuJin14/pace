package com.campusrun.server.service;

import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.impl.AuthServiceImpl;
import com.campusrun.server.util.UniqueIdGenerator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 单设备登录：换设备登录时递增令牌版本，让旧设备的令牌立即失效。
 *
 * <p><b>为什么值得单独测</b>：这个机制的失效方式是**静默的**——
 *   · 版本没递增 → 旧设备继续能收消息，回到「多设备同时在线」的一堆问题
 *     （WebSocket 互相顶掉、已读回执串台、两台设备各记一条轨迹）；
 *   · 同设备也递增 → 用户杀掉 App 重进就被判定「已在其他设备登录」，
 *     而这恰恰是最正常的操作。
 *
 * <p>两种都只在真机上、隔一段时间才暴露，所以必须在单测里钉死。
 */
@ExtendWith(MockitoExtension.class)
class SingleDeviceLoginTest {

    @Mock
    private UserMapper userMapper;
    @Mock
    private PasswordEncoder passwordEncoder;
    @Mock
    private JwtTokenProvider jwtTokenProvider;
    @Mock
    private UniqueIdGenerator uniqueIdGenerator;

    private AuthServiceImpl authService;

    @BeforeEach
    void setUp() {
        authService = new AuthServiceImpl(userMapper, passwordEncoder, jwtTokenProvider, uniqueIdGenerator);
        // lenient：不是每个用例都会走到「签发令牌」那一步
        // （密码错误、同设备登录都会提前返回），严格桩会直接报
        // UnnecessaryStubbing 而让正确的代码看起来像有问题。
        lenient().when(jwtTokenProvider.generateAccessToken(any(), any(), any(), anyInt()))
                .thenReturn("access");
        lenient().when(jwtTokenProvider.generateRefreshToken(any(), any(), any(), anyInt()))
                .thenReturn("refresh");
    }

    private User existingUser(String deviceId, int tokenVersion) {
        User u = new User();
        u.setId(7L);
        u.setUniqueId("CR-00000007");
        u.setPhone("13800138000");
        u.setNickname("小明");
        u.setPasswordHash("hashed");
        u.setRole(0);
        u.setDeviceId(deviceId);
        u.setTokenVersion(tokenVersion);
        return u;
    }

    private LoginRequest loginRequest(String deviceId) {
        LoginRequest r = new LoginRequest();
        r.setPhone("13800138000");
        r.setPassword("secret123");
        r.setDeviceId(deviceId);
        return r;
    }

    @Test
    @DisplayName("同一台设备再次登录：不递增版本（否则用户重进 App 就被自己踢下线）")
    void sameDevice_doesNotBumpVersion() {
        User user = existingUser("device-A", 3);
        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);

        authService.login(loginRequest("device-A"), "1.2.3.4");

        assertEquals(3, user.getTokenVersion(), "同设备登录不该改动版本");
        verify(userMapper, never()).update(any(), any());
    }

    @Test
    @DisplayName("换设备登录：版本 +1，并记下新设备")
    void differentDevice_bumpsVersion() {
        User user = existingUser("device-A", 3);
        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);

        authService.login(loginRequest("device-B"), "1.2.3.4");

        assertEquals(4, user.getTokenVersion(), "换设备必须递增版本，否则旧设备不会被踢下线");
        assertEquals("device-B", user.getDeviceId());
    }

    @Test
    @DisplayName("换设备登录：只更新 token_version 与 device_id 两列，且限定到该用户")
    void differentDevice_updatesOnlyThoseTwoColumns() {
        User user = existingUser("device-A", 0);
        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);

        authService.login(loginRequest("device-B"), "1.2.3.4");

        // 用 updateById 会把整个实体写回去，可能覆盖并发修改的昵称、密码等，
        // 所以实现走的是条件更新；这里断言那个条件更新的内容。
        @SuppressWarnings("unchecked")
        ArgumentCaptor<UpdateWrapper<User>> captor =
                ArgumentCaptor.forClass(UpdateWrapper.class);
        verify(userMapper).update(isNull(), captor.capture());

        UpdateWrapper<User> w = captor.getValue();
        // getSqlSegment() 只给 WHERE 部分，SET 子句要用 getSqlSet()（实测踩到）
        String set = String.valueOf(w.getSqlSet());
        String where = w.getSqlSegment();

        // 这两条断言同时在守「列名与迁移脚本一致」：
        // 列名是字符串字面量，写错了不会编译报错，只会在真机上静默失败。
        assertTrue(set.contains("token_version"), "SET 应更新 token_version，实际: " + set);
        assertTrue(set.contains("device_id"), "SET 应更新 device_id，实际: " + set);
        assertTrue(where.contains("id"), "WHERE 应限定到该用户，实际: " + where);
    }

    @Test
    @DisplayName("新签发的令牌带上递增后的版本")
    void newTokensCarryBumpedVersion() {
        User user = existingUser("device-A", 5);
        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);

        authService.login(loginRequest("device-B"), "1.2.3.4");

        // 版本必须写进令牌：令牌里没有新版本的话，新设备自己也会立刻被判失效
        verify(jwtTokenProvider).generateAccessToken(7L, "CR-00000007", 0, 6);
        verify(jwtTokenProvider).generateRefreshToken(7L, "CR-00000007", 0, 6);
    }

    @Test
    @DisplayName("首次登录（此前没有设备记录）：递增一次，让更早的遗留令牌失效")
    void firstLogin_withNoDevice_bumpsOnce() {
        User user = existingUser(null, 0);
        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);

        authService.login(loginRequest("device-A"), "1.2.3.4");

        assertEquals(1, user.getTokenVersion());
        assertEquals("device-A", user.getDeviceId());
    }

    @Test
    @DisplayName("老客户端不带 deviceId：退化成每次都递增（后登录的踢掉先登录的）")
    void noDeviceId_fallsBackToAlwaysBump() {
        User user = existingUser("device-A", 2);
        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);

        authService.login(loginRequest(null), "1.2.3.4");

        assertEquals(3, user.getTokenVersion(),
                "没上报设备时无法判断是否同设备，只能按「换设备」处理");
    }

    @Test
    @DisplayName("超长 deviceId 被截断到 64 字符（列宽限制，否则插入报错）")
    void oversizedDeviceId_isTruncated() {
        User user = existingUser("device-A", 0);
        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);

        authService.login(loginRequest("x".repeat(200)), "1.2.3.4");

        assertEquals(64, user.getDeviceId().length());
    }

    @Test
    @DisplayName("密码错误时不递增版本（不能靠猜密码把别人踢下线）")
    void wrongPassword_doesNotBumpVersion() {
        User user = existingUser("device-A", 3);
        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(false);

        BusinessException e = assertThrows(BusinessException.class,
                () -> authService.login(loginRequest("device-B"), "1.2.3.4"));

        assertEquals(ErrorCode.PASSWORD_ERROR.getCode(), e.getCode());
        assertEquals(3, user.getTokenVersion(), "密码错误不该影响任何人");
        verify(userMapper, never()).update(any(), any());
    }

}
