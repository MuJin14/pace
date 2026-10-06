package com.campusrun.server.controller;

import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.enums.UserRole;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.service.AuthService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 管理接口的权限边界（HTTP 层）。
 *
 * <p><b>为什么必须在这一层测</b>：Service 层写对 `@PreAuthorize` ≠ 客户端拿到 403。
 * 实测发现一个真实缺陷：`AccessDeniedException` 没有专门的处理器，
 * 被兜底的 `@ExceptionHandler(Exception.class)` 吞掉，
 * 返回 **HTTP 200 + body code=403** —— 调用方只看状态码会以为请求成功。
 *
 * <p>这与文档里记载的 `ForbiddenException` 问题完全同类，所以固化在这里：
 * **权限拒绝必须让 HTTP 状态码本身就是 403**。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Transactional
class AdminAccessControlTest {

    private static final String USERS = "/api/v1/admin/users";

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private AuthService authService;
    @Autowired
    private UserMapper userMapper;

    private String registerAndGetToken(String phone, String nickname) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname(nickname);
        LoginResponse resp = authService.register(req);
        return resp.getToken();
    }

    /**
     * 注册并把角色改成 ADMIN，**然后重新登录拿新 token**。
     *
     * <p>为什么必须重新登录：角色是写在 **JWT claim** 里的
     * （见 `JwtTokenProvider.generate(..., role, ...)`），
     * 所以权限在**签发那一刻就固化了** —— 改库不会影响已签发的 token。
     * 这也是为什么「提权后要让用户重新登录」。
     */
    private String registerAdmin(String phone, String nickname) {
        registerAndGetToken(phone, nickname);
        User u = userMapper.selectOne(
                new com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper<User>()
                        .eq(User::getPhone, phone));
        u.setRole(UserRole.ADMIN.getCode());
        userMapper.updateById(u);
        return login(phone);
    }

    /** 用已知密码重新登录，拿到带最新角色的 token。 */
    private String login(String phone) {
        var req = new com.campusrun.server.dto.request.LoginRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        return authService.login(req).getToken();
    }

    @Test
    void adminCanListUsers() throws Exception {
        String token = registerAdmin("13922220001", "管理员访问");

        mockMvc.perform(get(USERS).header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.list").isArray());
    }

    @Test
    void normalUserGetsHttp403NotHttp200() throws Exception {
        String token = registerAndGetToken("13922220002", "普通用户访问");

        // 关键断言：状态码本身必须是 403。
        // 这条曾经失败 —— 那时返回的是 200 + body code=403，
        // 前端 catch 不到，会把「没权限」当成「查到了但没有数据」。
        mockMvc.perform(get(USERS).header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value(403));
    }

    @Test
    void anonymousGets401() throws Exception {
        mockMvc.perform(get(USERS)).andExpect(status().isUnauthorized());
    }

    @Test
    void normalUserCannotResetSomeoneElsePassword() throws Exception {
        String adminToken = registerAdmin("13922220003", "管理员重置");
        String victimToken = registerAndGetToken("13922220004", "被重置对象");
        Long victimId = userMapper.selectOne(
                new com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper<User>()
                        .eq(User::getPhone, "13922220004")).getId();

        // 普通用户直接打管理员的「重置密码」接口 —— 这是最危险的越权，
        // 成功就等于任何人都能接管他人账号
        mockMvc.perform(post(USERS + "/" + victimId + "/reset-password")
                        .header("Authorization", "Bearer " + victimToken))
                .andExpect(status().isForbidden());

        // 管理员则应当能用（说明接口本身是通的，不是「全都 403」的假通过）
        mockMvc.perform(post(USERS + "/" + victimId + "/reset-password")
                        .header("Authorization", "Bearer " + adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.temporaryPassword").isNotEmpty());
    }

    @Test
    void normalUserCannotSeePasswordResetRequests() throws Exception {
        String token = registerAndGetToken("13922220005", "普通用户看申请");

        mockMvc.perform(get("/api/v1/admin/password-reset-requests")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden());
    }

    @Test
    void submitResetRequestWorksWithoutLogin() throws Exception {
        // 用户就是登不上才来申请的，所以这个接口必须匿名可用
        mockMvc.perform(post("/api/v1/password-reset-requests")
                        .param("phone", "13922220006"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void myRequestStatusStillRequiresLogin() throws Exception {
        // ⚠️ 只放行了 POST 提交，`/mine` 必须仍然需要登录。
        // 如果当初写成 `/api/v1/password-reset-requests/**` 放行，
        // 攻击者就能匿名查询任意申请记录 —— 这条测试防止那种回归。
        mockMvc.perform(get("/api/v1/password-reset-requests/mine"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void appVersionEndpointWorksWithoutLogin() throws Exception {
        // 更新提示应该在登录前就可能出现，不该被登录拦住
        mockMvc.perform(get("/api/v1/app/version"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.latest").exists());
    }
}
