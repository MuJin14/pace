package com.campusrun.server.service.impl;

import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.ChatPreference;
import com.campusrun.server.entity.DeviceToken;
import com.campusrun.server.mapper.ChatPreferenceMapper;
import com.campusrun.server.mapper.DeviceTokenMapper;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.UserService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 账号注销（合规要求的「删除权」）必须把该用户的数据清干净。
 *
 * <p><b>为什么补这组测试</b>：早期实现的 {@code deleteAccount} 显式清理了 8 张表，
 * 但**漏了 {@code chat_preference}（免打扰偏好）与 {@code device_token}（推送令牌）**。
 *
 * <p>漏掉 {@code device_token} 的后果最严重：账号已注销，令牌仍指向该用户 id，
 * 于是推送会继续往**这台已经换人的手机**发通知 —— 属于隐私泄露。
 * 本轮新增的免打扰功能也让 {@code chat_preference} 变成了必须清理的表。
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class DeleteAccountCleanupTest {

    @Autowired
    private AuthService authService;
    @Autowired
    private UserService userService;
    @Autowired
    private ChatPreferenceMapper chatPreferenceMapper;
    @Autowired
    private DeviceTokenMapper deviceTokenMapper;
    @Autowired
    private UserMapper userMapper;

    private long register(String phone, String nickname) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname(nickname);
        LoginResponse resp = authService.register(req);
        assertNotNull(resp, "注册应成功");
        return resp.getUserId();
    }

    private void setMute(long userId, long friendId, boolean muted) {
        ChatPreference pref = new ChatPreference();
        pref.setUserId(userId);
        pref.setFriendId(friendId);
        pref.setMuted(muted ? 1 : 0);
        chatPreferenceMapper.insert(pref);
    }

    private void addDeviceToken(long userId, String token) {
        DeviceToken dt = new DeviceToken();
        dt.setUserId(userId);
        dt.setToken(token);
        dt.setPlatform("android");
        deviceTokenMapper.insert(dt);
    }

    @Test
    void deleteAccount_removesChatPreferences() {
        long userId = register("13900001001", "注销测试A");
        long otherId = register("13900001002", "注销测试B");

        setMute(userId, otherId, true);   // 我静音了对方
        setMute(otherId, userId, true);   // 对方静音了我

        userService.deleteAccount(userId);

        // 两个方向都不该残留：自己设的、以及别人对我设的
        Long remaining = chatPreferenceMapper.selectCount(null);
        assertEquals(0L, remaining,
                "注销后 chat_preference 必须清空（两个方向都要删），实际剩 " + remaining);
        assertNull(userMapper.selectById(userId), "用户本身也应被删除");
        assertNotNull(userMapper.selectById(otherId), "不该误删对方账号");
    }

    @Test
    void deleteAccount_removesDeviceTokens() {
        long userId = register("13900001003", "注销测试C");
        addDeviceToken(userId, "fcm-token-of-user-c");
        assertEquals(1, deviceTokenMapper.selectByUserId(userId).size());

        userService.deleteAccount(userId);

        assertTrue(deviceTokenMapper.selectByUserId(userId).isEmpty(),
                "注销后必须删除推送令牌，否则通知会继续发到这台已换人的手机（隐私泄露）");
    }

    @Test
    void deleteAccount_doesNotTouchOtherUsersTokens() {
        long userId = register("13900001004", "注销测试D");
        long otherId = register("13900001005", "注销测试E");
        addDeviceToken(userId, "token-of-d");
        addDeviceToken(otherId, "token-of-e");

        userService.deleteAccount(userId);

        assertEquals(1, deviceTokenMapper.selectByUserId(otherId).size(),
                "只删自己的令牌，不能误删别人的");
    }

    @Test
    void deleteAccount_cleansEverythingInOneGo() {
        long userId = register("13900001006", "注销测试F");
        long otherId = register("13900001007", "注销测试G");
        setMute(userId, otherId, true);
        setMute(otherId, userId, true);
        addDeviceToken(userId, "token-of-f");

        userService.deleteAccount(userId);

        assertEquals(0L, chatPreferenceMapper.selectCount(null), "会话偏好应清空");
        assertTrue(deviceTokenMapper.selectByUserId(userId).isEmpty(), "推送令牌应清空");
        assertNull(userMapper.selectById(userId), "用户应删除");
    }
}
