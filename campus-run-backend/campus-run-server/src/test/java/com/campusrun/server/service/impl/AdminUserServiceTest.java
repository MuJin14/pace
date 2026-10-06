package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.AdminUserItem;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.dto.response.PasswordResetRequestItem;
import com.campusrun.server.dto.response.PasswordResetResult;
import com.campusrun.server.entity.PasswordResetRequest;
import com.campusrun.server.entity.User;
import com.campusrun.server.enums.UserRole;
import com.campusrun.server.mapper.PasswordResetRequestMapper;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.service.AdminUserService;
import com.campusrun.server.service.AuthService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 管理员后台（找回密码）。
 *
 * <p>背景：App 没有邮箱字段、也没有短信服务，用户忘记密码后无法自助找回。
 * 方案是给少量受信任账号开管理员权限，由管理员协助重置。
 *
 * <p>这组测试的重点是**安全边界**，不只是「功能能用」：
 * 管理员能重置别人、不能重置自己、重置后旧令牌必须失效、申请提交不能变成手机号枚举器。
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class AdminUserServiceTest {

    @Autowired
    private AdminUserService adminUserService;
    @Autowired
    private AuthService authService;
    @Autowired
    private UserMapper userMapper;
    @Autowired
    private PasswordResetRequestMapper resetRequestMapper;
    @Autowired
    private PasswordEncoder passwordEncoder;

    private long register(String phone, String nickname) {
        RegisterRequest req = new RegisterRequest();
        req.setPhone(phone);
        req.setPassword("secret123");
        req.setNickname(nickname);
        LoginResponse resp = authService.register(req);
        return resp.getUserId();
    }

    private void makeAdmin(long userId) {
        User u = userMapper.selectById(userId);
        u.setRole(UserRole.ADMIN.getCode());
        userMapper.updateById(u);
    }

    // ── 用户查询 ─────────────────────────────────────────────────

    @Test
    void listUsers_canSearchByPhoneNicknameAndUniqueId() {
        long id = register("13911110001", "搜索目标甲");

        // 按昵称
        PageResponse<AdminUserItem> byNick = adminUserService.listUsers("搜索目标甲", 1, 20);
        assertTrue(byNick.getList().stream().anyMatch(u -> u.getUserId().equals(id)),
                "应按昵称搜到目标用户");

        // 按手机号
        PageResponse<AdminUserItem> byPhone = adminUserService.listUsers("13911110001", 1, 20);
        assertEquals(1, byPhone.getList().size(), "手机号应精确命中一个");

        // 按专属 ID
        User u = userMapper.selectById(id);
        PageResponse<AdminUserItem> byUnique = adminUserService.listUsers(u.getUniqueId(), 1, 20);
        assertTrue(byUnique.getList().stream().anyMatch(x -> x.getUserId().equals(id)),
                "应按专属 ID 搜到目标用户");
    }

    @Test
    void listUsers_neverExposesPasswordHash() {
        register("13911110002", "不该泄漏哈希");
        PageResponse<AdminUserItem> page = adminUserService.listUsers("13911110002", 1, 20);

        // AdminUserItem 里根本没有密码字段 —— 用反射确认，防止将来有人「顺手」加上
        for (var field : AdminUserItem.class.getDeclaredFields()) {
            String n = field.getName().toLowerCase();
            assertFalse(n.contains("password") || n.contains("hash"),
                    "管理后台的用户列表不得包含密码相关字段，却出现了: " + field.getName());
        }
        assertEquals(1, page.getList().size());
    }

    // ── 重置密码 ─────────────────────────────────────────────────

    @Test
    void resetPassword_changesPasswordAndReturnsUsableTemporaryOne() {
        long admin = register("13911110003", "管理员甲");
        long target = register("13911110004", "被重置者甲");
        makeAdmin(admin);

        PasswordResetResult result = adminUserService.resetPassword(admin, target);

        assertNotNull(result.getTemporaryPassword());
        // 固定为 123456：它只是**一次性进门凭证**，不是最终密码。
        // 用户可以（也应该）登录后立刻到「我的 → 修改密码」改成自己的，
        // 那里的长度下限仍是 8 位。
        assertEquals("123456", result.getTemporaryPassword());

        // 临时密码必须真的能用
        var login = authService.login(loginReq("13911110004", result.getTemporaryPassword()));
        assertNotNull(login, "用临时密码应能登录成功");

        // 旧密码必须失效
        assertThrows(BusinessException.class,
                () -> authService.login(loginReq("13911110004", "secret123")),
                "重置后旧密码必须失效");
    }

    @Test
    void resetPassword_invalidatesOldRefreshTokens() {
        long admin = register("13911110005", "管理员乙");
        long target = register("13911110006", "被重置者乙");
        makeAdmin(admin);

        // 记录重置前的 tokenInvalidBefore（注册时通常为 null）
        User before = userMapper.selectById(target);
        assertNull(before.getTokenInvalidBefore(), "新注册用户不该有令牌作废时间");

        adminUserService.resetPassword(admin, target);

        User after = userMapper.selectById(target);
        assertNotNull(after.getTokenInvalidBefore(),
                "重置密码必须写 token_invalid_before，否则旧的 refresh token（30 天有效）"
                        + "仍能换到新 access token，重置形同虚设");
    }

    @Test
    void resetPassword_refusesToResetOwnAccount() {
        long admin = register("13911110007", "管理员丙");
        makeAdmin(admin);

        BusinessException e = assertThrows(BusinessException.class,
                () -> adminUserService.resetPassword(admin, admin),
                "管理员不能在这里重置自己 —— 那等于给管理员账号一个"
                        + "「无需旧密码改自己密码」的后门");
        assertTrue(e.getMessage().contains("修改密码"), "错误信息应引导用户去用「修改密码」");
    }

    @Test
    void resetPassword_unknownUserRejected() {
        long admin = register("13911110008", "管理员丁");
        makeAdmin(admin);
        assertThrows(BusinessException.class,
                () -> adminUserService.resetPassword(admin, 999_999_999L));
    }

    @Test
    @DisplayName("临时密码是固定值 123456（便于管理员转达）")
    void resetPassword_returnsFixedTemporaryPassword() {
        long admin = register("13911110009", "管理员戊");
        long a = register("13911110010", "被重置者丙");
        long b = register("13911110011", "被重置者丁");
        makeAdmin(admin);

        // ⚠️ 这条断言在历史上是反过来的（`assertNotEquals`，要求随机）。
        //
        // 改成固定值是用户的明确要求，理由是**转达成本**：
        // 随机串（Hk7mPq2nRt）通过微信/口头传给同学时极易抄错，
        // 抄错后用户登不进来、又来一轮重置，管理员工作量翻倍。
        //
        // 安全性不靠密码强度，而靠：重置必须由管理员发起、
        // 重置会作废全部旧令牌、App 内提示尽快改密。
        String p1 = adminUserService.resetPassword(admin, a).getTemporaryPassword();
        String p2 = adminUserService.resetPassword(admin, b).getTemporaryPassword();
        assertEquals("123456", p1);
        assertEquals("123456", p2);
    }

    // ── 自助申请 ─────────────────────────────────────────────────

    @Test
    void createResetRequest_unknownPhoneIsSilentlyAccepted() {
        // 关键安全属性：不能因为「手机号没注册」而报错，
        // 否则这个未登录接口就成了「哪些号注册过本 App」的枚举器。
        adminUserService.createResetRequest("13999998888", "试一下");
        assertEquals(0L, resetRequestMapper.selectCount(null),
                "未注册手机号不应产生申请记录");
    }

    @Test
    void createResetRequest_deduplicatesPendingOnes() {
        register("13911110012", "重复申请者");
        adminUserService.createResetRequest("13911110012", "第一次");
        adminUserService.createResetRequest("13911110012", "第二次");
        adminUserService.createResetRequest("13911110012", "第三次");

        assertEquals(1L, resetRequestMapper.selectCount(null),
                "同一用户只应保留一条待处理申请，否则管理后台会被同一个人的多条申请刷屏");
    }

    @Test
    void handleRequest_resetsPasswordAndMarksRequestHandled() {
        long admin = register("13911110013", "管理员己");
        register("13911110014", "申请人甲");
        makeAdmin(admin);
        adminUserService.createResetRequest("13911110014", "换手机了");

        PasswordResetRequest req = resetRequestMapper.selectList(null).get(0);
        PasswordResetResult result = adminUserService.handleRequest(admin, req.getId());

        assertNotNull(result.getTemporaryPassword());
        PasswordResetRequest after = resetRequestMapper.selectById(req.getId());
        assertEquals(PasswordResetRequest.STATUS_RESET, after.getStatus());
        assertEquals(admin, after.getHandledBy(), "处理人要留痕");
        assertNotNull(after.getHandledAt());
    }

    @Test
    void handleRequest_cannotBeHandledTwice() {
        long admin = register("13911110015", "管理员庚");
        register("13911110016", "申请人乙");
        makeAdmin(admin);
        adminUserService.createResetRequest("13911110016", null);

        PasswordResetRequest req = resetRequestMapper.selectList(null).get(0);
        adminUserService.handleRequest(admin, req.getId());

        assertThrows(BusinessException.class,
                () -> adminUserService.handleRequest(admin, req.getId()),
                "已处理的申请不能重复处理（否则会反复生成新临时密码）");
    }

    @Test
    void rejectRequest_marksRejectedWithoutTouchingPassword() {
        long admin = register("13911110017", "管理员辛");
        long target = register("13911110018", "申请人丙");
        makeAdmin(admin);
        adminUserService.createResetRequest("13911110018", null);

        String hashBefore = userMapper.selectById(target).getPasswordHash();
        PasswordResetRequest req = resetRequestMapper.selectList(null).get(0);
        adminUserService.rejectRequest(admin, req.getId());

        assertEquals(PasswordResetRequest.STATUS_REJECTED,
                resetRequestMapper.selectById(req.getId()).getStatus());
        assertEquals(hashBefore, userMapper.selectById(target).getPasswordHash(),
                "拒绝申请不能改动密码");
        assertTrue(passwordEncoder.matches("secret123", userMapper.selectById(target).getPasswordHash()),
                "拒绝后原密码必须仍然有效");
    }

    @Test
    void myLatestRequest_returnsNewestOnly() {
        long user = register("13911110019", "申请人丁");
        assertEquals(null, adminUserService.myLatestRequest(user), "没有申请时返回 null");

        adminUserService.createResetRequest("13911110019", "第一次");
        PasswordResetRequestItem item = adminUserService.myLatestRequest(user);
        assertNotNull(item);
        assertEquals("第一次", item.getNote());
        assertEquals(PasswordResetRequest.STATUS_PENDING, item.getStatus());
    }

    @Test
    void listRequests_filtersByStatus() {
        register("13911110020", "申请人戊");
        adminUserService.createResetRequest("13911110020", null);

        assertEquals(1, adminUserService.listRequests(PasswordResetRequest.STATUS_PENDING).size());
        assertEquals(0, adminUserService.listRequests(PasswordResetRequest.STATUS_RESET).size(),
                "按状态过滤应生效");
        assertEquals(1, adminUserService.listRequests(null).size(), "status=null 返回全部");
    }

    private com.campusrun.server.dto.request.LoginRequest loginReq(String phone, String password) {
        var req = new com.campusrun.server.dto.request.LoginRequest();
        req.setPhone(phone);
        req.setPassword(password);
        return req;
    }
}
