package com.campusrun.server.security;

import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.entity.User;
import com.campusrun.server.enums.UserRole;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.service.AuthService;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 角色变更必须**立即生效**（而不是等 token 过期）。
 *
 * <p><b>修复的隐患</b>：角色原先只从 JWT claim 读取，而 claim 在签发时就固化了。
 * 于是把某个账号从管理员改回普通用户后，他手上那枚 access token
 * 在剩余有效期内（最长 2 小时）**仍然是管理员** ——
 * 撤销一个管理员本该立刻生效，这是权限撤销场景下的真实漏洞。
 *
 * <p>现在权限一律以数据库为准（`JwtAuthenticationFilter.resolveCurrentRole`），
 * 带 60 秒 TTL 缓存。测试里通过清缓存模拟 TTL 过期。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Transactional
class RoleChangeTakesEffectTest {

    private static final String USERS = "/api/v1/admin/users";

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private AuthService authService;
    @Autowired
    private UserMapper userMapper;
    @Autowired
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    private String register(String phone, String nickname) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname(nickname);
        return authService.register(req).getToken();
    }

    private String login(String phone) {
        LoginRequest req = new LoginRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        return authService.login(req).getToken();
    }

    private void setRole(String phone, UserRole role) {
        User u = userMapper.selectOne(
                new LambdaQueryWrapper<User>().eq(User::getPhone, phone));
        u.setRole(role.getCode());
        userMapper.updateById(u);
        // 模拟缓存 TTL 到期
        jwtAuthenticationFilter.clearRoleCacheForTest();
    }

    @Test
    void promotingToAdminTakesEffectWithoutReLogin() throws Exception {
        String token = register("13933330001", "提权测试");

        // 刚注册是普通用户
        mockMvc.perform(get(USERS).header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden());

        // 提权后**不重新登录**，同一个 token 就应当生效
        setRole("13933330001", UserRole.ADMIN);

        mockMvc.perform(get(USERS).header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    @Test
    void demotingFromAdminTakesEffectImmediately() throws Exception {
        // 先注册再提权，然后重新登录拿到「管理员 token」——
        // 关键：这枚 token 的 claim 里 role=1
        register("13933330002", "降权测试");
        setRole("13933330002", UserRole.ADMIN);
        String adminToken = login("13933330002");

        mockMvc.perform(get(USERS).header("Authorization", "Bearer " + adminToken))
                .andExpect(status().isOk());

        // 现在降权。**不重新登录**，那枚 claim 里写着 role=1 的旧 token
        // 必须立刻失去管理员权限 —— 这正是修复前做不到的。
        setRole("13933330002", UserRole.USER);

        mockMvc.perform(get(USERS).header("Authorization", "Bearer " + adminToken))
                .andExpect(status().isForbidden());
    }
}
