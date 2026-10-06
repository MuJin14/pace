package com.campusrun.server.controller;

import com.campusrun.server.security.JwtTokenProvider;
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
 * 不存在的路径必须返回 404，而不是「HTTP 200 + body code=500」。
 *
 * <p>此前 {@code NoResourceFoundException} 被全局兜底处理器吞成 500，
 * 会导致调用方按 HTTP 状态码判断时误以为请求成功，排查时又被
 * 「服务器内部错误」误导去找服务端故障。这里把该行为固化。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class NotFoundHandlingTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtTokenProvider jwtTokenProvider;

    /**
     * 令牌里用的用户 id，刻意取一个**不存在**的号。
     *
     * <p>⚠️ 为什么不用真实用户（例如 id=1）：
     *
     * <p>本用例测的是**路由**（未知路径应当 404，而不是被全局兜底吞成 500），
     * 不需要一个真实用户。而十几个 {@code @SpringBootTest} 共用同一个 H2 内存库，
     * 其它测试类会注册/登录，并因此把那个用户的 {@code token_version} 递增。
     * 一旦用了真实用户 id，这里就得跟着读它当时的版本 ——
     * 用例之间产生隐式依赖，表现为「单独跑通过、全量跑拿到 401」（实测踩到）。
     *
     * <p>用不存在的用户时过滤器查库查不到，`known=false`，
     * 版本校验与改密吊销都会被跳过，令牌恒被接受，依赖被彻底切断。
     * 这也更贴合本用例的语义：无论鉴权结果如何，未知路径都该是 404。
     */
    private static final long TOKEN_USER_ID = 999_999L;

    private String accessToken() {
        return jwtTokenProvider.generateAccessToken(
                TOKEN_USER_ID, "CR-99999999", 0, 0);
    }

    @Test
    @DisplayName("不存在的接口路径 → HTTP 404 且 body code=404")
    void unknownPath_returns404() throws Exception {
        mockMvc.perform(get("/api/v1/this-endpoint-does-not-exist")
                        .header("Authorization", "Bearer " + accessToken()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value(404));
    }

    @Test
    @DisplayName("已存在控制器下的错误子路径同样返回 404")
    void unknownSubPath_returns404() throws Exception {
        mockMvc.perform(get("/api/v1/leaderboard/me")
                        .header("Authorization", "Bearer " + accessToken()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value(404));
    }
}
