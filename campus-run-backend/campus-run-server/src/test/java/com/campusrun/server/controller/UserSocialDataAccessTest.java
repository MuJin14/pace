package com.campusrun.server.controller;

import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.FriendService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 他人运动数据的越权防护（HTTP 层）。
 *
 * <p>为什么必须有这一层测试：Service 层抛对异常 ≠ 客户端拿到 403。
 * 早先的实现只把错误码写进 body、HTTP 仍是 200，前端 `catch` 不到，
 * 会把「没权限」直接渲染成空态。这里固化「状态码本身就是 403」。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class UserSocialDataAccessTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private AuthService authService;

    @Autowired
    private FriendService friendService;

    @Autowired
    private JwtTokenProvider jwtTokenProvider;

    @Autowired
    private com.campusrun.server.mapper.UserMapper userMapper;

    private Long register(String phone, String nickname) {
        RegisterRequest request = new RegisterRequest();
        request.setPhone(phone);
        request.setPassword("secret123");
        request.setNickname(nickname);
        LoginResponse response = authService.register(request);
        return response.getUserId();
    }

    /**
     * 造一枚**版本正确**的 access token。
     *
     * <p>⚠️ 不能写死版本 0：单设备登录上线后，数据库里的 token_version 会因为
     * 登录而递增，写死版本的令牌会被判成「已在其他设备登录」返回 401
     * （见 NotFoundHandlingTest 里同样的说明）。
     */
    private String tokenOf(Long userId, String uniqueId) {
        var u = userMapper.selectById(userId);
        int version = u == null ? 0 : u.getTokenVersion();
        return jwtTokenProvider.generateAccessToken(userId, uniqueId, 0, version);
    }

    @Test
    @DisplayName("陌生人看他人运动记录 → HTTP 403 且 body code=403")
    void stranger_activities_returns403() throws Exception {
        Long me = register("13900001001", "越权甲");
        Long other = register("13900001002", "越权乙");

        mockMvc.perform(get("/api/v1/user/" + other + "/activities")
                        .header("Authorization", "Bearer " + tokenOf(me, "00000001")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value(403));
    }

    @Test
    @DisplayName("陌生人看他人勋章墙 → HTTP 403")
    void stranger_badges_returns403() throws Exception {
        Long me = register("13900001003", "越权丙");
        Long other = register("13900001004", "越权丁");

        mockMvc.perform(get("/api/v1/user/" + other + "/badges")
                        .header("Authorization", "Bearer " + tokenOf(me, "00000002")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value(403));
    }

    @Test
    @DisplayName("好友看运动记录 → HTTP 200（权限放行）")
    void friend_activities_returns200() throws Exception {
        Long me = register("13900001005", "放行甲");
        Long other = register("13900001006", "放行乙");

        // 建立双向好友关系
        friendService.sendRequest(me, other);
        var requests = friendService.incomingRequests(other);
        friendService.acceptRequest(other, requests.get(0).getRequestId());

        mockMvc.perform(get("/api/v1/user/" + other + "/activities")
                        .header("Authorization", "Bearer " + tokenOf(me, "00000003")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    @DisplayName("看自己的运动记录 → HTTP 200")
    void self_activities_returns200() throws Exception {
        Long me = register("13900001007", "自己甲");

        mockMvc.perform(get("/api/v1/user/" + me + "/activities")
                        .header("Authorization", "Bearer " + tokenOf(me, "00000004")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    @DisplayName("未登录访问 → 401（鉴权先于权限判断）")
    void anonymous_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/user/9999/activities"))
                .andExpect(status().isUnauthorized());
    }
}
